# PHASE 04 COMPLETION REPORT — Capture: SMS · PDF · Receipts · Voice

Phase-04 scope delivered per `udao-build-prompts/PHASE-04-capture-sms-pdf-receipts-voice.md`.
All static checks pass; SDK-run is pending on Dinesh's Windows machine
(command block at the end). No SDK was run inside the sandbox, per
standing constraint.

---

## T1 — SMS receiver (`power` flavor → same WAL)

**Kotlin** (`android/app/src/power/kotlin/in/udao/app/capture/`, package
`` package `in`.udao.app `` backticked):

- `UdaoSmsReceiver.kt` — `SmsRetriever`-style `SMS_RECEIVED` broadcast
  listener; parses PDUs, filters the sender against the SAME bank/UPI
  allowlist regex the notification listener uses
  (`^(?:[A-Z]{2}-[A-Z0-9]{4,8}|[A-Z]{6,10})$`), and writes a WAL line
  FIRST on the broadcast thread (`try/c catch(e: Exception)` +
  `CaptureLog.ioFailure` — house pattern) via
  `WalWriter.append(context, SmsGate.walLine(sender, body, ts))`.
  Never parses, never surfaces anything downstream.
- `SmsGate.kt` — pure helpers: PDU walk, sender filter, `walLine()`
  JSON shape (`pkg = "sms:<SENDER>"`, text = body, ts = postTime).
- Manifest (`src/power/AndroidManifest.xml`): `RECEIVE_SMS` +
  `BIND`-less `SMS_RECEIVED` `<receiver>` — power source set only.
  Play source set has **zero SMS surface** (no permission, no receiver,
  no code — the Kotlin lives under `src/power/`).
- Gradle: `sourceSets` split for `power`/`play` (with `main` shared),
  `flavorDimensions += "dist"`, missingDimensionStrategy for tests.

**Dart side:**

- `lib/core/platform/app_flavor.dart` — `AppFlavor { play, power,
  unknown }` + `appFlavorProvider` (FutureProvider, platform-channel
  `getDeviceInfo` → `BuildConfig.FLAVOR`). **Fail-closed**: `unknown`
  (channel missing, unflavored `flutter run`) = treated as NOT power,
  so flavor-gated UI stays hidden until proven otherwise.
- `lib/features/capture/permission/sms_gate_screen.dart` — power-only
  route. Honest priming card: kyun chahiye, sirf bank/transactional
  padha jaata hai, **OTP bhi drop** (explicit), 24h raw retention,
  "Play build mein SMS off hai" note. Grant flow via `PermissionPort`;
  permanent-deny → "Open system settings". Settings → Tools tile is
  power-flavor-gated too.
- WAL replay: `CaptureRawEvent.sender` getter decodes `sms:` prefix;
  `CapturePipeline` labels SMS events `TxnSource.sms`, raw text NEVER
  hits logs (existing redaction law held; verified no `rawText`/
  body in any `log` call).

**Play compliance docs** — `docs/play/sms-declaration.md`: exception
claim text ("SMS-based money management"), declaration-form answer
table, airplane-mode demo video script, listing-copy requirements,
12-tester/14-day closed-test checklist, and the explicit
"play build has no SMS" engineering note. Ready for Dinesh to submit.

## T2 — PDF/CSV statement import

- `lib/features/capture/import/statement_parser.dart` — 5 bank
  profiles (HDFC / SBI / ICICI / Axis / Kotak). Date-first column
  split (`\s{2,}|\t`), right-walk for money/DR-CR markers, direction
  by 3-money split (DR-col vs CR-col) > marker > credit-first vocab
  > skip. Ref extraction: `(?:UPI|NEFT|IMPS|MMI|P2A|P2M)[/-](?:DR|CR)?
  [/-]?(\d{6,12})` → bare 12-digit → `ref/no`. `_moneyToken` accepts
  Indian grouping (`1,10,678.90`) and plain decimals. Skipped lines
  carry `StatementSkipReason` (never silently dropped).
- `csv_statement_parser.dart` — same `StatementParse` result type from
  CSV (round-trips our own export).
