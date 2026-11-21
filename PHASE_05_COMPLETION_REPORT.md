# PHASE 05 COMPLETION REPORT — Background Survival & OEM Mastery

> Delivered against `udao-build-prompts/PHASE-05-background-oem-survival.md`.
> Architecture of record: **ADR-0006** (`docs/adr/`), user manual:
> **`docs/oem-survival.md`**, device protocol: **`tools/oem_test.sh`**.

## What this phase is

UDAO's ears (NotificationListenerService) live at the mercy of OEM
skin "optimizers". Phase 05 makes the app survive them — honestly:
no fake health, no banned Android doors, no unconditional promises.
Every claim the UI makes is either machine-checkable or it says
"pata nahi".

## T1 — ADR-0006 (the truth table, written FIRST)

`docs/adr/ADR-0006-background-architecture.md` — the decision table
for all 9 survival scenarios, the two-engines constraint (background
isolate cannot reach MainActivity channels → Kotlin owns recovery,
Dart jobs own DB-only work), the workmanager 0.10.10 integration
facts (param names verified against the pub.dev API docs 2026-10-29),
the specialUse-FGS rules, the battery-permission flavor split, and
the honesty rules. Every cross-file constant it defines is enforced
by `test/features/survival/survival_contract_test.dart` +
`tools/static_verify.py §6n`.

## T2 — Kotlin survival kit (`android/.../survival/` + pinger rewrite)

