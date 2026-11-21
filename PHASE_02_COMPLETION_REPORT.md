# PHASE 02 COMPLETION REPORT — Data Layer & Parsers

**Commit:** (this commit) · **Branch:** main · **Author:** udao-build-agent
**Scope:** encrypted persistence, DAOs, capture-to-ledger pipeline, bank/UPI
parsers, merchant cleaner, dedup engine, 250-sample golden corpus, CSV
export, 183 runtime tests (148 test statements; see §3).
**Status:** **COMPLETE & LOCALLY VERIFIED** — `flutter test` **311/311**,
`flutter test test/data` **183/183**, golden corpus **100.0% on every field**
(user-attested on Windows 11 / Flutter 3.41.4, round-2 commit; see §7).

---

## 1. What was built

### 1.1 Dependencies (`pubspec.yaml`)

| Change | Why |
|---|---|
| ❌ removed `sqflite ^2.3.3` | plain sqflite has **no `password:` param** — cannot key SQLCipher |
| ✅ added `sqflite_sqlcipher: ^3.0.0` | same sqflite API + `password:` on `openDatabase` (SQLCipher 4.5.6, validates passwords) |
| ✅ kept `sqlcipher_flutter_libs ^0.6.4` | ships the native cipher binary per-platform |
| ✅ added `crypto: ^3.0.3` | sha1 fingerprints / raw hashes (dedup engine) |
| ✅ dev `sqflite_common_ffi: ^2.3.7` | `flutter test` on desktop — **bundles sqlite3.dll, no Windows setup script needed** (a planned `tools/setup_sqlite3.ps1` was dropped as unnecessary) |

Both cipher and FFI packages re-export the **same `sqflite_common`
types** — `Database`, `OpenDatabaseOptions`, hooks — so production and
tests share one schema code path with identical type identity.

### 1.2 Models (`lib/data/models/`, 11 files)

`Txn` (+`TxnDirection`, `TxnSource`, hand-rolled sortable `TxnId` — no
uuid-v7 risk), `Category` (+ **16 fixed-id seed categories**, essentials:
Rent/Bill, Health, Education — roast-protected), `Budget`,
`Subscription`, `StreakState` (single-row, freeze tokens),
`Badge`+`ChallengeProgress`, `Jar`, `RoastEntry`, `CaptureEvent`,
`EmbeddingRow` (float64 BLOB), `PendingReviewEntry`. Every model: manual
`copyWith` / `==` / `hashCode` / `toJson` / `fromJson` / `toRow` /
`fromRow`. No codegen, no reflection — analysis-safe and snapshot-cheap.

### 1.3 Database core (`lib/data/db/`)

- **`schema.dart`** — versioned DDL: **13 tables** (12 from the prompt +
  `embedding` for Phase-06 vectors), 7 indexes incl. `uq_txn_dedup`
  (UNIQUE — the last dedup backstop), FK-safe wipe order. `dbVersion = 1`.
- **`migrations.dart`** — framework live from day one: `steps[v]` walk in
  order inside the open transaction; **downgrade ⇒ `DatabaseFailure`**
  (loudly refused, never silently reshaped).
- **`db_key_store.dart`** — 32 random bytes, base64, Keystore-backed
  (`flutter_secure_storage`), generated exactly once, never logged.
- **`udao_database.dart`** — the encrypted singleton:
  - `openProduction()` = `openDatabase('$dir/udao.db', password: key,
    version, onConfigure/onCreate/onUpgrade/onDowngrade, onOpen:
    logCipherHealth)` from `sqflite_sqlcipher`.
  - **Static schema hooks are the single source of truth.** Tests open
    `databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options:
    OpenDatabaseOptions(version, singleInstance: false, <same hooks>))` —
    byte-identical DDL, no drift possible, no `SqlCipherOpenDatabaseOptions`
    construction anywhere.
  - `onConfigure`: `cipher_page_size=4096`, `journal_mode=WAL`,
    `foreign_keys=ON` (unknown pragmas silently no-op on plain sqlite —
    exactly what FFI tests want).
  - `logCipherHealth` (production onOpen): probes `PRAGMA cipher_version`,
    logs `SQLCipher active: 4.5.6` or **errors on empty** (plaintext
    betrayal would be visible in logs + Settings, Phase 08).
  - `wipeAll()` — DPDP delete: all rows in FK order, categories reseeded,
    **VACUUM** so purged pages don't linger in the file.
  - `main.dart` now fires `unawaited(_warmUpDataLayer())` (guarded,
    logged) so the first user action never pays the key+migration cost.