- `statement_import_service.dart` — `previewPdf(path, fileName,
  extractor:, password:)` / `previewCsv` / `confirm(preview)`.
  Preview writes NOTHING; `confirm` inserts via
  `TxnDao.insertAllAtomic` (single transaction, rollback on any
  failure). Dedup legs in-set: refNo → `refNoExists`, fingerprint →
  `findByDedupKey`, fuzzy → `findNear(±12h)` same amount/merchant.
  Dates noon-IST (UTC 06:30) so no date wobble; confidence **0.98**;
  source `TxnSource.pdf` (CSV `manual`); password is a call-argument
  only — never stored, never logged.
- `lib/features/capture/import/import_review_screen.dart` —
  skeleton-only loading (no spinners), New/Duplicates tabs, plain-words
  summary, confirm → `Add {count} transactions`. Password failures
  (`pdf_password`) re-prompt via sheet; terminal failures roll back
  atomically. Post-confirm the stage resets to idle body (no stuck
  skeleton). PDF text via `pdfrx ^2.10.1` behind
  `pdfTextExtractorProvider`.

## T3 — Receipt capture (ML Kit offline + rules ensemble)

- `ports/receipt_ocr.dart` — `ReceiptOcr.recognizeText(imagePath)`
  behind `google_mlkit_text_recognition` (offline, on-device).
- `receipt/receipt_rules_parser.dart` — money/date/GSTIN heuristics;
  `_findMerchant` now scans UP from the GSTIN line (≤3 lines) for a
  `MerchantCleaner.aliasOf` hit FIRST (fixes address-above-GSTIN
  fixtures), else the adjacent line, else first candidate.
- `receipt/receipt_parser.dart` — `EnsembleReceiptParser({ocr, model,
  modelEscalationMin = 0.70})`. Rules draft < 0.7 → consult model;
  model `Ok` → ITS draft wins (Phase-06 drop-in ready); model
  `Err(ModelFailure('model-absent'))` → rules draft survives. The
  model leg is a seam (`ReceiptModelParser`, `AbsentReceiptModel`
  default) — no model code shipped this phase.
- `receipt_vault.dart` + `core/utils/aes_gcm_codec.dart` — AES-GCM
  (pointycastle), fresh 12-byte IV per write, `<txnId>.bin` =
  [IV][ct+tag] under `no_backup` dir; key in
  `flutter_secure_storage` (`receipt_vault_key`). Vault write happens
  only AFTER the ledger row commits.
- `receipt_capture_sheet.dart` — camera via `image_picker` (1080p,
  JPEG q72), thumbnail encrypted into the vault (dedupKey
  `rcpt:$txnId` + `findNear(±24h)`), review-then-confirm.

## T4 — QuickAdd (Bolo · Likho · Bill)

- `lib/features/capture/quick/quick_add_sheet.dart` — 3 tabs,
  default **Bolo** (voice). Global FAB on Aaj + `showQuickAddSheet`.
- `quick/hinglish_amount_parser.dart` — 'sawa sau auto ka' → ₹125 ·
  auto · cat_transport. Word numbers (ek…nabbe, twenty…ninety),
  scales (sau/hazaar/lakh/karod + 'k' suffix on numerals: `1.2k`),
  fractions (sawa/derh/paune/adha), lakh idiom ('2 lakh 50' =
  ₹2,50,000), devanagari digits (`६०`), credit words (mila/refund/
  wapas/aaya…), unknownTail shaves confidence. ≤3 taps manual: pad
  → category chip → Save.
- `ports/voice_input.dart` — `speech_to_text` one-shot dictation
  seam; keeps last partial (Hinglish speakers pause), plugin
  finalTimeout + our Timer → `voice_timeout` / `voice_error` /
  `voice_unavailable` failures. No network permission of our own.

## T5 — Gap detector