| File | What it does |
|---|---|
| `survival/NotificationGateway.kt` | The ONLY notification poster. Channels `capture_health` (HIGH) + `capture_service` (MIN). Whitelisted ids: escalation 1002, gap 1003, keep-alive 1001. No Flutter notification plugin. |
| `survival/PowerStateProbe.kt` | batteryOpt / powerSaver / backgroundRestricted / standbyBucket / deviceIdle — every read try/catch'd; unreadable → `null` (→ "pata nahi"). |
| `survival/ExitInfoProbe.kt` | ApplicationExitInfo (API 30+), last 5, Hinglish labels ("Memory kam thi, OS ne hata diya"). Below API 30 → honest empty list. |
| `survival/KeepAliveService.kt` | specialUse FGS (type + manifest property + `FOREGROUND_SERVICE_SPECIAL_USE`). MIN notice with **Band karo** STOP action. 15-min Handler heartbeat (rebind nudge + prefs beat). `onTimeout` honored. **`onTaskRemoved` deliberately empty** — enforced by contract test. Never auto-started. |
| `survival/SurvivalBridge.kt` | `udao/survival` channel — 11 methods (probes, keep-alive lever, whitelisted notification post, battery intents incl. the flavor-guarded direct dialog, OEM deep links). |
| `capture/HealthPinger.kt` (extended) | The recovery ladder: rebind → 5s latch → toggle → 5s → escalate (≤1/24h, prefs cooldown). Periodic 30-min KEEP + exponential backoff, armed from `MainActivity.onCreate` + `BootReceiver`. Every run: snapshot → prefs (Dart mirrors it), `WalWriter.sweep` (7-day trim), OEM-suspect flag. |
| `capture/WalWriter.kt` (+4 lines) | `@Synchronized sweep()` — the age-only trim the pinger calls. |
| `MainActivity.kt` | survival bridge attach, periodic pinger arming, `getDeviceInfo` + `model` / `versionRelease` / `isEmulator` (existing keys untouched — bridge contract parity held). |
| `capture/BootReceiver.kt` | + `schedulePeriodic` (KEEP — no-op if the chain survived). **NEVER starts a FGS** (contract-tested). |
| Manifests | main: KeepAliveService (specialUse + property + `stopWithTask="false"`); power: `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (+docs); play: deliberately NOTHING. |

## T3 — Battery optimization flow (flavor split)

`lib/features/survival/health/battery_optimization_card.dart`:

- exempt → calm lime card.
- not exempt → gold card; **power**: direct dialog → list → details
  (full chain); **play**: list → details (the direct dialog's
  permission is Play-restricted and not declared; the Kotlin bridge
  double-guards by `BuildConfig.FLAVOR`).
- nag discipline: `batteryNagAllowed` ≤ 1 full-priming per 7 days
  (kv stamp, best-effort write).

## T4 — OEM matrix (`lib/features/survival/oem/`)

- `oem_detector.dart` — 11 `OemId`s, BRAND-first matching
  (Poco/Redmi→xiaomi, iQOO→iqoo, honor-brand-on-Huawei→honor,
  HiHonor alias), manufacturer fallback, unknown→stock. Pure.
- `oem_guide_data.dart` — full typed guides for all 11: summary,
  numbered steps with deep-link buttons (component strings), ALWAYS a
  manual fallback, notes with version honesty, dontkillmyapp links.
- `oem_setup_flow_screen.dart` — detected maker → steps → deep links
  (try/catch → "path nahi hai, manual steps use karo") → manual card
  → versioned ack (`survival.oemSetupAck.v1`).

## T5 — Health dashboard (`lib/features/survival/health/`)

`HealthDashboardScreen` (`/health`, settings tile "Capture sehat"):

- **stamp**: SHARP / DHYAN DO / BAND from live listener + last-event
  age (`WatchdogPlanner.verdict` — pure, fixture-tested).
- **gap-alert card**: pending weekly finding → notification (via
  channel) + clear (the ADR-0006 latency, honestly labeled).
- **listener card**: bound/component state + Rebind + Hard-rebind
  (toggle) buttons through the capture bridge.
- **watchdog card**: Hinglish trace of the pinger's last run + OEM
  suspect note.
- **7-day sparkline**: custom painter over ledger counters
  (seen/parsed/deduped chips; empty → "koi counter nahi").
- **keep-alive card**: arm/stop the specialUse service (user-only).
- **battery card** (T3), **device-truth card** (PowerState rows,
  "pata nahi" where unreadable), **exit-info card** (API 30+ else
  honest empty), **OEM card** (guide CTA).
- **diagnostics export**: `SharePlus.instance.share` of a JSON
  summary — schema `udao.diagnostics.v1`, counters/states only,
  `privacy: no raw notification/sms text included, by design`.
- footer: battery honesty — "<1%/day passive" excludes the optional
  keep-alive (labeled the user's call).

## T6 — workmanager jobs (`lib/features/survival/jobs/`)

`background_jobs.dart` — `callbackDispatcher` (top-level,
`@pragma('vm:entry-point')`) switched on task name:

- **NightlySweep** (24h period, initial-delay → ~01:30 IST
  best-effort, `requiresBatteryNotLow`, KEEP, exponential backoff):
  raw-text purge >24h (`CaptureHealthDao.purgeRawTextOlderThan`) +
  kv rollup (`survival.nightlySweep.v1`).
- **WeeklyGapJob** (7d period, Sun ~20:00 IST, same constraints):
  GapDetector over 30 days (same feed as /gap) → payload to
  `survival.gapAlertPending.v1` (none → kv cleared).
- `initializeBackgroundJobs()` called once from `main()` after the
  data-layer warm-up; wrapped so a scheduling failure never blocks
  the app. Widget tests never run `main()` → smoke stays green.
- All scheduling math (`JobWindows`) and payloads are pure and
  boundary-tested (01:30 edge = next-day, Sunday 20:00 edges,
  24h cutoff survives exactly-24h rows).

## T7/T8 — docs + device protocol

- `docs/oem-survival.md` — the honest manual: what kills us, the
  ladder, keep-alive rules, per-maker matrix, flavor split, weekly/
  nightly jobs, the adb protocol, and "what we refuse to do".
- `tools/oem_test.sh` — read-only adb protocol (listener binding,
  doze whitelist, standby bucket, exit-info, job state, keep-alive
  service) + the manual drill reminder.

## T9 — Tests (9 files, 117 statements)

| File | Covers |
|---|---|
| `oem_detector_test.dart` | 30-case manufacturer×brand matrix (incl. case/whitespace, iQOO/Poco precision, unknown→stock, killer flags) |
| `oem_guide_test.dart` | structural invariants: 11 guides complete, every deep link a valid `pkg/cls`, manual fallback ALWAYS, vivo≠iqoo, nokia/stock link-free, huawei 3-toggle |
| `watchdog_planner_test.dart` | the ladder (all 5 outcomes + cooldown boundary at exactly-24h) + verdict stamps (SHARP/DHYAN DO/BAND) + explainLastRun |
| `survival_models_test.dart` | Kotlin-map→Dart parsing, honest defaults, standby-bucket labels |
| `background_jobs_test.dart` | window math edges, cutoff boundary, rollup/gap payload shapes, locked workmanager strings |
| `health_dashboard_widget_test.dart` | stamp fixtures ×3, gap-alert flush (post+clear+invalidate), keep-alive arm, battery card flavor split ×2 + exempt |
| `oem_setup_flow_screen_test.dart` | Poco→Xiaomi guide, deep-link fire + miss-fallback, versioned ack |
| `survival_contract_test.dart` | Kotlin⇄Dart⇄manifest parity: 11 methods, pref keys, cadences (30/5s/24h), onTaskRemoved ban, flavor guards, workmanager params, pubspec pin, device-info fields |
| `fake_survival_bridge.dart` | fakes + `survivalTestOverrides` (channels off, DB off — phase-04 kit applied: phone viewport, bounded pumps, unawaited hops, no awaited modals) |

## Verification story (sandbox, no SDK)

- `tools/static_verify.py` — **ALL STATIC CHECKS PASS**: new globs
  (19 survival Dart + 5 survival Kotlin), `// phase-05` headers,
  Kotlin import allow-list extended (verified against the public
  AndroidX/Android surface) + MainActivity now checked, §6n survival
  contract (channel parity, cadences, pref keys, bans, l10n
  en/hi branch sanity), arb parity (82 new keys × both files).
