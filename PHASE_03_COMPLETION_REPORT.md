# PHASE 03 COMPLETION REPORT — Capture Engine I: Notification Listener

**Commit:** (this commit) · **Branch:** main · **Author:** udao-build-agent
**Scope:** Android notification-listener capture with a zero-loss WAL
architecture: native listener service + WAL writer + control bridge,
Dart capture stack (bridge seam, pipeline, replay, providers), the
permission gate UX (prime → deep-link → 30s test flight), settings
health card, allowlist asset, and the native⇄Dart contract test suite.
**Status:** **COMPLETE — statically verified** (no emulator run per the
phase contract). Local verification runbook in §8.

---

## 1. What was built

### 1.1 The zero-loss story (why this architecture)

A notification listener is the ONE capture source Android can revoke or
kill at any time, so the design assumes **the Dart engine may not be
running when money moves**:

```
system binds .capture.UdaoNotificationListener (survives process death)
        │ onNotificationPosted (binder thread)
        ▼
  [1] allowlist gate (pkg allow-list only, no text inspection)
  [2] WalWriter.append()  ← SYNCHRONOUS, on the binder thread,
                            BEFORE any push: the write is the law
  [3] live push to EventChannel IF the engine is listening
        │
        ▼  (engine may be dead — no matter, [2] already happened)
app start → main() → ProviderContainer → warm DB → bootstrapCapture():
  [4] pushAllowlist(assets/capture/allowlist.json)
  [5] replayWal(): readWAL → run every entry through the pipeline →
      ackWAL(maxTs)         ← at-least-once; dedup absorbs replays
  [6] captureDaemon: liveEvents → pipeline.run (rest of the session)
```

Rotation: WAL grows to 2 MB → shift to `.1` → `.2` (drop oldest);
`ack(upToTs)` drops acked entries + a 7-day sweep. Torn line writes
(partial line at crash) are skipped on read — a lost tail line is
tolerable, a corrupted ledger is not.

### 1.2 Native layer (`android/app/src/main/kotlin/in/udao/app/capture/`)

| File | Role |
|---|---|
| `WalWriter.kt` | @Synchronized `append` (binder thread), 2 MB rotate `.jsonl`→`.1`→`.2` in `noBackupFilesDir`, `readAll` oldest-first, torn-line skip, `ack(upToTs)` + >7d sweep via tmp+rename, single-thread `ioExecutor()` |
| `UdaoNotificationListener.kt` | skips group summaries; allowlist-first gate; `getCharSequence` extraction of title/text/bigText/subText; JSON line `{pkg,title,text,bigText,subText,ts}`; **WAL-append-before-push**; sink push on main handler; companion state (`isListenerConnected`, `lastEventAt`, `engineRunning`, `liveSink`); allowlist = `DEFAULT_ALLOWLIST` (UPI apps + top-15 bank ids, **TODO-VERIFY** §7) overridable from `no_backup/allowlist.json`; internal `CaptureLog` **never logs notification text**; NO `requestRebind` inside `onListenerDisconnected` (see §5.3) |
| `CaptureBridge.kt` | the Flutter boundary: EventChannel `udao/capture/stream`, MethodChannel `udao/capture/control` with `getWAL` / `ackWAL` / `listenerStatus` / `requestRebind` / `openListenerSettings` / `rebindViaToggle` / `pushAllowlist`; every branch `runCatching` → `result.error("UDAO_CAPTURE_ERROR", …)` (mirrors the `udao/platform` channel style); file IO on `WalWriter.ioExecutor`, results posted to main |
| `HealthPinger.kt` | WorkManager `Worker`: if `!isListenerConnected` → static `requestRebind`. `schedule(context, delayMs)` via `enqueueUniqueWork` **KEEP** (never stacks pings). Cadence ownership deliberately deferred to Phase 05 |
| `BootReceiver.kt` | `BOOT_COMPLETED` → `goAsync()` + thread: `requestRebind` + one delayed `HealthPinger.schedule` (~2 min) |

Manifest: `service .capture.UdaoNotificationListener` (exported,
`BIND_NOTIFICATION_LISTENER_SERVICE` + intent-filter) and `receiver
.capture.BootReceiver` (`BOOT_COMPLETED`; `RECEIVE_BOOT_COMPLETED`
permission existed since Phase 00). Gradle: +
`androidx.work:work-runtime-ktx:2.9.1` (`// verify-latest`).