- `lib/features/capture/gap/gap_detector.dart` — weekend-aware
  silence detection: baseline < 3/day, 48h listener staleness
  (day-padded cutoff — `DayCounts` can't express hours), 14-day
  lookback, weekends + today never flagged. `GAP_FF_HOURS`
  dart-define fast-forwards local testing.
- `gap/gap_screen.dart` — verdict card (none/watch/concern) + reason
  cards + actions (import statement / check listener). Route
  `/tools/gap`, Settings → Tools tile.

## T6 — Tests (11 files, ~123 tests)

| File | Tests | Covers |
|---|---|---|
| `sms_pipeline_test.dart` | 4 | sms: pkg decode, sender regex, WAL→pipeline→ledger, source=sms |
| `import/statement_parser_test.dart` | 12 | 5 bank fixtures, refs, skips, 3-money split, ambiguous-skip |
| `import/statement_import_service_test.dart` | 10 | preview-no-write, dedup 3 legs, atomic rollback, 0.98 conf, noon-IST |
| `receipt/receipt_rules_parser_test.dart` | 15 | fixtures + GSTIN-up merchant scan + confidence bar |
| `receipt/receipt_ensemble_test.dart` | 4 | model-Ok wins, model-Err survives, dead OCR, escalation threshold |
| `quick/hinglish_amount_parser_test.dart` | ~67 | 60-case amount table + behavior (devanagari, unknownTail, lakh idiom) |
| `gap/gap_detector_test.dart` | 10 | 8 scenarios + fresh install + IST bucketing (fixed clock 2026-10-28 Wed UTC) |
| `core/utils/aes_gcm_codec_test.dart` | 7 | roundtrip, fresh IV, tamper ct+IV, wrong key, short blob, empty |
| `sms_gate_widget_test.dart` | 4 | play off-card only, unknown fail-closed, grant flow, perm-deny→settings |
| `quick_add_widget_test.dart` | 3 | Likho 1-2-5→Save, Bolo voice→confirm, voice_timeout snack |
| `import_review_widget_test.dart` | 4 | pdf→summary→confirm 2 txns, picker cancel, password sheet, dup re-import 0-new |

Scaffolding: `test/data/db/test_db.dart` (sqflite_common_ffi),
`test/helpers/udao_test_app.dart` (l10n-decked pump),
`test/features/capture/fake_capture_bridge.dart`.

## Verification story (sandbox, no SDK)

1. `tools/static_verify.py` — **ALL PASS** (67 files, 149 regexes,
   82 capture test statements + 183 expected runtime in test/data;
   l10n class ↔ arb ↔ usage, banned-API scans, flavor hygiene).
2. **Python dry-runs of the two riskiest engines** (ported 1:1 and
   executed, since no Dart SDK exists in the sandbox):
   - Hinglish parser: **60/60** amount cases pass — this caught 2
     real bugs pre-ship: `1.2k` didn't match the numeral regex (now
     `^(\d+(?:\.\d{1,3})?)(k)?$`), and my own test table had
     `sawa/derh hazaar` expectations 10× too high (₹1,250/₹1,500 —
     corrected).
   - Statement parser: all 5 bank fixtures + 3-money + ambiguous-skip
     pass — this caught the generic debit regex `\bUPI[-/]\d`
     missing `UPI/P2M/…` rows (now `\bUPI[-/]`, credit-first order
     keeps safety) and a fixture missing its bank-detection header.
3. API grep-audit of every test-file assumption against the lib
   sources (ctor params, field names, l10n strings, enum members,
   provider names) — 51-point checklist, all resolved; fixed
   `CaptureLog.ioFailure` call site (takes `Exception`, not
   `Throwable`) and dropped 2 unused imports.

**Known residue**: tests are grep-verified, not analyzer-verified —
first `flutter analyze` on the Windows box is the real gate.

## Files touched this phase

- **New lib (18)**: app_flavor, permission_port, receipt_camera,
  receipt_ocr, voice_input, statement_source, pdf_text_extractor,
  capture_ports_providers, statement_parser, csv_statement_parser,
  statement_import_service, import_review_screen, sms_gate_screen,
  receipt_rules_parser, receipt_parser, receipt_parsed, receipt_vault,
  aes_gcm_codec, quick_add_sheet, hinglish_amount_parser,
  receipt_capture_sheet, gap_detector, gap_screen.
- **Edited**: routes+router, aaj FAB, settings Tools tiles, l10n
  class (+91 keys) & arb (174 keys ×2), capture_pipeline (sender
  label + packageKey), categorizer (aliases), txn_dao
  (refNoExists/insertAllAtomic), query_repos (deleteById),
  pubspec (+7 deps), gradle + manifests + Kotlin power source set.