- `tools/analyzer_shadow.py` — 0 problems (catches missing
  imports/undefined project symbols).
- Manual type-level review pass (the phase-04 lesson): 6 real bugs
  caught and fixed before delivery — `final double yFor = (int v)=>…`
  function-type error, `unawaited(void)`, unused imports ×2,
  `androidx.core.app.Notification` (nonexistent class) in Kotlin,
  `ref as Ref` cast in the gap flush, en/Hindi mix in one widget
  expectation. `refresh()` calls unawaited (lint), route hop
  unawaited.
- workmanager API (0.10.10) verified against pub.dev API reference:
  `registerPeriodicTask(uniqueName, taskName, {frequency, flexInterval,
  inputData, initialDelay, constraints, existingWorkPolicy:
  ExistingPeriodicWorkPolicy, backoffPolicy, backoffPolicyDelay, tag})`.

## Files touched this phase

- **New Dart (11)**: `lib/features/survival/` — `survival_providers.dart`,
  `oem/{oem_detector,oem_guide_data,oem_setup_flow_screen}.dart`,
  `health/{survival_models,probe_bridge,watchdog_planner,
  health_dashboard_screen,battery_optimization_card}.dart`,
  `jobs/background_jobs.dart`.
- **New Kotlin (5)**: `survival/{NotificationGateway,PowerStateProbe,
  ExitInfoProbe,KeepAliveService,SurvivalBridge}.kt`.
- **Extended**: `HealthPinger.kt` (full ladder), `WalWriter.kt`
  (sweep), `MainActivity.kt` (+3 fields, bridge attach, onCreate
  arming), `BootReceiver.kt` (+periodic), main manifest
  (+KeepAliveService), power manifest (+permission), `main.dart`
  (+jobs init), `routes.dart`/`udao_router.dart` (+2 routes),
  `settings_screen.dart` (+health tile), `app_localizations.dart`
  (+83 getters), both `.arb` files (+83 keys), `pubspec.yaml`
  (workmanager 0.10.10 exact), `static_verify.py` (§6n + globs).