### 1.4 DAOs (`lib/data/db/dao/`, 12 files)

All return `Result<T>`; every throw is scoped + logged and surfaces as
`DatabaseFailure` — the UI never sees a raw sqlite exception.

| DAO | Highlights |
|---|---|
| `TxnDao` | `upsertByDedupKey` (INSERT OR IGNORE, first capture wins), filtered `page` + `count`, `sumBetween`, `sumByCategory`, `totalsByDay`, `findNear` (10-min cross-source window), `findByDedupKey`, `firstTxnDate`, category/note updates |
| `CategoryDao` | ordered reads, `upsertAll` reseed |
| `BudgetDao` | upsert, active/inactive lists, per-category lookup |
| `SubscriptionDao` | inferred recurring charges, status marking |
| `StreakDao` | read-creates-initial, write, reset |
| `BadgeDao` | badges + challenge progress meters |
| `JarDao` | CRUD |
| `RoastDao` | insert, recent, `usedTemplateOnDay` (novelty guard) |
| `CaptureHealthDao` | insert, per-day stats, **`purgeRawTextOlderThan`** — the 24h privacy job (raw_text → NULL, hash + parsed fields survive) |
| `PendingReviewDao` | queue, count, resolve, housekeeping |
| `KvDao` | typed key/value with reserved-keys list |

### 1.5 Capture pipeline (`lib/data/repos/`)

`LedgerRepo.ingest(ParserInput)` — the phase's centrepiece:

```
OtpFilter ─▶ PromoFilter ─▶ parser chain (11) ─▶ confidence gate
     │drop codes          │no_parser_match        │< 0.6 drop
     ▼                    ▼                       ▼
capture_event row (health, always) ────────► every outcome
     │
     ├─ ≥ 0.8 (auto): findNear cross-source check BEFORE write
     │      ├─ near match (±10 min, amount+merchant) ⇒ duplicate
     │      └─ else upsertByDedupKey ⇒ autoAccepted
     └─ 0.6–0.8 (review): pending_review queue
```

**Two-layer dedup:** (1) `DedupEngine.fingerprint` =
`sha1(ref | amountPaise | counterparty | 10-min-bucket)` stored as
`dedup_key` (UNIQUE index); (2) `TxnDao.findNear` catches the same
payment reported by two sources with *different* refs (GPay notification
+ HDFC SMS). Plus `PendingReviewRepo` (approve → ledger txn, dismiss →
recorded), read-model repos (category/budget+status/subscription/streak/
roast/jar/capture-health/khel) and Riverpod providers for all of it.

### 1.6 Parsers (`lib/data/parsers/`, 18 files)

- **Filters first:** `OtpFilter` (`otp_security` — requires OTP language
  AND a 4–8 digit code), `PromoFilter` (`promo_marketing` — offers,
  prizes, marketing senders with shop/sale/offer bodies).
- **Registry order is policy:** 7 banks → 3 UPI apps → `GenericUpi`
  fallback. **Banks first** because sender tags are authoritative (an
  HDFC SMS mentioning "Paytm Fastag" stays an HDFC txn); generic UPI
  last so it only catches leftovers.
- 11 parsers: `gpay` (0.95), `phonepe` (0.95), `paytm` (0.90), 7 banks
  (0.85 full), any-parser partial (0.70), `generic_upi` (0.65). Bands:
  **≥0.8 auto · 0.6–0.8 review · <0.6 drop** (`CONFIDENCE.md` documents
  the policy).
- `AmountExtractor`: ₹/Rs./INR markers, Indian comma grouping
  (`1,2,34,567`), decimals, **Devanagari + Arabic-Indic digits**,
  `\b` guards (`years 500` ≠ amount), and balance-avoidance that only
  poisons the text *since the previous amount* (fixes
  `Avl Bal Rs.45,000. Rs.250 debited…` — see errata §6).
- `MerchantCleaner`: **79 curated Indian-consumer aliases** (Swiggy →
  Zepto → DMart → "Domino's" → Vi…), corporate-suffix noise stripping
  (Pvt/Ltd/India/Technologies/…), bracketed noise removal, VPA
  pass-through (`ramesh@okhdfcbank` stays an identifier), channel-phrase
  stripping (`via UPI`, `using PhonePe`, …), and title-casing that
  treats long ALL-CAPS runs as shouting (`RAMESH` → `Ramesh`) while
  preserving genuine mixed-case brands (`DMart`) and ≤3-letter acronyms.
