# ADR-0006 — Background & Survival Architecture (Phase 05)

- **Status:** Accepted (2026-10-29)
- **Supersedes:** none (extends ADR-0002 flavor split, ADR-0004 single store)
- **Scope:** everything that keeps UDAO's capture alive when the app
  is closed, and every honest claim we make about it.

## Context

UDAO's core dependency is Android's NotificationListenerService — a
binding the OS grants, revokes, and (on most OEM skins) actively
kills. Phase 03 shipped a one-shot watchdog; Phase 05 builds the full
survival stack. The design space is full of banned doors: dataSync
FGS (Play scrutiny + Android 15 six-hour timeout), boot-started
foreground services (Android 15 ban), wake locks, `setExact` alarms,
reflection into OEM power managers. All banned — see the table.

## Decision — the survival truth table

| # | Scenario | Owner | Action | NEVER |
|---|----------|-------|--------|-------|
| 1 | Device reboot | `BootReceiver` | `requestRebind` + ensure the 30-min periodic pinger | start ANY foreground service from boot (Android 15 ban) |
| 2 | Listener drops, app foregrounded | `listenerHealthProvider` + health dashboard | user-tap Rebind / Hard-rebind buttons | auto-rebind storms from the UI |
| 3 | Listener drops, app dead | `HealthPinger` (Kotlin `Worker`, 30 min, KEEP, exponential backoff) | rebind → 5 s latch wait → component toggle → 5 s wait → escalate (≤ 1 notification / 24 h, cooldown in `SharedPreferences`) | wake locks, `setExact`, hot-loop polls |
| 4 | Process death | OS + WorkManager re-delivery + scenario 1/3 | binding re-requested on the next run; `ExitInfoProbe` shows why it died (API 30+) | pretending we survived |
| 5 | Persistent OEM killing | `KeepAliveService` — **specialUse FGS, user-armed only** | MIN-importance notice + 15-min heartbeat; `onTaskRemoved` deliberately does nothing; STOP action on the notice | auto-arming, `dataSync`/`mediaPlayback` FGS types |
| 6 | Weekly capture gaps | `WeeklyGapJob` (Dart workmanager, Sun ~20:00 IST, battery-not-low) | write gap payload to kv; flushed as a notification + card on the next app open | calling MainActivity-registered channels from the background isolate (impossible by design — see below) |
| 7 | Nightly hygiene | `NightlySweep` (Dart workmanager, 01:00–04:00 IST best-effort) + `WalWriter.sweep` from the pinger | raw-text purge > 24 h; WAL trim > 7 d; rollup to kv | network use (none exists), exact-time guarantees |
| 8 | OEM-specific settings | `udao/survival` channel → OEM deep links | try component → manual steps fallback, always | reflection hacks into OEM power managers |
| 9 | Battery optimization | flavor-split (below) | honest cards + system screens | lying about "guaranteed fix" |

## The two-engines constraint (why Kotlin owns recovery)

`workmanager`'s Dart tasks run on a **headless FlutterEngine**. The
channels registered in `MainActivity.configureFlutterEngine`
(`udao/capture/control`, `udao/survival`) exist only on the
activity's engine — a background isolate **cannot reach them**
(MissingPluginException / null). Therefore:

- **Kotlin `HealthPinger`** owns everything channel-free: rebind
  ladder, WAL sweep, escalation notifications (via
  `NotificationGateway`, not a Flutter plugin), snapshot persistence.
- **Dart workmanager jobs** own only DB-side work (they run on the
  background engine where sqflite_sqlcipher IS registered):
  raw-text purge, gap detection, kv payloads.
- **Gap alerts** pay a documented latency: the notification appears
  on the next app open (kv flush through the foreground engine).
  Honest > sneaky.

## workmanager integration facts (verified against 0.10.10)

- Dependency pinned **exact** `0.10.10` (background reliability >>
  convenience; `pubspec.yaml`).
- `Workmanager().initialize(callbackDispatcher)` in `main()` after
  the data-layer warm-up; `callbackDispatcher` is top-level +
  `@pragma('vm:entry-point')`. Widget tests never run `main()`, so
  app_smoke stays green.
- `registerPeriodicTask(uniqueName, taskName, frequency:, initialDelay:,
  constraints: Constraints(requiresBatteryNotLow: true),
  existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  backoffPolicy: BackoffPolicy.exponential)` — param names verified
  against the 0.10.10 API docs (2026-10-29).
- **No custom `Application` class**: with v2 embedding the background
  engine registers plugins automatically
  (`TODO-VERIFY(local)` — if the nightly job logs
  MissingPluginException for sqflite on a device, add the Application
  class per the workmanager README; it is not needed for the
  DB-registered path we use).

## Keep-alive service (specialUse) — the rules

- Declared `foregroundServiceType="specialUse"` +
  `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` with an honest subtype string.
- `FOREGROUND_SERVICE_SPECIAL_USE` permission in the **main** manifest
  (both flavors; power-only features stay flavor-gated separately).
- Started ONLY by an explicit user tap on the health dashboard —
  never from boot, never from a job, never silently.
- `onTimeout` (Android 15+ hook) stops the foreground part quietly.
- `onTaskRemoved` is **deliberately empty** — swipe-away must not
  kill us; the enforced contract lives in
  `test/features/survival/survival_contract_test.dart`.

## Battery optimization — the flavor split (extends ADR-0002)

| Flavor | Permission declared | UI chain |
|--------|--------------------|----------|
| `play` | — (Play-restricted) | system LIST screen (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`) → app details |
| `power` | `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (power overlay manifest) | direct system dialog → list screen → app details |

`SurvivalBridge.requestIgnoreBatteryOptimizations` double-guards
with `BuildConfig.FLAVOR != "power"`, so a play build cannot even
try. Enforced by contract test + static_verify.

## Notifications — one Kotlin gateway

All background notifications (escalation, gap alert, keep-alive
notice) are posted by `NotificationGateway` (Kotlin,
`NotificationManager`), channels `capture_health` (HIGH) and
`capture_service` (MIN). No `flutter_local_notifications` dependency;
no raw notification/SMS text ever crosses this boundary — titles and
bodies are static strings decided in Kotlin. The Dart side may post
only the two whitelisted health ids via the survival channel.

## Honesty rules (enforced by tests where possible)

1. Unreadable state → "pata nahi" / `null` — never a healthy guess
   (PowerState probes, standby bucket, exit info below API 30).
2. Battery claim: "<1%/day passive" refers to listener + 30-min
   watchdog only; the keep-alive service is explicitly excluded and
   labeled the user's call.
3. WorkManager timing is inexact — the 01:00–04:00 IST window is
   best-effort (initial-delay biased, period drifts). We say so in
   the UI copy and in docs/oem-survival.md.
4. Deep links to OEM screens are undocumented territory: every one
   is try/catch'd and every guide carries full manual steps.

## Consequences

- +1 dependency (`workmanager`), 0 notification plugins.
- `HealthPinger` (Kotlin) and `WatchdogPlanner` (pure Dart) are
  parallel specs of one ladder — the contract test + static_verify
  pin the shared constants (30 min / 5 s / 24 h); changes must touch
  both.
- The dashboard reads pinger state via prefs-mirrored
  `getWatchdogSnapshot` — no new streaming surface.
- TODO-VERIFY(local) items live in PHASE_05_COMPLETION_REPORT.md
  (workmanager Application class, OEM deep-link paths on real
  devices, keep-alive battery draw measurement).