- **New tests (9) + docs (2) + tooling (1)**.

## Bans honored (contract-enforced where possible)

- ❌ dataSync FGS · ❌ FGS-from-boot · ❌ wake locks · ❌ setExact ·
  ❌ reflection into OEM managers · ❌ fabricated health states —
  the last one is a design rule: every unreadable probe returns null
  and renders "pata nahi" / "check nahi ho sakta".

## TODO-VERIFY(local) — Dinesh's first run

1. `flutter pub get` (new dep `workmanager 0.10.10`), then the usual
   `tools\local_verify.ps1`. Expected: analyze 0, tests green
   (470 + ~117 new ≈ 587).
2. **workmanager Application class**: with v2 embedding the
   background engine auto-registers plugins; if the nightly job ever
   logs a MissingPluginException for sqflite on a real device, add
   the custom Application class per the workmanager README (ADR-0006
   documents the exact step).
3. OEM deep links on the Redmi (MIUI 14/HyperOS): autostart +
   powerkeeper paths — the manual fallback covers a miss by design.
4. Keep-alive battery draw on-device (the "<1%/day passive" claim
   covers listener + watchdog only; keep-alive is labeled separately).
5. `bash tools/oem_test.sh` after install — the read-only protocol
   (docs/oem-survival.md §8).

## Dinesh's verification block (PowerShell 5.1 — no `&&`)

```powershell
cd D:\udao
flutter pub get
flutter analyze
flutter test
```


## ERRATA — round 1 (first local analyze + test run, 2026-10-29)

User's run: `flutter pub get` clean (workmanager 0.10.10 resolved),
`flutter analyze` **41 issues (6 errors / 35 infos)**, `flutter test`
**+553 / -6** — all 6 failures were compile-failures of files
importing the broken sources (every test that compiled, passed).

### The 6 errors — root causes and fixes

| # | Error | Root cause | Fix |
|---|---|---|---|
| 1 | `SharePlus` / `ShareParams` undefined (dashboard:279) | **API version drift, my mistake**: `SharePlus.instance.share(ShareParams(...))` is the share_plus **11+** API; the pinned 10.1.4 exposes the static `Share.share(text)` (verified against the 10.1.4 class docs). I assumed the new API without checking the resolved major — exactly the phase-04 lesson I was supposed to apply. | `await Share.share(json);` + permanent static_verify **§6o(b)** ban on `SharePlus.`/`ShareParams(` while share_plus is 10.x. |
| 2 | `PointMode` undefined (dashboard:653) | `flutter/material.dart` does **not** re-export `dart:ui`'s PointMode in this Flutter version (my memory of the painting export surface was wrong). | `import 'dart:ui' show PointMode;` |
| 3 | `List<DaySourceCount>` vs `List<DayCount>` (jobs:160) | Null-aware fallback literal `<DaySourceCount>[]` pinned the whole expression's type against the `List<DayCount>` declaration. | Split: `rows` (DaySourceCount) → `dayCounts` (DayCount) mapping, exactly like gap_screen. |
| 4 | `digit-separators` experiment not enabled (planner test ×7) | `1_000_000` needs SDK **language version ≥ 3.6**; the package's `environment.sdk` floor is lower, so the feature is off despite Dart 3.11. | Plain literals (`1000000000`) + permanent static_verify **§6o(a)** ban on `\d_\d` in string-stripped Dart (the contract test's `'5_000L'` is inside a string — legal). |

### The 35 infos (all fixed)

- `require_trailing_commas` ×15 (dashboard, probe_bridge, oem screen,
  4 test files) — my hand-formatting; each rewritten in tall style.