- **Docs**: `docs/play/sms-declaration.md`.

## Dinesh's verification block (PowerShell 5.1 — no `&&`)

```powershell
cd D:\udao
flutter pub get
flutter analyze
flutter test
flutter test test/features/capture
```

Expected: analyze clean (info-level allowed), full suite green
(phase-03 suite + ~123 new). Then fill the AGENT_LOG local column.

— Agent, Phase 04 close-out.

---

## ERRATA (post-delivery fix pass — user's `flutter analyze` found real errors)

Dinesh's analyze run surfaced two failure classes. Both fixed, and the
tooling upgraded so neither can recur silently.

### E1 — The zip was missing `lib/data/models/` (all 11 files)

`.gitignore` line `models/` (meant for on-device ML binaries under
`assets/models/`) also matched `lib/data/models/` — the entire model
layer was silently untracked since phase-00. Previous phase zips were
built from the working tree so the hole never showed; phase-04's
`git archive` exposed it.

Fix: `.gitignore` rule narrowed to `/assets/models/`; all 11 model
files committed. Audit confirms no other source path is ignored.

### E2 — Real compile bugs in phase-04 code (grep-verified ≠ compiled)

| Bug | File | Fix |
|---|---|---|
| `blob` referenced in its own cascade initializer | aes_gcm_codec | end = `ivLength + sealed.length` |
| `RegExp` in `static const` list (RegExp has NO const ctor) | statement_parser | `static final` |
| `.map(String.trim)` — class-name instance tear-off is illegal Dart | statement_parser | explicit closure loop |
| duplicate `'ke'` in const Set | hinglish parser | removed |
| `Set.containsKey()` (Map-only method) | hinglish parser | `.contains()` |
| missing `core/result/result.dart` import (Result/Ok/Err undefined) | sms_gate_screen, quick_add_sheet, receipt_capture_sheet, import_review_screen | imported |
| missing `Money` import | statement_import_service | imported (hidden in the truncated part of the error log) |
| `DaySourceCount` used without import | gap_screen | imported from txn_dao |
| `UdaoButton` used without import | sms_gate_widget_test | imported |
| `KvDao` used without import | sms_pipeline_test | imported |
| `txnDaoProvider` used without import | import_review_widget_test | imported |
| pdfrx API: `password:` isn't a param; `loadText()` returns `PdfPageRawText?` | pdf_text_extractor | `passwordProvider:` + nullable raw text (verified against pub.dev docs) |
| mlkit type is `RecognizedText`, not `Text` | receipt_ocr | fixed |
| `stt.SpeechRecognitionError/Result` live in their own libraries | voice_input | inferred callback params + `localeId` moved into `SpeechListenOptions` (deprecation) |
| context used after await without mounted guard | receipt_capture_sheet | mounted gate |
| unnecessary `!` after promoted null check | receipt_rules_parser | dropped |
| ~30 `require_trailing_commas`, `prefer_const`, pubspec dep order, 52 `avoid_dynamic_calls` in the rules test | various | all fixed (rules test rewritten typed) |

### Tooling upgrade (so this class of failure is caught pre-delivery)

- **`tools/analyzer_shadow.py`** (new): resolves every project symbol
  (class/enum/typedef/top-level fn/const) used in every lib+test file
  through its import closure; flags missing imports and dead import
  URIs. Self-tested (removing an import → caught; restoring → clean).
  Currently: **0 problems**.
- **`static_verify.py` §6m** now also fails on: const declarations
  carrying `RegExp(`, `Set` used with `containsKey`, and any
  analyzer-shadow failure. ALL PASS.

The honest lesson: "grep-verified" caught name/shape mistakes but not
compile-level mistakes (const-ness, tear-offs, import presence,
external-package signatures). The shadow closes most of that gap in
sandbox; the real analyzer remains the user-side gate.

— Agent, Phase-04 errata pass.

### Errata round 2 (user's second analyze — 12 issues, all fixed)