- `DateHints`: `on 27-10-26` / `at 18:45` extraction; same-day hints keep
  the precise receive clock.

### 1.7 Corpus & golden test (`test/fixtures/`, `tools/gen_corpus.py`)

**250 samples** — 185 machine-generated template variants (7 banks × 5
template families × 4 merchants = 140 SMS; 3 UPI apps × 5 × 3 = 45
notifications) + **65 hand-authored adversarial cases** with independent
expectations (OTP-with-amount, promo spam, KYC noise, balance-only
texts, partials, Devanagari amounts, lakh-comma amounts, cross-app
routing traps, VPA counterparties, Paytm-Payments-Bank SMS…).

`tools/gen_corpus.py` contains a **1:1 Python model of the Dart chain**
(same regexes, same registry order, same cleaner) — it emits the JSON
expectations *and refuses to run if its output disagrees with any of the
65 hand expectations*. Class mix: 215 auto / 17 pending / 18 drop.

`parser_golden_test.dart` runs the real Dart chain over both files,
asserts **class + parserId + amountPaise + direction + merchantClean +
confidenceMin + occurredAtIsoDate + hasVpa/hasRef**, prints a per-field
accuracy table, and gates at **≥ 95% per field**.

### 1.8 CSV export (`lib/data/csv/csv_service.dart`)

Window-filtered export (paged reads), RFC-4180 escaping (quotes, commas,
newlines), decimal-rupees amounts for spreadsheet friendliness, IST
date/time columns, `parseCsv` reader for round-trip tests,
`Share.shareXFiles` hand-off for the share sheet.

## 2. File inventory (new)

```
lib/data/models/         11 files
lib/data/db/              4 files (schema, migrations, db_key_store, udao_database)
lib/data/db/dao/         12 files
lib/data/repos/           5 files (ledger, pending_review, query_repos, providers, capture_pipeline_result)
lib/data/parsers/        18 files (+ CONFIDENCE.md)
lib/data/csv/             1 file
test/data/               14 files (db ×4, parsers ×6 + golden, csv ×1, repos ×2)
test/fixtures/            2 corpus JSONs + README.md
tools/gen_corpus.py, tools/static_verify.py
```

Edited: `pubspec.yaml`, `lib/main.dart`, `AGENT_LOG.md`,
`tools/local_verify.ps1` (adds `flutter test test/data`).

## 3. Tests