- `prefer_final_locals` (jobs `daysAhead`), `prefer_const_constructors`
  (jobs `GapDetector()`, fake `Ok<void>(null)`, wtest `ListenerStatus`),
  `prefer_const_declarations` (planner test `now = 10 * _dayMs`).
- `use_build_context_synchronously` ×3 (oem screen) — the method took
  a `BuildContext` PARAM while guarding with the STATE's `mounted`
  ("unrelated" to the analyzer). Dropped the param; the State's own
  context + mounted guard is the related pair.
- `sort_pub_dependencies` — workmanager inserted after share_plus;
  moved to its alphabetical slot (after uuid).

### Lessons (added to the permanent checks)

1. **Resolve-then-verify**: for ANY new package API, check the docs of
   the version that RESOLVES on the user's machine — "current" docs
   describe the latest major, which may not be the pinned one. (Same
   class as the phase-04 pdfrx/speech drift, and I repeated it —
   static_verify now hard-bans the 11+ names.)
2. **Export surface ≠ memory**: framework re-exports (PointMode via
   material) must be verified, not assumed — when in doubt, import
   from the defining library with `show`.
3. **Language version is per-package**: features newer than the
   pubspec's SDK floor (digit separators) are compile errors even on
   a newer toolchain. Now statically banned.
4. The 6 test files that failed to LOAD never executed — their
   assertions were re-traced by hand against the fakes (labels,
   locales, pump counts) before this errata shipped.

**Verification after errata:** static_verify ALL PASS (with the two
new §6o guards), analyzer_shadow 0 problems, digit-separator + API
sweeps clean across lib/ and test/.


## ERRATA — round 2 (second local test run, 2026-10-29)

`flutter pub get` clean, analyze **clean** (not re-run — nothing to
report), `flutter test` **+594 / -3**. All three failures were test
bugs, not product bugs:

| # | Failure | Root cause | Fix |
|---|---|---|---|
| 1 | planner: `contains('pehla run')` vs actual `'Pehla run baaki hai'` | Case-sensitive matcher vs a capital-P string — traced the fixture by eye, not against the source constant. | `contains('Pehla run')` |
| 2 | dashboard SHARP: `find.text('Seen')` found 0 | **StatChip renders `label.toUpperCase()`** (same convention as UdaoButton, documented in the phase-03 lessons — I checked the button, not the chip). The chips WERE rendered (as SEEN/PARSED/DUPES DROPPED) and the stats fixture HAD delivered. | Expect `'SEEN'`, `'PARSED'`, `'DUPES DROPPED'`. |
| 3 | Poco test: "A Timer is still pending even after the widget tree was disposed" | `FakeKvDao._neverDb = Future.delayed(24h)` creates a **FakeTimer** inside the test's fake-async zone. Because the field is a lazily-initialized STATIC, only the FIRST `FakeKvDao` construction per isolate creates the timer — so exactly one test per file failed, order-dependently (Poco passed every assertion; SHARP would have hit it too had its text expect passed). | `Completer<Never>().future` — a never-completing future with **zero timers**. |

### Lessons

1. **Label-transform sweep**: EVERY widget that renders user-facing
   strings must be checked for casing transforms before asserting on
   its text — the codebase convention is uppercase (UdaoButton AND
   StatChip). A quick grep for `toUpperCase` in core/ui is now part
   of my write-the-assertions checklist.
2. **Never-futures in test doubles**: `Future.delayed(...)` inside a
   fake creates a real FakeTimer in the fake-async zone — the
   correct inert never-future is `Completer<T>().future`. Worse, a
   static/late-initialized one makes the failure depend on TEST
   ORDER (only the first construction per isolate trips it) — the
   worst kind of flake to debug locally.

**Verification after errata:** static_verify ALL PASS, shadow 0,
hand-trace of the not-yet-executed tail of the SHARP test
(listener-bound text, exempt card, gap-card absence) against the
l10n en strings and fake defaults.