### 1.3 Dart layer (`lib/features/capture/`)

| File | Role |
|---|---|
| `bridge/capture_channels.dart` | LOCKED channel/method/key constants (`abstract final class`) |
| `bridge/capture_raw_event.dart` | raw event model; `fullText` = title + (bigText ∥ text) + subText joined `\n`; `fromLine` (torn/malformed → null, never throws); `toLine` round-trip |
| `bridge/listener_status.dart` | `{connected, lastEventAt, componentEnabled}` + `granted` / `neverConnected` views |
| `bridge/capture_bridge.dart` | **the seam**: `abstract class CaptureBridge` (liveEvents, status, readWAL, ackWAL, requestRebind, openListenerSettings, rebindViaToggle, pushAllowlist) + `PlatformCaptureBridge` (EventChannel broadcast stream with defensive `handleError`; MethodChannel calls wrapped → `Result`, `PlatformException` → `CaptureFailure`) |
| `bridge/wal_replay.dart` | readWAL → run pipeline on every entry (drops included) → `ackWAL(maxTs)`. At-least-once by design |
| `pipeline/categorizer.dart` | ~75-alias merchant→`cat_*` map over the 16 seeds; unknown → null (rendered "Other") |
| `pipeline/ledger_events.dart` | `TxnCaptured` + broadcast `LedgerEvents` — future features (roast triggers, verdicts) subscribe here, not to the DB |
| `pipeline/capture_pipeline.dart` | orchestrator: builds `ParserInput(packageKey: pkg)` → `LedgerRepo.ingest` → kv counters (`cap_txn`/`cap_dup`/`cap_review`/`cap_drop_<reason>`/`cat_unknown`) → alias categorisation via `TxnDao.updateCategory` → `TxnCaptured` emit. **Platform-pure**: never imports flutter/services |
| `capture_providers.dart` | db/dao/repo/bridge/events/pipeline/daemon providers + `bootstrapCapture(container)` + `listenerHealthProvider` (Notifier: 60s Timer while built + `AppLifecycleListener` resume re-poll, both torn down on dispose) |
| `permission/listener_gate_screen.dart` | status-aware gate: prime card → `openListenerSettings`; returned-without-grant nudge copy; granted → animated confirm + 30s **test flight** with RAW/PARSED chips from the live streams; `Done — continue` → `/aaj` |

### 1.4 Wiring changes (existing files)

| File | Change |
|---|---|
| `lib/main.dart` | `ProviderContainer` created in `main()` + `UncontrolledProviderScope`; warm-up now calls `bootstrapCapture` after the DB opens (never blocks first frame, never throws) |
| `lib/core/constants/routes.dart` | + `captureGate = '/capture-gate'` |
| `lib/core/router/udao_router.dart` | + gate GoRoute (redirect logic untouched — the gate is not force-enforced) |
| `lib/features/onboarding/onboarding_screen.dart` | `_finish` → `context.go(Routes.captureGate)` |
| `lib/features/shell/screens/settings_screen.dart` | CAPTURE card (live status + dot + push to gate), converted to ConsumerWidget |
| `lib/l10n/app_localizations.dart` + both `.arb` | +18 keys (gate + settings), 82 keys × 2 locales, parity checked |
| `pubspec.yaml` | + `assets/capture/` |
| `assets/capture/allowlist.json` | 22 package ids (UPI apps + banks) |

### 1.5 Tests (`test/features/capture/` + smoke)

| File | Tests | What it locks |
|---|---|---|
| `bridge_contract_test.dart` | 12 | reads the Kotlin sources, manifest, pubspec, asset **as text** and asserts string parity: channels, all 7 methods, status keys, WAL file names + line keys, manifest service/receiver, allowlist wiring, MainActivity attach |
| `wal_replay_test.dart` | 6 | line round-trip, torn-line tolerance, fullText precedence, replay-ingest-dedup-drop + **ack advances past drops**, empty-WAL acks nothing, read-failure propagates |
| `capture_pipeline_test.dart` | 3 | **40-event e2e** on the real DB/parsers/dedup (28 unique + 5 dupes + 3 OTP + 2 promo + 2 pending): ledger=28, broadcast=28, every kv counter, alias categorisation + `cat_unknown`=5; drop-silence; idempotent re-run |
| `listener_gate_test.dart` | 2 | not-granted prime + deep-link + nudge; granted card + `Last event` stamp + 30s countdown + RAW/PARSED chips (timezone-portable assertion) |
| `app_smoke_test.dart` | 2 (updated) | fresh install now walks onboarding → **gate** → shell |