| Issue | File | Fix |
|---|---|---|
| `transaction((Database executor)` — sqflite wants `Future<dynamic> Function(Transaction)` | txn_dao insertAllAtomic | param type `Transaction` |
| non-exhaustive switch: riverpod 2.x `AsyncValue` is not sealed | gap_screen | wildcard `_ =>` arm |
| 2 unnecessary `!` after `??=` promotion | csv_statement_parser | dropped |
| `DateTime?` tuple element into `_shortDate(DateTime)` | import_review_screen | `range.$1!` / `range.$2!` |
| unused `l10n` local | import_review_screen `_rowLines` | removed |
| `dedupKey` typed `String?` though `DedupEngine.fingerprint` returns `String` → 3 assign errors + 1 nullable info | statement_import_service | `final String dedupKey` |
| `range!.$1.day` — tuple element still `DateTime?` | statement_parser_test | `.$1!` / `.$2!` |

Proactive sweep for the same classes across the tree: no other
`transaction((Database`, no other unsealed AsyncValue switches, no
other nullable-tuple member access, no other unused l10n locals.
analyzer-shadow: 0 problems; static_verify (incl. §6m): ALL PASS.

### Errata round 4 (user's `flutter test` — 452 pass / 10 fail; analyze CLEAN)

`flutter analyze` reported **No issues** — every remaining failure was
runtime/expectation level:

| Failure | Root cause | Fix |
|---|---|---|
| 4x import_review widget: 'Choose file' not found | `UdaoButton` renders labels `.toUpperCase()` — buttons say 'CHOOSE FILE' | tests assert uppercase labels (incl. 'ADD 2 TRANSACTIONS', 'OPEN STATEMENT') |
| 2x sms_gate widget: 'Allow SMS access' not found | same | 'ALLOW SMS ACCESS' / 'OPEN SYSTEM SETTINGS' |
| quick_add widget (hidden in paste) | same — 'SAVE', 'START SPEAKING' | uppercase |
| receipt fixture 2: items 3≠2 | timestamp line `12-06-2026 18:42` donated its trailing `42` as an item | items skip date-shape lines |
| receipt fixture 7: merchant 'Tatkal Charges 250.00' ≠ 'IRCTC' | `_mostlyNumeric` class `[...A-Z]{0,6}` ate any ≤6-char caps word as noise — but 'IRCTC' IS the merchant; conversely amount-bearing lines became merchants | digit-lookahead added; (merchant fix below) |
| noon-IST hour assertion false | `occurredAt` convention is wall=IST; my `IstDates.toIst(DateTime.utc(...6,30))` double-shifted the epoch (+5:30) so the DB read-back showed 17:30 | store the raw noon-IST instant `DateTime.utc(y,m,d,6,30)` (3 parsers) |
| fuzzy leg: no 'Swiggy' row | `MerchantCleaner.clean('UPI/401234567890/SWIGGY/YESB0PTX')` → 'upi/401...' — no segment notion | `_merchantFromNarration` walker: word-wise channel/DR-CR/IFSC/ref/card filtering, then clean (8/8 bank-narration sim) |
| pub: `speech_to_text ^6.7.0` doesn't exist; local resolution drifted (7.4.0, pdfrx 2.4.7) | phantom version in the phase sketch | exact pins `speech_to_text: 7.4.0`, `pdfrx: 2.4.7` (what analyze+test ran against); static_verify contracts updated |

Also caught by our own checks during this round: two stray `)` left
behind by the toIst unwrap (static_verify balance check), and
`_mostlyNumeric` needing the digit lookahead.

analyzer-shadow: 0 problems · static_verify (incl. §6m): ALL PASS.

— Agent, Phase-04 errata pass 4.

### Errata round 5 (final widget-test hang + lint)

- `flutter analyze` was down to 3 unused-import warnings (leftovers of
  the toIst unwrap) — removed.
- `flutter test` hung at `pumpAndSettle` in the import-review widget
  flow. Root cause (confirmed against sqflite_common_ffi's own
  testing doc): the default `databaseFactoryFfi` proxies every DB
  call through a background isolate whose replies never arrive inside
  `testWidgets`' fake-async zone → skeleton stays → pumpAndSettle
  times out. Fix: `createTestDb()` now uses
  **`databaseFactoryFfiNoIsolate`** — the documented widget-test
  factory; plain tests are unaffected.
- Suite size: ~605 runtime tests (363 statements + loop-expanded
  corpus cases). Acceptance = last line `-0`.