**148 new `test()` statements across 14 files — 183 tests at runtime**
(merchant_cleaner_test registers 25 + 12 per-case tests inside for-loops;
on top of Phase-01's 128 — full suite = 311):

| File | Covers |
|---|---|
| `udao_database_test` | open+seed 16 categories, FK pragma, singleton, wipeAll+VACUUM reseed, embedding cascade, downgrade refusal, migration runner, DB independence |
| `txn_dao_test` | upsert/dedup-ignore, row round-trip, paging+filters, sums, category/day totals, findNear windows, updates/deletes, firstTxnDate |
| `dao_catalog_test` | all other DAOs (category/budget/subscription/streak/badge/jar/roast/kv/pending_review/capture_health incl. 24h purge) |
| `filters_test`, `amount_extractor_test`, `merchant_cleaner_test` (45 cases), `dedup_engine_test`, `upi_app_parsers_test`, `bank_parsers_test` | parser stack unit coverage |
| `golden/parser_golden_test` | 250-sample corpus, ≥95% per-field gate |
| `csv_service_test` | escaping, round-trip, window filter, comma-merchant survival |
| `ledger_repo_test` | full ingest pipeline: auto/duplicate/pending/drop, cross-source suppression, health rows, purge, warmUp |
| `pending_review_repo_test` | queue, approve→txn, dismiss, cleanup |

## 4. Design decisions worth remembering

1. **No `path` dependency** — DB paths build as `'$dir/udao.db'` from
   `getDatabasesPath()`; one less dep to sweep.
2. **`singleInstance: false`** in test options — `:memory:` +
   singleInstance would silently share one DB across tests.
3. **`EmbeddingRow` beyond the prompt list** — Phase 06 needs vector
   storage; landing the table + cascade test now avoids a v2 migration
   later. Same for `pending_review` (review-queue contract).
4. **capture_event purge = `raw_text = NULL`, row survives** — the
   health dashboard needs the counters; DPDP needs the text gone. 24h
   window, Phase 05 schedules the job.
5. **findNear runs BEFORE the write** (not after) — otherwise the
   cross-source duplicate inserts first and the check comes too late.
6. **Expectation-first adversarial cases** — the corpus generator
   cross-checks the model against hand expectations and hard-fails on
   disagreement; that loop caught 4 real parser bugs during development.

## 5. Static self-verification (sandbox has no Dart SDK)

`tools/static_verify.py` — **ALL PASS**:

- bracket/paren/brace balance on all 67 touched `.dart` files
  (comment/string/interpolation-aware scanner);
- all 71 regex literals compile (Python `re` ≈ Dart `RegExp` syntax
  check; adjacent raw-string concatenations joined);
- banned-pattern sweep (no `withOpacity`, no `TextStyle.apply`, no
  `CrossAxisAlignment.stretch`, no escaped-`\$` anchor bugs, no
  leftover placeholders);
- import-graph audit: every relative import resolves; no unknown
  packages; unused-import heuristic (2 found → removed);
- corpus model vs Dart regex drift check (joined-literal compare);
- phase-02 headers, 148 test statements confirmed (183 runtime).

Also verified against real Phase-01 sources (not memory): logger lives
at `core/log/` (not `core/logging/`), `IstDates` lives in
`core/utils/date_utils.dart`, `warn()` has no `error:` parameter (only
`error`/`fatal` do), `Money.fromRupees` is a non-const factory,
`const FlutterSecureStorage()` is valid on 9.x. Each of these was a
compile error waiting to happen — all fixed before commit.

## 6. Errata found & fixed during the build (pre-commit)

| # | Bug | Root cause | Fix |
|---|---|---|---|
| 1 | `android.Database` phantom type in `_daos()` | copy-paste slip | direct `Future<Database>` wiring |
| 2 | export directive mid-file in `parser_types.dart` | Dart requires directives before declarations | proper import |
| 3 | "Avl Bal" leaked into merchant names / poisoned next amount | tail regexes + fixed-width lookback | lookahead-terminated merchant capture; balance-context scoped to the segment since the previous amount |
| 4 | `\$` literal-dollar in 3 bank regexes | Python heredoc escaping | `\s*$` anchors restored |
| 5 | ALL-CAPS words never title-cased (`PRIYA SHARMA` stayed) | `camelish` check matched any trailing uppercase | requires mixed case; ≤3-letter all-caps kept (KFC-like) |
| 6 | alias loader missed `"Domino's"`-style double-quoted values | single-quote regex | both quote styles |
| 7 | gpay probe `via\s+upi` stole generic UPI texts | over-broad probe | app-name probes only; banks ordered before apps |
| 8 | `findNear` ran after insert (cross-source dup became autoAccepted) | ordering | near-check before write, insert-ignore still a duplicate |
| 9 | `const Budget(limit: Money.fromRupees(2000))` | factory isn't const | `final` |
| 10 | 7 files imported `core/logging/...` / `utils/ist_dates.dart` | trusted stale memory over sources | fixed to `core/log/...`, `utils/date_utils.dart` |

## 6a. Errata round 1 — first local `flutter analyze` (post-commit)

Dinesh's first local run (Windows 11 / Flutter 3.41.4) produced a 935-line analyzer
log: **300 issues — 35 errors, 8 warnings, 257 infos.** All fixed in the errata
commit; nothing was hand-waved away.

**A. Compile errors (35) — all in Phase-02 code:**

| # | Class | Count | Fix |
|---|---|---|---|
| 1 | `Database` passed where DAOs take `Future<Database>` (`await` before `_database.db` in DAO ctor calls) | 8 | drop the `await` — DAOs hold the future and resolve lazily |
| 2 | `.value` on `Result` after a *negative* `is Err` guard (no promotion without a positive check) | 7 | `valueOrNull!` after the guard, or drop `!` where a positive `is Ok` had already promoted |
| 3 | `TxnDirection.fromName` / `TxnSource.fromName` (extension members called via the on-type) | 4 | call via extension name: `TxnDirectionName.fromName` / `TxnSourceName.fromName` |
| 4 | `Category` ambiguous (flutter/foundation annotations vs models) in `udao_database.dart` | 2 | `import 'package:flutter/foundation.dart' show visibleForTesting;` |
| 5 | `_debitVerbFirst` / `_debitAmountFirst` undefined in phonepe/paytm | 4 | a Phase-02 patch replaced the *usages* but its declaration replace silently no-op'd (the old `_debit` stayed, unused) — declarations restored 1:1 from the `tools/gen_corpus.py` model (DV/DA). **Lesson burned in: every scripted patch now asserts its replacement count** (all three errata scripts here do). |
| 6 | `DatabaseFailure` undefined in `csv_service.dart` (+2 cascade) | 2 | missing `core/errors/failure.dart` import |
| 7 | `Badge.seen` required but not passed in `dao_catalog_test` | 2 | `this.seen = false` default on the model |
| 8 | `String.new` tear-off over runes (`amount_extractor`) | 1 | `String.fromCharCode` |
| 9 | `db.getVersion()` doesn't exist on sqflite `Database` | 1 | `rawQuery('PRAGMA user_version')` |
| 10 | `sender: null` into non-nullable helper param (`ledger_repo_test`) | 1 | helper param now `String?` |

**B. Warnings (8):** unused sqflite import in `dao_helpers.dart` (removed);
2 × `!` on already-promoted receivers in `ledger_repo` (dropped); 2 × `@override`
on non-interface members in `showcase_golden_test`'s custom comparator
(`getBaseline`/`getSize` are helpers, not overrides — annotations removed);
`package_prefixed_doc_comments` not recognized by this SDK's linter set (removed
from `analysis_options.yaml` — it was the one speculative entry from a newer
lints set than flutter_lints 4).