Test doubles: `fake_capture_bridge.dart` (recording fake + timer-free
`FakeListenerHealthNotifier` + `captureTestOverrides`) — no platform
channels anywhere in widget tests.

## 2. Locked contracts

- Channels: `udao/capture/stream` (EventChannel),
  `udao/capture/control` (MethodChannel) — enforced both sides by
  `bridge_contract_test.dart` AND `tools/static_verify.py` §6a.
- Methods: `getWAL`, `ackWAL`, `listenerStatus`, `requestRebind`,
  `openListenerSettings`, `rebindViaToggle`, `pushAllowlist`.
- Status keys: `connected`, `lastEventAt`, `componentEnabled`.
- WAL line schema: `{pkg, title, text, bigText, subText, ts}` (ts = ms).
- WAL files: `capture_wal.jsonl` / `.1` / `.2` in `noBackupFilesDir`.
- Error channel: every Kotlin branch funnels to
  `result.error("UDAO_CAPTURE_ERROR", …)`.

## 3. Design decisions & interpretations

1. **"Other" category does not exist in the seed set** (16 `cat_*`
   seeds, phase-02). Interpretation: unknown merchants keep
   `categoryId = null` (the ledger UI renders null as "Other") and bump
   a `cat_unknown` kv counter. Phase 06's classifier replaces the miss
   path; no schema change was made.
2. **Ack advances past drops and duplicates.** Replay processes every
   entry regardless of per-event outcome, then acks the max ts —
   otherwise a crashed replay would re-drop the same noise forever.
   Consequence (documented): a crash between "drop health-row written"
   and "ack" can re-insert that drop row on the next replay — a metrics
   skew only, never a duplicated txn (txns are deduped).
3. **No `requestRebind` in `onListenerDisconnected`.** A rebind storm
   from inside the listener is the classic way to get the component
   throttled or disabled by some OEMs. Rebinds are issued only from the
   safe static entry points: BootReceiver, HealthPinger, and the
   explicit user actions (gate/settings).
4. **WAL append is synchronous on the binder thread** — ordering and
   durability beat frame-rate purity for a ~0.1 ms local file append;
   the IO-heavy paths (readAll/ack) run on WalWriter's executor.
5. **Allowlist is native-owned.** The asset is pushed at boot and cached
   at `no_backup/allowlist.json`; the listener reads the cache (or the
   compiled default) before any Dart code runs.
6. **`ProviderContainer` in `main()`** (not `ProviderScope`'s internal
   one) so WAL replay + allowlist push start before the first frame and
   survive even if the widget tree is never built.
7. **Gate is not force-enforced** by the router redirect — re-reachable
   from settings; product calls it a gate, not a wall.

## 4. Verification performed (static, sandbox)

`python3 tools/static_verify.py` (extended for phase-03):

```
files checked: 67 (+16 capture dart, 5 capture kotlin)
regex literals compiled: 73
test statements in test/data: 148
expected runtime tests (flutter test test/data): 183
test statements in capture tests (incl. smoke): 25
ALL STATIC CHECKS PASS
```

New §6 checks (all green): channel/method/key string parity Kotlin↔Dart,
WAL file + line-key contract, manifest service/receiver/permissions,
gradle work-runtime, pubspec asset entry, allowlist JSON validity +
contents (≥20 ids, UPI musts), Kotlin symbol cross-references
(`CaptureLog.bridge/ioFailure` exist+used, `WalWriter.append/readAll/
ack/ioExecutor` referenced, companion state defined+consumed), l10n
getter↔arb parity for BOTH locales, routes/router/onboarding gate
wiring. Plus: bracket-balance on all capture `.dart` **and** `.kt`
files (Kotlin-aware stripper handles `${...}` templates), banned-pattern
sweep, `// phase-03` headers.

## 5. Test-count expectations for the local run

| Suite | Statements | Expected runtime |
|---|---|---|
| `flutter test test/features/capture` | 23 | **23** (no loop-registered tests) |
| `test/app_smoke_test.dart` | 2 | 2 (same count, gate leg added) |
| Whole suite | — | **334** (311 phase-02 + 23 new) |

## 6. TODO-VERIFY(local) inventory