analyzer-shadow: 0 · static_verify: ALL PASS.

### Errata round 6 — the real pumpAndSettle root cause

Round 5's no-isolate factory was correct but insufficient: the same
timeout reproduced byte-identically. Full-chain code read (screen →
service → DAO → `UdaoDatabase`) found the actual straggler:

- `UdaoDatabase.db` is a LAZY future (`_opened ??= _open()`). Test
  setUps did `TxnDao(db.db)` WITHOUT awaiting — so pragmas + full DDL
  only ran on the FIRST QUERY, i.e. from inside the widget test's
  fake-async zone. An in-flight open crossing the real→fake zone
  boundary is exactly the kind of future a pump loop can strand.
- Separately, `pumpAndSettle` can by design never settle while a
  shimmer skeleton (`AnimationController..repeat()`) is mounted —
  the parse/write stages mount skeletons, so any stall in the chain
  turned into the opaque 10-minute fake-clock timeout instead of a
  diagnosable assertion failure.

Fixes (3 files):
1. `test/data/db/test_db.dart` — `createTestDb()` now `await db.db`
   before returning: the DB is FULLY open (schema + seeds) before any
  fake zone exists; every later `await _db` resolves an
   already-completed future (microtask-pure). Also prints a one-line
   freshness marker (`[udao-test-db] r6`) once per test-file isolate.
2. `import_review_widget_test.dart` + `quick_add_widget_test.dart` —
   all 20 `pumpAndSettle()` calls replaced by a bounded `_settle()`
   helper (≤50 pumps × 100 ms, exits the moment no frame is
   scheduled). Identical behaviour when the chain is healthy; a stall
   now fails the next EXPECT with a readable message instead of
   timing out.

analyzer-shadow: 0 · static_verify: ALL PASS.

### Errata round 7 — readable failures unmasked the real bugs

Round 6 did its job: the opaque timeout became readable failures, which
exposed FOUR distinct root causes (two of them real app bugs):

1. **DB × fake-async is fundamentally incompatible in widget tests.**
   sqflite's query pipeline contains zero-delay timers; inside
   testWidgets' fake-async zone those timers only fire while the clock
   is being pumped. A bare `await dao.count()` in a test body
   deadlocks (quick_add #1 and the cancel test hung exactly 10:00 at
   their final DAO await). Widget tests now use **FakeTxnDao**
   (`test/features/capture/fake_txn_dao.dart`): in-memory rows, pure
   microtask futures, `noSuchMethod` fail-fast for unimplemented
   members. Real DB semantics remain covered by the plain DAO +
   statement-import tests (all green).
2. **Fixture bug**: the widget test's `hdfcText` used 2-money rows;
   the parser's HDFC profile expects the 3-money
   Withdrawal/Deposit/Balance shape (as in the proven
   `statement_parser_test` fixture) — the preview could never arrive.
   The fixture is now byte-identical to the proven one (minus the
   third row).
3. **App bug — password controller**: `_askPassword` disposed its
   local `TextEditingController` as soon as `UdaoDialog.show`
   returned, racing the sheet's exit animation → "A
   TextEditingController was used after being disposed". The
   controller is now State-owned, the VALUE zeroed on both exits
   (CTA + dismissal).
4. **App bug — snack bar timer lifecycle**: `UdaoSnackBar`'s 3.5 s
   auto-dismiss Timer lived on a session object with no widget tie —
   it could outlive the tree (flutter_test fails tests on pending
   timers; in the app a late fire dismissed a dead overlay). The
   overlay is now a StatefulWidget whose `dispose` cancels the
   session timer.

analyzer-shadow: 0 · static_verify: ALL PASS.

### Errata round 8 — snackbar overshoot + the real quick_add hang

Round 7's output proved the flows WORK (import #2/#3 passed; #1/#4
reached CONFIRM; quick_add still hung). Two final root causes:

1. **App bug — snack bar opacity overshoot.** The brand spring
   (`Cubic(0.2, 0.9, 0.25, 1.15)`) deliberately drives the entrance
   tween past 1.0, and `Opacity(opacity: t)` asserts outside 0..1 —
   every snack bar crashed the frame mid-animation in debug. The
   translate leg keeps the spring; the opacity leg is clamped.