**C. Infos (257) — mostly analyzer drift vs the Phase-01-era toolchain, plus my own style misses:**

- `dangling_library_doc_comments` ×102 — the house `// phase-XX` header followed
  by a `///` block *before* imports is a dangling library doc. Sweep: **327 `///`
  lines converted to `//` across 113 files** (header blocks only; real API docs
  untouched).
- `always_put_required_named_parameters_first` ×47 — this analyzer build flags
  `super.key`-before-`required` too. All 14 widget ctors + 5 model/codec params
  reordered; house rule updated: **required named params first, `super.key` last.**
- `require_trailing_commas` ×54 — multiline arg/param lists across models,
  repos and tests restructured (canonical `dart format` shapes).
- `prefer_const_constructors` / `prefer_const_literals` ×46 — const added across
  Phase-01 showcase/tests + `const Err/Ok(...)` forms in the repos.
- `sort_pub_dependencies` ×2 — my Phase-02 pubspec edit inserted
  `sqflite_sqlcipher` *after* `sqlcipher_flutter_libs` (wrong: `sqfl < sqlc`) and
  `flutter_test` after `sqflite_common_ffi` in dev_deps. Both sections re-sorted.
- Singles: `use_key_in_widget_constructors` (notification_step got `super.key`),
  `prefer_final_locals` (date_hints), 2 × `avoid_print` (golden-test print
  tear-offs got their own `// ignore: avoid_print` lines), 1 static-comparison
  hint (`Ok == Err` rewritten over `Result<int>`-typed operands).

**D. Regression safety:** `tools/static_verify.py` re-run after the sweep —
67 files, 73 regex literals (the 2 restored amount-first debit patterns now
compile), 148 test statements / 183 runtime tests, ALL PASS. The restored
PhonePe/Paytm debit regexes match
`gen_corpus.py`'s DV/DA character-for-character, so the golden corpus
expectations (which were generated from that model) are unaffected — behavior
simply returns to what the corpus was built against.

## 6b. Errata round 2 — first local `flutter test`

Analyze came back with **one** leftover info (round-1 sweep miss), and the test
run was **303/311 passing — 8 failures**. The golden corpus itself passed
**100.0% on every field on real hardware** — the failures were mostly test-code
defects, plus two genuine production-code findings (a dropped `\b` in the
amount extractor, and `resolve()` taking an injectable clock).