| Where | What |
|---|---|
| `UdaoNotificationListener.kt` `DEFAULT_ALLOWLIST` | the 15 **bank app package ids** (SBI/HDFC/ICICI/Axis/Kotak/PNB/BoB/Canara/Union/IDFC/IndusInd/Yes/Federal/Airtel×2) — each must be confirmed against the exact ids on a real device (bank apps rebrand packages); UPI ids (GPay/PhonePe/Paytm×2/Cred/BHIM/Amazon) match the phase-02 parser corpus keys and are high-confidence |
| `android/app/build.gradle.kts` | `work-runtime-ktx:2.9.1` — verify-latest at build time |
| Real-device behaviour | listener grant flow on the user's Redmi (MIUI may show its own permission interstitial); boot-restore behaviour; `requestRebind` post-boot on MIUI |

## 7. Deviations from the phase prompt

None material. The prompt's "verify via static checks only" was honoured
(no SDK/emulator in the sandbox); the bridge contract test doubles as
the rename-guard the prompt asked for. One planned-but-dropped idea:
`tools/gen_arbs` regeneration — the script does not exist (phase-01
kdoc references it aspirationally); the 18 new keys were added to both
`.arb`s by a sorted-insert script and parity is enforced by the existing
l10n test + static_verify.

## 8. Local verification runbook (Dinesh — Windows 11, PS 5.1)

Run each line separately (PS 5.1 has no `&&`):

```powershell
cd D:\udao
flutter pub get
flutter analyze
python tools\static_verify.py
flutter test
flutter test test\features\capture
flutter build apk --flavor play --debug
```

Device check (optional but recommended for TODO-VERIFY): install the
play-flavor debug build, walk onboarding → gate → grant notification
access ("UDAO Capture" in system settings) → make a ₹1 UPI payment →
the test flight should show a RAW chip and a PARSED chip within 30 s;
then check the ledger tab.

## 9. Errata — round 1 (first local run, 2026-10-28)

The first local run (`flutter analyze` + `flutter test`) found **8
analyzer infos + 6 test failures**. Three root causes:

### 9.1 GPay parser keyed on a FAKE package id — production bug 🐛

`GPayParser.packageKey` shipped as `com.google.android.apps.nobu` —
the id the phase-02 corpus generator had invented. Real GPay
notifications carry **`com.google.android.apps.nbu.paysa`** and would
have **never matched**: every production GPay event would have fallen
through to `no_parser_match` and been silently counted as a drop. The
phase-03 40-event e2e caught it precisely because it feeds the REAL
package id (the phase-02 corpus could never see this — it shared the
same fake id as the parser).

Fixed:
- `gpay_parser.dart` packageKey → `com.google.android.apps.nbu.paysa`
  (header documents the errata);
- `test/fixtures/corpus_notifications.json`: 25 sample packageKeys →
  real id (input only — no expectation touches packageKey, so the
  golden corpus numbers are unaffected);
- `tools/gen_corpus.py` `GPAY_PKG` → real id;
- `test/data/repos/ledger_repo_test.dart`: 3 occurrences → real id;
- **new guard** in `tools/static_verify.py` §6g: parser package keys
  must be the real ids, and the fake id is banned in `lib/`, `test/`
  and the fixtures.

PhonePe (`com.phonepe.app`) and Paytm (`net.one97.paytm`) audited —
already correct.

### 9.2 UdaoButton renders labels UPPERCASED

`UdaoButton` applies `label.toUpperCase()`; the smoke/gate assertions
used the mixed-case l10n strings → `find.text('Open notification
access')` matched nothing. Fixed: assert and tap the rendered form
(`OPEN NOTIFICATION ACCESS`, `DONE — CONTINUE`). Lesson for all future
phases: **any find/tap on a UdaoButton label must use the uppercased
string**.

### 9.3 Gate test-2 checked the countdown after stopping it (test bug)

The 30s monitor STOPS the moment a txn is captured (by design — the ✓
state); the test emitted the PARSED chip first and then expected
`15 s`. Reordered: countdown asserts → RAW chip → PARSED chip → `✓` +
`15 s` gone + no pending timers.

### 9.4 Analyzer infos (8)

- `prefer_const_constructors` ×3: channel pair hoisted to
  `static const EventChannel _event` / `static const MethodChannel
  _control` in `capture_bridge.dart`; `const
  Err(CaptureFailure(...))` in the fake bridge; `const
  EmbeddingRow(...)` in `udao_database_test.dart` (pre-existing
  phase-02 file).