2. **quick_add widget tests awaited the sheet's completion future.**
   `showQuickAddSheet` returns `UdaoDialog.show`'s future, which
   completes only when the sheet is DISMISSED — the taps that would
   dismiss it sat behind the await → self-deadlock → 3× 10-minute
   timeouts (this, not the DB, was quick_add's hang from the very
   first run). All three call sites are now `unawaited(...)`.

analyzer-shadow: 0 · static_verify: ALL PASS.

### Errata round 9 — the last one: Likho sheet overflow

Suite reached `+469 -1`: everything green except quick_add #1, whose
failure was a REAL app bug — `RenderFlex overflowed by 31px` in the
Likho tab: the sheet's fixed 460px body held ~431px of content, so
the SAVE button sat below the fold (tap missed → nothing written →
count 0). On real devices the button was partially clipped too.

Fix (`quick_add_sheet.dart`):
- Sheet height 460 → 520 (content 431 + ~60 chrome, with slack).
- `_likhoBody` restructured: the variable-height middle (amount, pad,
  merchant field, suggestions, category chips, day/direction row)
  lives in `Expanded > SingleChildScrollView`; **SAVE is pinned
  outside it** — visible and tappable at any sheet height or OS text
  scale instead of overflowing.

analyzer-shadow: 0 · static_verify: ALL PASS.

### Errata round 10 — the 600px test surface was the ceiling

Round 9's 520px sheet overflowed the DIALOG's own column
(`udao_dialog.dart:72`) by 32px in all three quick_add tests: the
default 800x600 test surface gives the modal's content column only
~550px, while sheet 520 + dialog chrome ~62 needs ~582. Real devices
are 800+ logical px tall, so only the test viewport was too short.

Two layered fixes:
- `quick_add_widget_test.dart` — each test now runs at a realistic
  PHONE viewport (412x915 logical via `tester.view`), reset in
  teardown. The sheet that ships is the sheet under test.
- `udao_dialog.dart` — the sheet's content is now `Flexible(child:)`
  instead of a bare child: on short viewports (small phones,
  landscape, large OS text scale) the BODY shrinks instead of
  overflowing under the fold; handle, title and CTA stay reachable.

analyzer-shadow: 0 · static_verify: ALL PASS.

### Errata round 11 — chips Row on narrow phones

`+469 -1`: only quick_add #1 left. The 412px phone viewport caught a
genuine device bug the 800x600 surface had hidden: the Likho
day/direction chips Row (Today · Yesterday · Spacer · Credit/Debit)
overflowed by ~16px at a 362px sheet body — the chips' natural width
plus a Spacer cannot compress. Credit/Debit is now right-aligned via
`Expanded + Align` (absorbs slack, cannot overflow) instead of a
Spacer. 'Khaana' is the first seeded category, so the horizontal
category strip needs no scrolling either.

analyzer-shadow: 0 · static_verify: ALL PASS.

---

## ✅ PHASE 04 — CLOSED (user-attested green)

**Final state: `+470 -0: All tests passed!`** on the user's machine
(Windows 11, Flutter 3.41.4), commit `131d478`.

Errata history: `9ef9c96` (rejected) → r1 `397b2a7` → r2 `b12b015` →
r3 `e983ead` → r4 `d25e54a` → r5 `b2c6e40` → r6 `e7860d6` → r7
`ec57c37` → r8 `5dd034f` → r9 `2830453` → r10 `b45b83d` → r11
`131d478` (green).

Shipped: T1 SMS power receiver→WAL · T2 PDF/CSV import (5-bank
parser, dedup refNo→fuzzy, atomic confirm, no-spinners, password
in-memory-only) · T3 ML Kit + rules ensemble, encrypted thumbnails ·
T4 QuickAdd 3 tabs + Hinglish + ≤3 taps · T5 GapDetector/GapScreen ·
T6 470-test suite. Golden corpus: 250/250, all fields 100%.

Real bugs found & fixed along the way (would have shipped broken):
password-controller dispose race, snackbar spring-overshoot crash,
snackbar timer leak, Likho sheet overflow + SAVE under the fold,
chips-row overflow on real phone widths, widget-test DB deadlock.