| # | Failure | Root cause | Fix |
|---|---|---|---|
| 1 | analyze info: `udao_dialog_test.dart:35` trailing comma | missed in the round-1 sweep | call restructured |
| 2 | `AmountExtractor` matched `rs` inside "years 500" → 50000 | Dart transcription of `gen_corpus.py`'s `MARKED` dropped the `\b` on the `rs`/`inr` branches | `\b` restored — now character-identical to the model (verified: `years 500` → null; `Rs./INR/₹/Devanagari` all still match). Real production fix, not a test fix. |
| 3 | `PendingReviewDao` cleanup test: 0 deleted, expected 1 | `resolve()` stamps wall-clock *now* (Oct 28 on the run machine); the test's cutoff (Oct 5) was already in the past | `resolve()` gained an optional `at:` clock (deterministic test instants); test resolves at Oct 3, cutoff Oct 5 |
| 4 | `CaptureHealthDao` purge test: 1 purged, expected 0 | cutoff direction inverted in the test — a *future* cutoff purges everything, not nothing | first cutoff = `now − 24h` (events still inside the privacy window) |
| 5 | embedding FK-cascade test: `Invalid sql argument type 'List<int>'` | the test bypassed the model and passed a raw `List<int>` — sqflite accepts only num/String/Uint8List | insert via `EmbeddingRow.toRow()` (float64 BLOB — the production path) |
| 6 | dedup bucket test: +9m59s landed in a different bucket | `t = 18:45:03` sat 5:03 into a 10-minute bucket, so +9m59s crossed the edge; local time too | `t = DateTime.utc(…, 18, 40)` — exactly on a bucket edge, timezone-proof |
| 7 | CSV export test: got `10.04`, expected `10.00` | `page()` is newest-first (`occurred_at DESC, id DESC`); the test used five identical timestamps and assumed insertion order | distinct per-txn times; asserts newest-first (`t4` leads, `t0` closes) |
| 8 | ledger duplicate test: `deduped` flag false | `recent()` is newest-first **and** both events shared one timestamp (unstable tie order); test read `.last` | second ingest at +1 min; asserts `events.first.deduped` |
| 9 | `cleanupResolved(days: 0)` deleted 0 | resolve stamp and cutoff can tie to the same millisecond on a fast machine (`<` never fires) | `days: -1` — cutoff strictly in the future, deterministic |

**Test-count truth:** the runner executes **183** tests in `test/data`, not 148
— `merchant_cleaner_test` registers 25 + 12 per-case tests inside for-loops.
148 is the static statement count; full suite = 128 + 183 = **311**.
`tools/static_verify.py` now prints both numbers.

## 7. Local verification (for Dinesh)

> **✅ VERIFIED — 2026-10-28** (round-2 errata commit `da98926`):
> `flutter test` → **+311: All tests passed!** · `flutter test test/data` →
> **+183: All tests passed!** · golden corpus accuracy table → **100.0% on
> every field** (250/250 class, 232/232 each parsed field, 18/18 drops,
> 157/157 refs). Windows 11 / Flutter 3.41.4.

> **Round-2 errata is in.** The first test run (303/311) found 8 test defects +
> 2 production nits — §6b. Use the latest commit (`fix(phase-02): second
> local-run errata`) before re-running.

```powershell
cd udao
flutter pub get
flutter analyze            # expect: No issues found!
dart format lib test       # first tall-style run may rewrite — commit it
flutter test               # all: 128 (phase-01) + 183 (phase-02) = 311
flutter test test/data     # phase-02 detail incl. golden accuracy table
```

or just: `powershell -ExecutionPolicy Bypass -File tools\local_verify.ps1`

Notes for the run:

- The golden test prints the accuracy table — every field should read
  **100.0%** (expectations were generated by a model of the same regexes;
  any sub-100 field means Dart/Python regex divergence — send me the
  printed failures and I'll patch in an errata commit).
- `sqflite_common_ffi` bundles sqlite3.dll for tests — nothing to
  install. (Release-mode *desktop* builds would need the DLL next to the
  exe; irrelevant for Android.)
- On-device cipher proof: run `flutter run --flavor play`, check logcat
  for `SQLCipher active: 4.5.6` from `udao` scope on first open.

## 8. What Phase 03 can lean on

- `ledgerRepoProvider` → `ingest(ParserInput)` for the notification
  listener (Phase 03 just builds the events).
- `captureHealthRepoProvider` → purge + stats for the watchdog.
- `udaoDatabaseProvider` for anything direct.
- `ConfidencePolicy` bands are the contract for review-queue UX.
- `kSeedCategories` powers any category picker.