- `require_trailing_commas` ×4: `bridge_contract_test.dart` ×3,
  `wal_replay_test.dart` ×1.

Post-fix state: `static_verify.py` ALL PASS (§6g + §6h). Expected
local run: `flutter analyze` **0 issues**, `flutter test` **334/334**.

## 10. Errata — round 2 (second local run, 2026-10-28)

Round 1 brought the suite to 332/334 — both remaining failures in
`listener_gate_test.dart`, both real finds:

### 10.1 Prime state showed the wrong copy (product logic)

The not-granted branch rendered
`status.neverConnected ? gateStatusNever : gateStatusOff` — and a
fresh off-bridge (`lastEventAt == 0`) IS `neverConnected`, so the
freshest user saw **"Nothing captured yet"** instead of
**"Capture is still OFF"**. Fixed: the prime state now always shows
`gateStatusOff`; `gateStatusNever` ("Nothing captured yet") moved to
where it belongs — the GRANTED card when `lastEventAt == 0`. The
now-unused `ListenerStatus.neverConnected` getter was removed.

### 10.2 RAW chip assertion raced the frame (test determinism)

The fake bridge's broadcast controller used the default async
delivery: `emit()` queues a microtask and the chip renders only if it
drains before the pumped frame. The same assertion passed in run 1
and failed in run 2 (after a 15s-duration pump) — classic
timing-dependent test. Fixed three ways, belt and braces:
- fake bridge controller is now `broadcast(sync: true)` — `emit()`
  runs listeners inline, zero microtask dependence (locked by the new
  `static_verify.py` §6h guard);
- the PARSED chip (production `LedgerEvents` stays async on purpose)
  gets a double-pump — the standard idiom for async stream delivery;
- the granted test pins a tall surface
  (`tester.view.physicalSize = 800×2400 @1.0`) so every gate child —
  chips included — is BUILT: ListView is lazy and offscreen children
  do not exist for finders.

Post-fix state: `static_verify.py` ALL PASS (§6g + §6h). Expected
local run: `flutter analyze` **0 issues**, `flutter test` **334/334**.

## 11. Errata — round 3 (first local BUILD, 2026-10-28)

`flutter build apk --flavor play --debug` failed at
`:app:compilePlayDebugKotlin` — 8 Kotlin errors, three root causes.
This is the class of error only a real compile catches (no Android
SDK in the agent sandbox); each is now guarded statically.

### 11.1 NotificationListenerService imported from the WRONG package

`BootReceiver.kt`, `CaptureBridge.kt` and `HealthPinger.kt` imported
`android.app.NotificationListenerService` — the class actually lives
in **`android.service.notification`** (the service file itself had it
right, which is why only three files broke). Fixed all three; new
`static_verify.py` **§6i** enforces a VERIFIED import allowlist over
every import in the capture `.kt` files (each entry confirmed against
the public Android / androidx / Flutter API reference), plus an
explicit ban on the wrong-package import.

### 11.2 Group-summary check used a HIDDEN API

`sbn.isGroupSummary` does not resolve — `StatusBarNotification` has
no public `isGroupSummary()`; the accessor exists only as hidden API
on `Notification` (that's why `NotificationCompat` ships a public
wrapper). Fixed with the public bit check:
`(notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0`
(FLAG_GROUP_SUMMARY is public since API 20; minSdk 26). The captured
`notification` is also reused for extras extraction. New **§6j**
guard: `.isGroupSummary` banned, `FLAG_GROUP_SUMMARY` required.

### 11.3 Kotlin property initialiser forward reference

`private var allowlist = DEFAULT_ALLOWLIST` was declared ABOVE
`DEFAULT_ALLOWLIST` in the same companion — Kotlin property
initialisers cannot forward-reference ("Variable 'DEFAULT_ALLOWLIST'
must be initialized"). Fixed by moving the DEFAULT_ALLOWLIST block
(including its TODO-VERIFY kdoc) above its consumer. New **§6k**
guard: declaration index must precede first use.

Also: two unused imports (`ComponentName`, `Intent`) dropped from the
listener. The `device_info_plus` `Build.SERIAL` deprecation **warning**
in the build log comes from the pub.dev package itself (10.1.2) —
benign, not UDAO code, does not fail the build.

Post-fix state: `static_verify.py` ALL PASS (§6g–§6k). Expected local
run: `flutter analyze` **0 issues**, `flutter test` **334/334**,
`flutter build apk --flavor play --debug` **succeeds**.
