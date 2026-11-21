# UDAO — hostile production audit

**Audited tree:** `/home/user/udao`, branch `main`, HEAD `042630d` ("first commit", squashed) — *not* `d0b364c` from the brief.
**Method:** read-only static audit, `python3 tools/static_verify.py` (passes), plus a numeric replay of every date/epoch expression in Python. No Flutter/Dart SDK exists in this sandbox, so **nothing was compiled or run on device**. Every runtime claim is tagged `needs-runtime-verify`.

---

## 0. Repo vs. brief — reconcile these before trusting the brief

| Brief says | Repo says | Evidence |
|---|---|---|
| HEAD `d0b364c` | HEAD `042630d`, one squashed commit | `git log --oneline` |
| Phase 09 "Awaaz" delivered: verdict notifications, spend roasts, WYSIWYG share cards, CSV export, "POST_NOTIFICATIONS fix" | **None of it exists.** No `lib/features/notify/`, no `lib/features/share/`, no `roast_notify.dart`, no `toImage`/`RepaintBoundary`→PNG anywhere, no evening-verdict sweep. `verdict_bell.dart` is a static mock used by onboarding/showcase. | `find lib -name '*notify*' '*share*'` → nothing; `grep -rn "toImage\|verdict\|roast" android/` → 0 Kotlin hits; `AGENT_LOG.md` stops at `08-errata-1` |
| `AGENT_LOG.md` records every phase | no phase-09 row at all | `tail AGENT_LOG.md` |
| 13 Kotlin files | **15** (incl. `PowerStateProbe.kt`, `UdaoSmsReceiver.kt`, `SmsGateTest.kt`) | `find android -name '*.kt' \| wc -l` |
| 410 l10n keys | **390** in each ARB; delegate exposes 358 getters + 33 methods = 391 | python key count over `assets/l10n/app_{en,hi}.arb` |
| README: "fully delivered through phase 09", `90 files, ~876 tests` | README:22, README:251 advertise phase 09; tree has **95** test files / **699** `test(`+`testWidgets(` statements | `README.md:22,228,251`; `grep -c` |
| README §10 layout lists `features/notify/`, `features/share/` | absent | `ls lib/features` → 9 dirs, neither present |
| "CSV export" shipped | `CsvService.share()` (`csv_service.dart:76`) has **zero call sites**; only `export_report` writes a file and hands the raw path to the model | `grep -rn "\.share(" lib` |

**Consequence for your self-risks:** risk **(b)** (`roast_notify.dart` dispose race, midnight kv rollover, `fireRoastNotification` error paths) **is not auditable — that code is not in the tree.** Risk **(d)** is mis-stated in the brief: there is no POST_NOTIFICATIONS request at `onCreate`; there is **no request anywhere** (F-08). Don't spend field time on "double ask".

---

## 1. Executive summary — severity × likelihood

1. **Every IST day-window in the app sits 5 h 30 m late, and manual entries are 5 h 30 m in the future.** `IstDates` hands out *shifted wall clocks* (`DateTime.utc(y,m,d)` whose epoch is 05:30 IST), but the DB stores real epochs. So "Aaj" is `[05:30 D → 05:29 D+1]` IST, budgets start at 05:30 on the 1st, and Khel judges the previous calendar day. Meanwhile `quick_add`/`receipt` stamp entries at **17:30 IST**, which is *later than `now`*, so `sumBetween(from, now)` — the budget and `predict_month_end` query — **excludes a manual spend made before 18:00**. Two screens disagree about today's spend. Verified numerically (§4.1).
2. **WAL replay acks what it failed to ingest.** `replayWal()` discards `pipeline.run()`'s `Result` and then calls `ackWAL(maxTs)` for the whole batch (`wal_replay.dart:44,50`). DB cannot open → every event fails → **all of it acked and deleted** (F-03). The one scenario the WAL exists for is the scenario that destroys it.
3. **The 0.60–0.79 review band is written to a table no screen, route, or l10n string can reach.** `pending_review` has a complete DAO + repo; `Routes` has no review path; `pendingCount()` is called only from tests. Real transactions park there forever (F-06).
4. **Below 0.60 the message is destroyed at write time** — `_recordDrop` omits `rawText` (`ledger_repo.dart:186-203`), and `capture_event.raw_text` is `NULL`-able (`schema.dart:121`) — so the 24 h purge is moot: the text was never stored. Only a `cap_drop_low_confidence` counter survives (F-02).
5. **`POST_NOTIFICATIONS` is declared and never requested** (`manifest:12`; `grep -rn POST_NOTIFICATIONS lib android/**/*.kt` → 0). On Android 13+ every `NotificationGateway.postHealth` escalation — the entire "we'll tell you when capture dies" story — is silently dropped (F-08).
6. **The hard guardrail false-negatives exactly what a Hinglish model emits.** Replaying the real regexes (`guardrail.dart:53-76`): `"chutiye, phir se swiggy?"`, `"gaandu saala"`, `"bhenchod"`, `"tum naalayak ho"`, `"Tum to barbaad ho bhai"`, `"Tumhari zindagi khatam ho gayi"` **all pass** (F-09). Each is one typographic step from a blocked form (`chutiya` is blocked, `chutiye` is not; `tu barbaad` is blocked, `tum to barbaad` is not).
7. **`ModelManager.touch()` has zero callers**, so the 5-minute timer armed at load is *"unload 5 min after load"* — a chat at minute 6 silently loses the model voice and falls back to templates with no UI signal (F-10).
8. **Two same-amount payments within ±10 min are fused into one.** `findNear` (`txn_dao.dart:86-108`) runs before every auto-accepted write with merchant equality and no ref-number escape hatch (`ledger_repo.dart:95-104`, F-05). Two ₹40 chais, two ₹500 splits: the second is "a duplicate".
9. **There is no delete path and no reachable export.** `txnDao.deleteById`, `wipeAll` and the vault's `delete()` have no feature caller, and `csv_service` has no caller at all (F-14). For a privacy-marketed app in India that is both a UX hole and a Play Data-safety problem — the form asks you to declare a deletion path you don't have.
10. **Release is not shippable as configured**: absent keystore ⇒ R8 release build is **debug-signed** (`build.gradle.kts:129-133`); CI never runs `tools/static_verify.py`, never builds `--release`, never builds `--flavor power` (`.github/workflows/ci.yml`); README/AGENT_LOG claim a phase that does not exist (F-13).

---

## 2. Scorecard

| Dimension | Score | One-sentence justification |
|---|---|---|
| **Data integrity** | **3 / 10** | Integer paise and a sound dedup fingerprint are undermined by a 5 h 30 m day-window error, a 17:30 future-dated manual stamp that hides spends from budgets, WAL ack-on-failure, and an unreachable review band — four independent ways for real money to be wrong or gone. |
| **Security / privacy** | **6 / 10** | SQLCipher + Keystore key, AES-256-GCM receipt vault with a fresh nonce per file, `allowBackup=false`, and zero INTERNET in release are all genuinely done — but raw SMS/notification text sits **unencrypted** in `noBackupFilesDir` for 7 days, `pending_review.raw_text` never expires, and the guardrail fails **open** on any internal error. |
| **Crash-safety** | **6 / 10** | `Result` everywhere, `guardDb` around every DB call, `runCatching` at every platform boundary, no `!` on external data in hot paths — but `_load()` re-reads providers after awaits with the `mounted` check *after* the last one (`aaj_screen.dart:73-99`), and `State.ref` after dispose throws in Riverpod 2. |
| **Background survival** | **5 / 10** | The watchdog ladder mirrors the Dart planner and is text-pinned by tests; but 10 s of `Thread.sleep` inside a Worker, `KEEP` never re-arms a dead chain, and the channel it escalates on has no runtime permission on A13+. |
| **AI robustness** | **5 / 10** | Template floor, schema-validated tool args, honest 5-round cap, SHA-256 re-verified per load — but guardrail false negatives, a dead idle timer, and write tools that accept any positive number. |
| **UI / a11y** | **5 / 10** | Strong component library and empty-state discipline, but 11 `Semantics` nodes in 188 files, `TxnRow` has none, hero text is clamped to 1.3, and `'SETTINGS'` / `'8:30 PM'` bypass the delegate. |
| **Release readiness** | **3 / 10** | Debug-key signing, a CI that gates none of your product laws, README claims for a phase that doesn't exist, `steps = {}` + throwing migrations, and no Play disclosure artifact for notification access. |
| **Test quality** | **6 / 10** | Corpus-driven parser goldens, native↔Dart contract tests, real DB via `sqflite_common_ffi`, disciplined fake-async — but the suite **encodes the day-boundary bug as expected behaviour** (fixtures built in the same shifted space), and nothing tests the review band, the WAL-failure path, or import duplicate override. |

---

## 3. Findings

Confidence: **C** = certain from code (arithmetic replayed), **L** = likely, **R** = needs-runtime-verify.

### P0

| ID | Sev | File:line | What | Why it matters (user impact) | Fix sketch | Conf |
|---|---|---|---|---|---|---|
| F-01 | P0 | `date_utils.dart:15,21-26,42-44`; `aaj_screen.dart:75-86`; `query_repos.dart:72-79`; `khel_service.dart:198-204`; `ledger_screen.dart:127-128`; `txn_dao.dart:252-270` | `IstDates` produces **shifted wall clocks** (`nowIst()` = `toUtc()+5:30`; `startOfDay` = `DateTime.utc(y,m,d)`), but every stored instant is a **real epoch** (`capture_raw_event.dart:40` ← `sbn.postTime`/`System.currentTimeMillis()`; `txn.dart:162` writes `millisecondsSinceEpoch`). All SQL bounds are therefore +5:30 from true IST midnight. Replayed: "Aaj" at 09:00 IST = `[04-Nov 05:30 → 05-Nov 05:29]`. | A 02:00 IST Swiggy order is **not in Aaj** — it is grouped under **"Kal"** (`startOfDay(occurredAt)` takes the UTC fields → date−1 for anything before 05:30). Khel's `_daySpend(D)` covers `[05:30 D → 05:29 D+1]`, so that 2 AM spend is charged to D−1 and **day D is scored a no-spend day → the streak advances on a day with a spend** (violates the no-fake-streak law) and D−1's already-journaled "clean" verdict cannot be revoked. Budget months start 05:30 on the 1st, so the last 5.5 h of every month land in the next period. | Two coherent options: **(a)** keep the shifted-wall-clock convention everywhere but convert at the DB boundary — `ms(istWall) => istWall.millisecondsSinceEpoch - istOffset.inMilliseconds` (the pattern `countByDaySource` already uses: `(occurred_at + 19800000)/86400000`, `txn_dao.dart:302`); or **(b)** store an `day_ist TEXT` column at write time and group on it. Land G1/G6 red first. | **C** |
| F-02 | P0 | `ledger_repo.dart:186-203`; `schema.dart:117-124` | `_recordDrop` inserts a `CaptureEvent` with no `rawText`, so the column is NULL at write time — the drop is unrecoverable by construction. The 24 h purge (`capture_health_dao.dart:38-56`) protects nothing here. | One parser mis-score (F-03 below makes that easy: `generic_upi_parser` is 0.65, `bank_parser_base` `full ? 0.85 : 0.7`, `confidence_policy` 0.6/0.8) and the bank SMS is gone — no review row, no text, only a counter. "Zero-loss capture" holds at the WAL and is thrown away one layer up. | Write `rawText: input.text` exactly as `_record` does (`:180`), and let the existing nightly `purgeRawTextOlderThan` be the only erasure point. Then a "problem captures" list becomes possible. | **C** |
| F-03 | P0 | `wal_replay.dart:44,50` | `await pipeline.run(event);` discards the `Result`; `maxTs` is the max over **all** events; `ackWAL(maxTs)` then deletes them. `DatabaseFailure`/`CaptureFailure` are indistinguishable from a drop. | DB open fails (lost Keystore key after a restore, corrupt file, disk full) → replay walks the WAL, every ingest errs, and the whole backlog is acked and deleted. Silent, unrecoverable loss of every bank message captured since the last successful boot. | Ack only on `Ok` and on *drop-coded* `Err`s (`otp_security`, `promo_marketing`, `low_confidence`, `no_parser_match`); on `DatabaseFailure`/`CaptureFailure` break the loop and ack nothing. Keep `maxTs` = max of *handled* events. | **C** |

### P1

| ID | Sev | File:line | What | Why it matters | Fix sketch | Conf |
|---|---|---|---|---|---|---|
| F-04 | P1 | `quick_add_sheet.dart:130-136`; `receipt_capture_sheet.dart:168-175`; `query_repos.dart:72-79` | `_occurredAt()` = `DateTime.utc(y,m,d,6,30).add(istOffset)` = **12:00 UTC = 17:30 IST**. Budget/agent windows end at `now` (`statusOf`: `sumBetween(from, at)`; `predict_month_end` likewise). | A manual spend saved at 08:00 IST is stamped 17:30 IST — **9.5 h in the future** — so it is excluded from the budget bar and from month-end prediction until 18:00. `Aaj` (a window query) *does* show it. The user sees "I entered ₹500 and the rekha didn't move". Statement-import rows have the same shape at 12:00 IST (`statement_parser.dart:275-278`), so morning imports are invisible to budgets until noon. | Store the real instant (`DateTime.now().toUtc()`) for quick-add/receipt, and for date-granular sources clamp to *at most now*: `stamp.isAfter(now) ? now : stamp`. Then make all windows half-open `[start, nextStart)`. | **C** |
| F-05 | P1 | `txn_dao.dart:86-108`; `ledger_repo.dart:95-104` | `findNear` runs **before every auto-accepted write**: same `amount`, `merchant_clean` equality, ±10 min, and any hit ⇒ "duplicate", with **no ref-number escape hatch** (even when both sides carry different `ref_no`s). | Two ₹40 chais four minutes apart at the same shop → one recorded. Two ₹500 splits to the same cleaned merchant name → one recorded. A ₹99 recharge bought twice in ten minutes → one recorded. Aaj understates the day and the budget silently gains headroom, with no warning. | If both sides have a `ref_no` and the refs **differ**, they are different payments — skip `findNear`. Only fall back to the fuzzy window when at least one side lacks a ref. G4 pins both halves. | **C** |
| F-06 | P1 | `schema.dart:126-145`; `pending_review_repo.dart:25-117`; `routes.dart:3-19`; `pending_review_dao.dart:53` | The review band is write-only: complete DAO + repo (`pending/approve/dismiss/pendingCount/cleanupResolved`), **no route, no screen, no l10n key**, and `pendingCount()` is called only from tests. `cleanupResolved` likewise has no production caller. | Every 0.60–0.79 parse — `GenericUpiParser`'s entire output (0.65), every bank SMS whose merchant regex misses (`0.7`) — disappears from the user's ledger with no signal and no path to fix it. `CONFIDENCE.md`'s "a human fills the blank" is unimplemented. | `Routes.review` + a `ReviewScreen` (list `pending()`, show `raw_text`, edit amount/merchant/direction, `approve`/`dismiss`), a pending-count badge on Ledger, and `cleanupResolved` in the nightly job. | **C** |
| F-07 | P1 | `pending_review_repo.dart:57-110` vs `ledger_repo.dart:95-104` | `approve()` writes via `upsertByDedupKey` and **never runs `findNear`**, and it falls back to `dedupKey: 'review-${entry.id}'` (`:97-99`) — a key that can never match a real payment's fingerprint. | Approving the review entry for a payment the bank SMS already captured inserts a **second transaction**. The exact flow the queue exists for (GPay 0.70 + HDFC 0.85) is the one that double-counts. | Run the same near-gate inside `approve()`; resolve as `'approved-duplicate'` linking to the existing txn. | **C** |
| F-08 | P1 | `manifest:12`; `permission_port.dart:14-17`; `notification_step.dart:41-45,57-58` | `POST_NOTIFICATIONS` declared; `CapturePermission` has exactly one value (`sms`); onboarding's notification screen is a mock that records intent and carries `TODO-VERIFY`; zero Kotlin references to the permission. | Android 13+: watchdog escalation, gap alerts and the keep-alive notice are all suppressed with no dialog and no error. Capture can be dead for weeks and the app's whole health story says nothing. | Add `CapturePermission.notifications` to the port, ask once from the capture-gate screen on `SDK_INT >= 33`, and — on permanent denial — show a persistent in-app banner on Aaj (never rely on a notification you can't post). | **C** |
| F-09 | P1 | `guardrail.dart:53-76,114-123,128-149` | (a) Regex false negatives, replayed: `chutiye`, `gaandu`, `bhenchod`, `naalayak`, `"Tum to barbaad ho"`, `"Tumhari zindagi khatam ho gayi"`, `"Aapki halat khatam hai"` all **pass** — `slurs` matches `chutiya` but not `chutiye`/`gandu`-with-double-a; `alarmist` requires `tu|tum|aap|tera|tumhara` **immediately** before the adjective, so any interposed word ("to", "hari") escapes; `naalayak` is only in `panic` but the `\b`-anchored set has `nalaayak|nalayak` (double-a and single, but not `naalayak`). (b) `filter()`'s catch (`:117-123`) returns the input **unfiltered** — a fail-open on a safety control. | The product's hardest promise ("roast never harms, on every generated line") fails on the most probable model outputs, which are Hinglish colloquialisms with vowels shifted. (b) means one exception silently disables the law. | Stem-based patterns (`chutiy|gandu|gaand|madar|bhosd|harami|kutta` + Devanagari), allow up to 2 tokens between pronoun and adjective (`(tu\|tum\|aap\|…)\s+(?:\w+\s+){0,2}(barbaad\|khatam\|…)`), add `naalayak`, and fail **closed** to `safeTemplates`. G8 pins each string. | **C** |
| F-10 | P1 | `model_manager.dart:45,358-372` | `_armIdleTimer()` is called from `load()` (`:335`) and from `touch()` (`:360`) — and `touch()` has **no callers** anywhere (`grep -rn "\.touch()" lib test` → 0). `GemmaRuntime._run` never notifies the manager. | With the default `idleTimeout: 5 min`, the model is unloaded 5 minutes after loading **regardless of use**. Chat/roast silently degrade to the template floor with no UI signal; reads as "the AI is dumb", not "the AI left". | Call `touch()` at `GemmaRuntime._run` entry and in `AgentLoop.send`; or expose `onInference()` and wire it in `llmRuntimeProvider`. G7 pins it. | **C** |
| F-11 | P1 | `csv_service.dart:39-74,76-83`; `agent_tools.dart:585-624` | `exportCsv` writes the whole ledger — merchant, `ref_no`, `vpa`, `note` — to `Directory.systemTemp` (`:63`) and **never deletes it**; `share()` has no caller; `export_report` returns the raw path into the model transcript (`:617-621`) where the user can't act on it. | "CSV export" is unreachable, while every file ever produced sits in cache indefinitely — a full plaintext transaction history at rest outside the encrypted DB, contradicting "data leaves only by explicit user action". | Wire `share()` to Settings/Ledger, `File.delete()` in a `whenComplete` after the sheet returns, and return a boolean from `export_report` — never a path — into the model context. | **C** |
| F-12 | P1 | `statement_import_service.dart:150-153,299`; `import_review_screen.dart:392-424` | `confirm()` hard-filters `!r.isDuplicate`; the preview renders `DupReason` as **text only** — no checkbox, no override. The fuzzy window is **12 h** (`:299`). | A mis-detected duplicate silently drops a real row and tells the user "N duplicates skipped". Two genuine same-amount rows 12 h apart to the same merchant (morning + evening chai, two ₹500 splits in a day) lose one, with no recourse. | Give `ImportPreviewRow` an `include` flag (default `!isDuplicate`), render a checkbox on `DupReason.fuzzy`, include checked rows in `confirm()`. | **C** |
| F-13 | P1 | `build.gradle.kts:121-134`; `.github/workflows/ci.yml` | `signingConfig = if (releaseSigningInput != null) release else debug`. CI = pub get, analyze, format, test, icon-grep, `bootstrap.sh`, **debug** play build — no `static_verify.py`, no `--release`, no `--flavor power`. | The artifact for a closed track is debug-key-signed (Play rejects it; sideload users hit `INSTALL_FAILED_UPDATE_INCOMPATIBLE`). And the gates that encode your laws — no-network, `Share.share` pin, sealed-Failure, watchdog constants — are not in CI, so any PR can violate them and go green. R8/SQLCipher (a bug your own `proguard-rules.pro:53-61` remembers as a live field incident) is never built in CI. | Fail the build when `releaseSigningInput == null`; add `python3 tools/static_verify.py`, `flutter build apk --release --flavor play` and `--flavor power` to CI. | **C** |
| F-14 | P1 | `txn_dao.dart:353-358`; `udao_database.dart:147-162`; `receipt_vault.dart:73,138-150` | `deleteById`, `wipeAll` and `vault.delete` all exist; **none has a feature caller** (`grep -rn "wipeAll\|deleteById" lib/features` → 0). `settings_screen.dart` has no data row at all. | No way to delete a wrong transaction; no way to delete your data. Play's Data-safety form requires a deletion path; DPDP expects one; and `wipeAll`'s own doc-comment claims to be the DPDP path while being unreachable. Receipts therefore also orphan forever. | Settings → "Mera data mitao" (confirm → `wipeAll` + vault dir + chat kv) and long-press-delete on `TxnRow` (calls `deleteById`, then `vault.delete`). | **C** |

### P2

| ID | Sev | File:line | What | Why it matters | Fix sketch | Conf |
|---|---|---|---|---|---|---|
| F-15 | P2 | `WalWriter.kt:26-36,44-66,128-159`; `pending_review` (no purge) | WAL is plaintext JSONL in `noBackupFilesDir`, retained 7 days (`SEVEN_DAYS_MS`); `pending_review.raw_text` has **no expiry at all** (`grep purge pending_review` → 0; only `cleanupResolved` exists and it is uncalled). | The stated privacy law ("rawText only inside a 24 h window", `capture_event.dart:4-8`) is true for one table and false for the other two stores. 7 days of bank SMS in clear on disk defeats the SQLCipher/Vault work. | Encrypt WAL segments (key from `DbKeyStore` at boot) **or** drop retention to 24 h; add `purgeRawTextOlderThan` for `pending_review` to the nightly job. | **C** |
| F-16 | P2 | `HealthPinger.kt:48-70,186-196` | `Thread.sleep(REBIND_LATCH_MS)` twice (5 s each) inside `doWork()`; `ExistingPeriodicWorkPolicy.KEEP` never replaces a chain that ends `FAILED`/`CANCELLED`. | 10 s of a Worker blocked per down-check, and — worse — a wedged periodic chain has no self-heal: boot and app-open re-arms can only `ADD if missing`, which `KEEP` reports as present. | Return a retryable/`success()` immediately and let the *next* run check, or use `CoroutineWorker`+`delay`. For re-arm: read `getWorkInfosForUniqueWork` and `REPLACE` when `CANCELLED`/`FAILED`. | **C** |
| F-17 | P2 | `capture_pipeline.dart:121-125` | `_bump()` is `kv.get` → `kv.set` (read-modify-write). Two concurrent ingests (live EventChannel + the 15 s `walDrainDaemon`) lose one increment. | The only telemetry the app has (`cap_txn`, `cap_dup`, `cap_drop_*`) drifts — and it is the evidence a user's capture is failing. | One statement: `INSERT INTO kv(key,value) VALUES(?, '1') ON CONFLICT(key) DO UPDATE SET value = CAST(value AS INTEGER)+1`. | **C** |
| F-18 | P2 | `aaj_screen.dart:73-118` | `_load()` interleaves `ref.read` with `await`: 2 DAO pages, then `budgetRepoProvider.all()` (`:90`) and `statusOf()` (`:94`) **before** the `mounted` check at `:99`. `_openQuickAdd` (`:117-120`) reads a provider after an await with no guard. | Pull-to-refresh then switching tabs during a slow first open → `StateError: Cannot use ref after dispose` in Riverpod 2. Low frequency, high embarrassment (home screen). | Capture DAOs/repos into locals before the first await; `if (!mounted) return;` after **each** await that precedes another `ref`/`setState`. | **C** |
| F-19 | P2 | `aaj_screen.dart:75-86,133-138`; `ledger_screen.dart:56`; `txn_dao.dart:222-249` | Hero totals are folded in Dart over **page-limited** lists (`limit: 100` ×2; ledger `limit: 200`), and the ledger has no paging or "showing N of M". | A day with >100 rows understates "spent today" and the vs-yesterday delta; after ~3 weeks the ledger silently stops showing older rows with no indication — users read that as data loss. | Use `sumBetween`/`sumByCategory` (already exist) for hero math; paginate the ledger on `offset` (already supported) + a count line. | **C** |
| F-20 | P2 | `capture_health_dao.dart:60-77`; `txn_dao.dart:252-270` | `statsByDay` buckets `received_at / 86400000` (UTC days); `totalsByDay` does the same (`occurred_at / 86400000`) — while `countByDaySource` correctly shifts `+19800000` (`:302`). `totalsByDay` has **no callers**. | The health dashboard's day bars sit 5.5 h off the ledger's own days, and the "correct" and "incorrect" idioms coexist three methods apart — the next feature will copy the wrong one. | One IST-bucketing SQL fragment shared by all three; delete `totalsByDay` or fix and use it. | **C** |
| F-21 | P2 | `README.md:22,214,228,251`; `AGENT_LOG.md` | README says "fully delivered through phase 09" and lists "Verdict notifications, spend roasts, WYSIWYG share cards, CSV export, POST_NOTIFICATIONS fix"; the tree has none of the five, and AGENT_LOG has no 09 row. Test count claims (~876, `90 files`) vs 699 statements in 95 files. | The single most misleading artifact in the repo, and the first thing a Play reviewer, investor, or new contributor reads. | Implement phase 09 or strike the row, §10 entries, §6.4 and the claim sentence; add an AGENT_LOG row "09 NOT BUILT"; fix the test count. | **C** |
| F-22 | P2 | `db_key_store.dart:15-29`; `udao_database.dart:166-179` | The SQLCipher key is created once, never rotated, never recoverable; backup is off by design, so nothing exists outside the device. | A wiped Keystore / failed OS-upgrade migration orphans the database permanently; the next open fails and the user sees an empty app with no honest explanation and no path forward. | Detect "key present but open fails" and show an explicit screen ("ledger khul nahi raha — naya shuru karein?"), archive the orphan rather than crash-looping; ideally a user-invoked encrypted export first. | **L** (mechanism is certain; which OEM/OS events trigger it is **R**) |
| F-23 | P2 | `agent_tools.dart:386-392,434-450,229-246` | `add_transaction` accepts any `amount > 0` and writes `confidence: 1.0, source: manual` with `dedupKey: 'agent:<newId>'` (a key that can never dedupe); `set_budget` accepts any `limit > 0`. | A hallucinating or injected model writes a ₹1 crore row indistinguishable from a user's own entry, and can never be caught by dedup. | Cap `amount <= 10_00_000` and `limit <= 1_00_00_000`, reject non-integral rupees, and require an explicit confirm chip for `add_transaction` (the tool trace UI already renders one). | **C** |
| F-24 | P2 | `agent_loop.dart:294-303`; `agent_tools.dart:301,617-621` | Every tool result — including `merchantClean` from SMS-derived rows and a filesystem path — is appended as `TOOL_RESULT <json>` into the model transcript, truncated only by length (`_compact`, 800 chars). | A crafted bank-SMS merchant string is a prompt-injection channel into the tool loop; impact is bounded today (writes need taps, no network) but it is the unvalidated path your risk (f) describes. | Sanitise merchant strings to `[A-Za-z0-9 .&'-]{1,40}` before they enter any prompt/tool result; never put a path in the transcript. | **C** |
| F-25 | P2 | `agent_loop.dart:190,232`; `chat_controller.dart:199-215` | `AgentTokenEvent` fires **once**, at the end, by design (buffering avoids leaking tool JSON) — so the "streaming" bubble shows `…` for the entire generation. | Multi-round tool use on a 6 GB device = a `…` bubble for ~30 s. Users conclude the app hung. | Surface real progress you already have (`AgentToolEvent` names) — "budget dekh raha hoon…" — instead of implying token streaming. | **C** |
| F-26 | P2 | `guardrail.dart:87,154-161`; `chat_controller.dart:240` | The 280-char cap is applied to **chat answers** too, trimmed at a sentence boundary with ellipsis. | "Mera mahina samjhao" gets cut at 280 chars with no error and no continuation affordance — a broken feature that looks like a model limit. | Split `roastMaxChars` (280) from chat (unbounded or ~1200 with a "continue" tap); `GuardrailContext.isRoast` already distinguishes the paths. | **C** |
| F-27 | P2 | `query_repos.dart:67-79` (`BudgetRepo.statusOf`); caller `aaj_screen.dart:94` | `statusOf(now:)` uses `sumBetween(from, at)` with `at = now` — an **open** upper bound against future-dated stamps. | Compounds F-04: any entry stamped later than now (manual/receipt 17:30, import 12:00) is excluded from the rekha until the clock catches up. | Switch to half-open `[start, nextStart)` and clamp stored stamps to `min(stamp, now)`. | **C** |
| F-28 | P2 | `migrations.dart:18,24-45`; `schema.dart:10` | `steps = {}` and `run()` **throws** on a missing step; `dbVersion = 1`. | The first schema bump without a step bricks every existing install at open (`DatabaseFailure` inside `_openProduction`) — an empty app the user cannot fix. | Add the step before any bump, add the v1→v2-on-a-real-file test (G9), and during *open* log + route to a recovery screen instead of throwing. | **C** |
| F-29 | P2 | `guardrail.dart:114-123` | `filter()` catches everything and returns the input unfiltered, documented as "availability beats a dead chat". | A safety control that disables itself on the first exception isn't a hard guardrail; the safe templates are right there. | Fail **closed** to `safeTemplates` (which is what every other failure mode already does). | **C** |

### P3

| ID | Sev | File:line | What / why | Conf |
|---|---|---|---|---|
| F-30 | P3 | `txn_dao.dart:86-108`; `schema.dart:166-168` | `findNear` filters `amount = ?` over a time range with only `idx_txn_occurred_at`; called before **every** auto-accepted write and every 15 s drain pass. Add `INDEX txn(amount, occurred_at)`. | **C** |
| F-31 | P3 | `schema.dart:117-124`; `capture_health_dao.dart` | `capture_event` grows forever — one row per notification indefinitely (only `raw_text` is nulled). ~55 k rows/yr of counters, never pruned. Add a 90-day delete to the nightly job. | **C** |
| F-32 | P3 | `udao_logger.dart:119-140` | `attachFileSink` has **no callers** (grep: definition only) — the file sink, rotation and `close()` are dead code, so the "diagnostics bundle" has no logs to bundle. Wire it with `{amount, merchant}` redaction, or delete it. | **C** |
| F-33 | P3 | `quick_add_sheet.dart`/`receipt_capture_sheet.dart` `dedupKey: 'quick:$txnId'`/`'rcpt:$txnId'` | Unique-by-construction keys and **no `findNear`** for manual/voice entries: a double-tap on Save writes two rows; a re-scanned receipt writes two rows. Debounce the save or run the near-gate. | **C** |
| F-34 | P3 | `receipt_capture_sheet.dart:139-160,190-216` | The duplicate check only sets `_dupWarned` and `_save` never consults it — correct (warn, don't block) but it fires on F-05's false positives too, teaching users to ignore it. Pair with F-12's override UI. | **C** |
| F-35 | P3 | `AiBridge.kt:245-250` | `generatingSessionId` check-then-set is not atomic. Latent only: the executor is single-threaded today. Note, don't fix now. | **L** |
| F-36 | P3 | `txn_dao.dart:193-220`; `khel_service.dart:198-204`; `aaj_screen.dart:76-86` | Every range is inclusive `<=` with `endOfDay` (ms-exact) **and** `to = now`/`endOfMonth` — overlapping conventions. Standardise on `[start, nextStart)` and pin it with one adjacent-boundary test. | **C** |
| F-37 | P3 | `health_dashboard_screen.dart:269` | The diagnostics export hardcodes `'play-flavor policies: no battery permission'` in the **power** build too — the artifact you ask users to send lies about the build. Pass the real flavor. | **C** |
| F-38 | P3 | `HealthPinger.kt:162-165`; `docs/oem-survival.md` | `OEM_SUSPECTS` = xiaomi/redmi/poco/oppo/realme/vivo/iqoo/huawei/honor/oneplus/samsung — no Transsion (Infinix/Tecno/itel), Motorola, Lava, Micromax, Nothing. Those phones are common in India and among the most aggressive. Extend the set; render "pata nahi" for unknown rather than "stock". | **C** |
| F-39 | P3 | `settings_screen.dart:52`; `notification_step.dart:45` | Hardcoded `'SETTINGS'` and `'8:30 PM'` in a 390-key l10n app; the demo time should come from a key or the locale clock. | **C** |
| F-40 | P3 | `txn_row.dart:69-73` | `occurredAt.hour/.minute` → 24 h, no AM/PM, no locale, and (per F-04) shows **17:30** for a manual entry made at 08:00. Add a locale formatter, and for date-granular rows render the date only. | **C** |
| F-41 | P3 | `receipt_vault.dart:73,138-150` | `AesGcmCodec` use is sound (fresh IV per file, tag appended, tamper-evident `read`), but `delete()` is never called and the ciphertext name is not authenticated. Wire `delete` into the (missing) delete path. | **C** |
| F-42 | P3 | `ledger_repo.dart:104,126-135` | The comment at `:126-129` calls the unique-index ignore "an identical fingerprint replay … that findNear somehow missed" — it is equally a silently-lost **real** second payment in the same 10-min bucket. Reword so nobody trusts it. | **C** |
| F-43 | P3 | `date_hints.dart:30-52` | When an SMS carries a date but no time, the hint defaults to **12:00 device-local**; cross-day SMS therefore get a 12 h-uncertain stamp, which the 10-min `findNear` window can never match. Document it in `CONFIDENCE.md` and widen the cross-source gate for hint-only dates. | **C** |

### P4 nits

| ID | File:line | Note |
|---|---|---|
| F-44 | `CONFIDENCE.md` ("App notifications outrank bank SMS — whichever arrives first") | Contradicts the code: the chain is first-**parser**-match and the ledger keeps first-**arrival** (`ConflictAlgorithm.ignore`). "Whichever arrives first" is right; "outranks" is not implemented and cannot be, since the loser is dropped. |
| F-45 | `amount_extractor.dart:76-79` | Cap ₹1e10 whole rupees, then `min(paise, 1<<53)` — unreachable guard. Harmless. |
| F-46 | `settings_screen.dart:52` | `SectionHeader(number: '01', label: 'SETTINGS')` — cosmetic clash with Aaj `01` / Ledger `02`. |
| F-47 | `pubspec.yaml:4` | `version: 0.1.0+1` must become monotonic the moment anything ships. |
| F-48 | `tools/static_verify.py:243-256` (ban list) | Bans `withOpacity`, `CrossAxisAlignment.stretch`, `TextStyle.apply`, spinners — but not the landmines found here. Add four line-greps: `IstDates` in a raw-SQL comparison, `DateTime.now()` in a domain query, `Thread.sleep` in a Worker, `dedupKey:` built without `refNo`. |
| F-49 | `lib/core/result/result.dart:13-15` | The doc example logs `parsed $v` — fine, but `UdaoLogger` has no redaction hook at all (F-32 covers the sink), so any future `_log.info('... $amount ...')` ships amounts to disk. |
| F-50 | `ledger_screen.dart:238`; `aaj_screen.dart:354`; `txn_row.dart:15-18` | Both screens render `TxnRow(txn: …)` with **no `onTap`** — the widget supports it (`txn_row.dart:15-18,81`) and nothing passes one, so no ledger row is tappable. Sheet-based paths are dead-ended instead: the SMS tile routes to `Routes.smsGate` in the play flavor too (where `RECEIVE_SMS` is absent, so the request can only be denied), and `settings_screen.dart:52` hardcodes `'SETTINGS'` while section 02 uses `l10n.settingsToolsSection.toUpperCase()`. | You cannot correct a mis-parsed merchant, change a category, fix an amount, or delete a row — every mistake is permanent. In the play flavor the SMS tile is a dead end that reads as a broken permission flow. | `TxnRow(onTap: …)` → detail sheet (merchant, category chip, amount, delete) on both screens + long-press delete with an undo snackbar; gate the SMS tile on `appFlavorProvider == power`; `l10n.settingsSectionTitle`. This is the UI half of F-13. | **C** |
---

## 4. What I verified and how (plus the one self-correction)

### 4.1 The date arithmetic, replayed

| Expression | Replay result |
|---|---|
| `IstDates.nowIst()` at 09:00 IST 4-Nov | epoch reads **13:30 IST** (a shifted wall clock) |
| `startOfDay(now)` in a SQL bound | **04-Nov 05:30 IST** |
| `endOfDay(now)` | **05-Nov 05:29:59.999 IST** |
| txn at **01:30 IST 4-Nov** inside "Aaj"? | **No** — and `startOfDay(occurredAt)` takes UTC fields → grouped under **"Kal"** |
| txn at 07:00 IST 4-Nov | inside the window, grouped today |
| `quick_add._occurredAt()` | `DateTime.utc(y,m,d,6,30)+5:30` = **12:00 UTC = 17:30 IST** |
| Budget window at 08:00 IST | `from` = 01-Nov 05:30 IST, `to` = 13:30 IST → a 17:30-stamped manual entry is **outside** (`sumBetween` excludes it) |
| Statement import stamp | **12:00 IST** → excluded from budgets before ~noon |
| `countByDaySource` (`occurred_at + 19800000`) | **correct** — the right idiom already exists in-tree, three methods from the wrong one |

**Self-correction recorded:** I initially wrote that `TxnRow` prints manual entries as `12:00`. That is wrong — `TxnRow` prints `occurredAt.hour`, i.e. **device-local**, so it shows `17:30`. The display is honest about a stamp that is wrong; the real damage is F-04 (budgets) and F-40 (no locale/AM-PM). This is why every number above was re-derived rather than trusted.

### 4.2 Guardrail replay (real regexes, not approximations)

```
PASSES   'chutiye, phir se swiggy?'          []      <- should block
PASSES   'gaandu saala'                      []
PASSES   'bhenchod'                          []
PASSES   'tum naalayak ho'                   []
PASSES   'Tum to barbaad ho bhai'            []
PASSES   'Tumhari zindagi khatam ho gayi'    []
PASSES   'Aapki halat khatam hai'            []
BLOCKED  'chutiya' / 'madarchod' / 'bhosdike' / 'harami'      ['slur']
BLOCKED  'tu barbaad hai' / 'tum khatam ho'                   ['alarm']
```

---

## 5. False-positive register — looks wrong, verified fine (and how)

| # | Looked like a bug | Verdict | How I verified |
|---|---|---|---|
| 1 | Kotlin `package `in`.udao.app` — `in` is a keyword | **Intentional** | All 15 `.kt` files; `MainActivity.kt:1-6` states the JVM package; backticks everywhere. |
| 2 | Play build ships `INTERNET` | **False** | `src/play/` is an empty comment-only overlay; INTERNET appears **only** in `src/debug/AndroidManifest.xml:11`; `bootstrap.sh:46-62` asserts it. |
| 3 | Play build can read SMS | **False** | `RECEIVE_SMS`/`READ_SMS` + `UdaoSmsReceiver` exist only under `src/power/`; `static_verify.py` pins it. |
| 4 | Empty backup rules = ADB exfil | **False** | `allowBackup=false` (`manifest:22-25`) plus empty `backup_rules.xml`/`data_extraction_rules.xml`; moot by design. |
| 5 | R8 will strip SQLCipher | **Handled** | `proguard-rules.pro:53-61` keeps `net.sqlcipher.**` with the incident documented; `:33` MediaPipe; `:13` app classes. Still needs the F-13 release smoke. |
| 6 | "Banks first" chain misroutes a bank SMS that mentions Paytm | **Correct by design** | `parser_registry.dart:19-24` states the policy; sender tags are authoritative (`bank_parser_base.dart`). |
| 7 | `SmsGate` rejects real senders (`JD-BOBSMS-S`) | **Fixed in-tree** | `SmsGate.kt:34-35` allows an optional third `-TOKEN`; `SmsGateTest.kt` covers it; AGENT_LOG records the live field case. |
| 8 | `OtpFilter` drops anything containing "OTP" | **False** | Needs OTP language **and** a 4–8 digit code (`filters.dart:22-30`). |
| 9 | `AmountExtractor` returns the balance, not the amount | **False** | `_balanceContext` only inspects text since the previous amount; "first non-balance currency amount wins". Covered by `amount_extractor_test.dart`. |
| 10 | `MerchantCleaner` mangles `IRCTC` → `Irctc` | **False** | Alias table + ≤3-letter-caps and camelCase preservation; VPAs pass through. |
| 11 | `wipeAll()` violates FKs | **False** | Children-first `wipeOrder`, reseed in the same batch, `VACUUM` after. |
| 12 | `insertAllAtomic` can half-write a statement | **False** | One `db.transaction` + `Batch.commit`, ignores counted. |
| 13 | `Share.shareXFiles` is the removed 11.x API | **False** | `share_plus: ^10.0.2`; correct for 10.x; `static_verify.py:880-886` bans `SharePlus.instance`/`ShareParams`. |
| 14 | `pdfrx 2.4.7` is stale | **Intentional** | `pubspec.yaml:28-31` + one adapter seam. |
| 15 | Widget tests never `pumpAndSettle` | **Intentional** | repeat() skeletons + bounded `_settle` helpers; a deliberate fake-async law. |
| 16 | `createTestDb()` opens without an isolate | **Intentional/load-bearing** | `sqflite_common_ffi` + pre-awaited open, required by fake-async. |
| 17 | `ProviderContainer` before `runApp` | **Intentional** | `main.dart:25-36` — WAL replay must precede the first frame. |
| 18 | Roast `overspendPercent` clamp 300; zero-spend day → "streak-win" | **Intentional** | `query_repos.dart` + `roast_engine.dart:171-183`. |
| 19 | Guardrail not applied to roast rewrites | **False** | `roast_engine.dart:126-128` **and** `:320-322` both filter with `isRoast: true`. |
| 20 | `AiBridge` touches channel sinks from a MediaPipe worker thread | **False** | `AiBridge.kt:341-345` posts every sink write to `main`. |
| 21 | `ToolSchema.validate` doesn't validate | **False** | `agent_tool.dart:35-71`: unknown keys tolerated, required/type/enum enforced; `agent_loop.dart:277-281` wraps `invoke` in try/catch. |
| 22 | `SurvivalBridge.openOemScreen` can throw on a bad component | **False** | `ComponentName.unflattenFromString` + `runCatching`. |
| 23 | Model SHA is checked only at import | **False** | Re-verified on every load (`model_manager.dart:283-284`). |
| 24 | WAL grows unbounded | **False** | 2 MB × 3 segments + 7-day sweep on every ack and every ping. The real defect is F-03. |
| 25 | `onConfigure` uses `rawQuery` for pragmas | **Fine** | Same hook runs in the FFI test path; suite green. One on-device `PRAGMA foreign_keys` check remains (**R**). |

---

## 6. Test-gap analysis — 10 highest-value missing tests

Money math and boundaries first. All are `arrange / act / assert` at the level you'd actually write.

**G1 — the day boundary in real epochs** · `test/data/db/txn_dao_ist_window_test.dart`
*Arrange:* `createTestDb()`; insert txns at **`DateTime.utc(2026,11,3,20,30)`** (= 02:00 IST 4-Nov) and **`DateTime.utc(2026,11,4,1,30)`** (= 07:00 IST 4-Nov).
*Act:* `page(from: IstDates.startOfDay(ist(2026,11,4)), to: IstDates.endOfDay(...))` where `ist(...)` is `DateTime.utc(2026,11,4,9)`.
*Assert:* **both** rows returned; and the previous day's window returns neither. **Fails today** (F-01) — this is the proof, write it red first.

**G2 — replay must not ack a failed ingest** · `test/features/capture/wal_replay_failure_test.dart`
*Arrange:* 3 events; fake pipeline returns `Ok` for #1, `Err(DatabaseFailure('boom'))` for #2, `Ok` for #3; fake bridge records every `ackWAL(ts)`.
*Act:* `await replayWal(...)`.
*Assert:* `ackWAL` was **not** called (or called with `ts < event2.ts`), and the call returns `Err`. **Fails today** (F-03).

**G3 — the review band is reachable and single-counts** · `test/features/capture/review_queue_test.dart`
*Arrange:* ingest `'Transaction ₹88 at CHAI POINT successful'` from `com.phonepe.app` (0.70), plus a bank SMS for the same ₹88 that auto-accepts.
*Act:* read the queue **through the provider the screen uses** (not `PendingReviewRepo` directly — *that* is the bug); then `approve()`.
*Assert:* one entry with `rawText` intact and `amount == 8800`; after `approve()`, `txnDao.count() == 1` (F-06/F-07). Pinning "1, not 2" is the point.

**G4 — two same-amount payments inside 10 minutes** · `test/data/repos/ledger_repo_test.dart`
*Arrange:* GPay `'₹40 paid to Chai Point'` at 09:00 and 09:04, **different refs**; first auto-accepts.
*Act:* ingest the second.
*Assert:* `count() == 2`. Then repeat with **identical** refs → `count() == 1`, `status == duplicate`. **Fails today on the first half** (F-05).

**G5 — dedup bucket edges** · `test/data/parsers/dedup_engine_test.dart`
*Arrange:* two ref-less, same-amount, same-merchant parses at `09:59:59` and `10:00:01` (`bucketMs = 600000`, `dedup_engine.dart:11`).
*Act:* `DedupEngine.fingerprint` on both.
*Assert:* keys differ **and** both land in the ledger when ingested 2 min apart. Then the same pair 30 s apart **with the same ref** → one row. Pin the policy in the test name.

**G6 — month boundary, IST-new-year style** · `test/data/repos/budget_repo_test.dart`
*Arrange:* wallet ₹5,000 monthly, `rollover: false`; seed `DateTime.utc(2026,10,31,20,30)` (= 02:00 IST 1-Nov) ₹1,000.
*Act:* `statusOf(now: DateTime.utc(2026,11,1,6,30))` (= 12:00 IST).
*Assert:* `spent == 0` (it belongs to October). **Fails today** (F-01) — the fixture an accountant would write.

**G7 — idle unload must not fire mid-conversation** · `test/features/ai/model_idle_test.dart`
*Arrange:* `ModelManager(idleTimeout: 50ms)` + fake engine; `load()`; simulate inference at t=40 ms.
*Act:* pump to t=90 ms.
*Assert:* `isLoaded` still true; then unloads 50 ms after the last activity. **Fails today** (F-10).

**G8 — guardrail blocks what the model actually emits** · `test/features/ai/guardrail_test.dart`
*Arrange:* the seven strings from §4.2.
*Act:* `filter(s, context: GuardrailContext(isRoast: true))`.
*Assert:* `blocked == true` and `text` ∈ `GuardrailRules.safeTemplates` for **each**. All seven fail today (F-09).

**G9 — v1 → v2 migration on a real file** · `test/data/db/migration_v2_test.dart`
*Arrange:* temp file DB at `dbVersion = 1` with the v1 DDL, 2 txns, close.
*Act:* open with `dbVersion = 2` + the step; then open at v3 **without** a step.
*Assert:* data intact, new column present; the v3 open returns a handled `DatabaseFailure` rather than throwing out of `onOpen` (F-28).

**G10 — CSV/cash boundary round-trip** · `test/data/csv/csv_round_trip_test.dart`
*Arrange:* txns at `00:00:00.001` and `23:59:59.999` IST, one credit, one with `.05`, one merchant containing `"` `,` `\n` and Devanagari.
*Act:* `CsvService.toCsv` → `CsvStatementParser.parse`.
*Assert:* same row count, same paise total, same IST day for both boundary rows, escaped merchant byte-identical. Assert against **explicit** ISO dates derived from real IST instants, never from `IstDates` (else the test inherits the bug).

*Cheaper honourable mentions:* kv counter atomicity under `Future.wait([pipeline.run, pipeline.run])` (F-17); `confirm()` with one `fuzzy` row and its override (F-12); `TxnRow` semantics label; `capture_event` retention.

---

## 7. Release checklist

**Before a closed-test Play track (`--flavor play`)**

1. **Keystore wired and build-enforced** (F-13). No debug-signed release may exist.
2. **POST_NOTIFICATIONS requested** (`SDK_INT >= 33`) + permanent-denial banner fallback (F-08). Without it the app is silently deaf.
3. **F-01 + F-04 fixed, G1/G6 green.** Don't ship a money app whose "today" is 5 h 30 m wrong and whose manual spends don't move the budget.
4. **F-03 fixed, G2 green.** Don't ship a WAL that deletes what it failed to ingest.
5. **Review band reachable** (F-06/F-07) — or set `reviewMin == autoAcceptMin` honestly and delete the table. Half-built is worse than both.
6. **`static_verify.py` + a release build of both flavors in CI** (F-13). R8+SQLCipher is a documented field failure.
7. **Deletion path exists** (F-14, F-41) — Play's Data-safety form asks for it, and `wipeAll`'s own comment claims it.
8. **Play artifacts:** in-app explanation before the notification-access jump (the gate screen exists — mirror the copy in the listing), privacy-policy URL, and a Data-safety form declaring *Financial info → transaction history*, collected, **not shared**, deletion available.
9. **README/AGENT_LOG claims struck or implemented** (F-21).
10. **`targetSdk` pinned explicitly** in `build.gradle.kts` (today it inherits `flutter.targetSdkVersion`, so a Flutter bump silently moves your Play target).
11. **Release smoke on hardware:** fresh install → onboarding → capture gate → one real bank notification → appears in Aaj; kill + post → reopen → appears; reboot → listener rebinds.

**Additionally before the first power-flavor sideload**

12. **SMS rationale + post-denial honesty** ("SMS capture band hai"), not an empty ledger.
13. **`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` flow tested** on HyperOS and realme UI — the OEM matrix is theory until then (F-38).
14. **Confirm zero `INTERNET` in the release AAB** on device (`adb shell dumpsys package in.udao.app`).
15. **F-15 decided** — encrypt the WAL or accept 7 days of plaintext bank SMS in writing.
16. **No crash reporting by law ⇒ manual soak is the gate:** 30 min with the model loaded + receipt scan + PDF import + CSV export + a 3-round chat + 20 min backgrounded + kill/reopen, `logcat` captured, no `FATAL EXCEPTION`.

---

## 8. Runnable verification commands

Windows 11, PowerShell 5.1, repo at `D:\udao`. **No `&&`** — `;` or separate lines only.

```powershell
# 0. Baseline — does it even build/analyse/test here?
cd D:\udao
flutter --version
flutter pub get
flutter analyze
dart format --set-exit-if-changed lib test
flutter test
python tools\static_verify.py
python tools\analyzer_shadow.py
```

```powershell
# 1. F-01 / F-04 — prove the date bug in 20 lines of Dart, before believing me.
@'
void main() {
  const off = Duration(hours: 5, minutes: 30);
  final DateTime nowIst = DateTime.now().toUtc().add(off);
  final DateTime start = DateTime.utc(nowIst.year, nowIst.month, nowIst.day);
  final DateTime end   = DateTime.utc(nowIst.year, nowIst.month, nowIst.day, 23, 59, 59, 999);
  print('window start epoch = ${start.toIso8601String()}Z  (true IST ${start.toLocal()})');
  print('window end   epoch = ${end.toIso8601String()}Z');
  final DateTime manual = DateTime.utc(nowIst.year, nowIst.month, nowIst.day, 6, 30).add(off);
  print('quick_add stamp    = ${manual.toLocal()}  <-- note 17:30');
  print('manual inside [start..now]? ${!manual.isAfter(nowIst)}  <-- false before 18:00 = F-04');
}
'@ | Out-File -Encoding utf8 D:\udao\tool_datecheck.dart
dart run D:\udao\tool_datecheck.dart
Remove-Item D:\udao\tool_datecheck.dart
# EXPECT, at any time before 18:00 IST: "manual inside ...? false"  -> budget ignores your own entry.
```

```powershell
# 2. F-01 / F-04 on a device — the user-visible version
adb shell am start -n in.udao.app/.MainActivity
adb shell cmd notification post -S bigtext -t "HDFC Bank" tag "Rs.148.00 debited from A/c No. XX1234 on 04-11-26 to SWIGGY. Avl Bal Rs.1000"
#   Aaj: does it appear? scroll to Ledger: is it filed under "Aaj" or "Kal"?
#   At 00:00-05:29 IST: EXPECT "Kal" (F-01).
# Now add a manual entry of Rs.500 at 08:00 IST -> open /budgets
#   EXPECT today: rekha unchanged until 18:00 (F-04).
```

```powershell
# 3. F-03 — WAL ack-on-failure. Corrupt the open, watch the WAL empty itself.
adb shell run-as in.udao.app wc -l /data/data/in.udao.app/no_backup/capture_wal.jsonl
#   (post 3 notifications first)
adb shell run-as in.udao.app mv databases/udao.db databases/udao.db.bak
adb shell am force-stop in.udao.app
adb shell am start -n in.udao.app/.MainActivity
adb shell run-as in.udao.app wc -l /data/data/in.udao.app/no_backup/capture_wal.jsonl
#   EXPECT today: 0 (ack'd despite every ingest failing). EXPECT after fix: 3.
adb shell run-as in.udao.app mv databases/udao.db.bak databases/udao.db
```

```powershell
# 4. F-08 — no runtime notification permission on Android 13+
adb shell cmd appops get in.udao.app POST_NOTIFICATION
adb shell dumpsys package in.udao.app | Select-String "POST_NOTIFICATIONS|INTERNET"
#   Revoke listener access, wait for the 30-min ping, then:
adb shell cmd notification allow_listener in.udao.app/in.udao.app.capture.UdaoNotificationListener false
Start-Sleep -Seconds 60
adb shell dumpsys notification --noredact | Select-String "capture ruk gaya"
#   EXPECT today: nothing, and no dialog was ever shown.
```

```powershell
# 5. F-13 — what the release build actually is
flutter build apk --release --flavor play
flutter build apk --release --flavor power
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\35.0.0\apksigner.bat" verify --print-certs build\app\outputs\flutter-apk\app-play-release.apk | Select-String "CN="
#   EXPECT: "CN=Android Debug" today -> not uploadable.
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\35.0.0\aapt2.exe" dump permissions build\app\outputs\flutter-apk\app-play-release.apk
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\35.0.0\aapt2.exe" dump permissions build\app\outputs\flutter-apk\app-power-release.apk
#   play: no INTERNET, no RECEIVE_SMS/READ_SMS.  power: SMS yes, INTERNET no.
```

```powershell
# 6. Release-build DB smoke — the R8/SQLCipher class of bug
adb install -r D:\udao\build\app\outputs\flutter-apk\app-play-release.apk
adb logcat -c
adb shell am start -n in.udao.app/.MainActivity
Start-Sleep -Seconds 20
adb logcat -d | Select-String "SQLCipher|UDaoCapture|FATAL EXCEPTION|flutter"
#   EXPECT "SQLCipher active: <version>" (udao_database.dart:133).
```

```powershell
# 7. F-10 — the model unloads 5 min after load, not 5 min after last use
#   Import a model, send one chat, wait 6 min, send another.
adb logcat -d | Select-String "udao-ai|UDAO_AI|model"
#   EXPECT a reload round-trip before answer #2 (or a template answer with no notice).
```

```powershell
# 8. F-15 — plaintext at rest vs the encryption claim
adb shell run-as in.udao.app cat /data/data/in.udao.app/no_backup/capture_wal.jsonl
#   EXPECT readable JSON incl. your bank SMS body (7 days).
adb shell run-as in.udao.app head -c 64 /data/data/in.udao.app/databases/udao.db
#   EXPECT binary garbage. The contrast is the finding.
```

```powershell
# 9. F-16 / F-38 — watchdog ladder + OEM reality
adb shell dumpsys jobscheduler | Select-String "udao_capture_health_pinger" -Context 0,6
adb shell am force-stop in.udao.app
Start-Sleep -Seconds 40
adb shell dumpsys jobscheduler | Select-String "udao_capture_health_pinger" -Context 0,6
#   EXPECT a 30-min periodic job (REPEAT_MINUTES = 30L). If it is CANCELLED/FAILED
#   and never comes back after an app open -> F-16 (KEEP never replaces).
```

```powershell
# 10. F-06 / F-07 — review band invisibility + approve double-count
flutter run --debug
#   Post: "₹88 paid to CHAI POINT" (PhonePe), then the HDFC SMS for the same ₹88.
#   EXPECT: a pending_review row exists, and NO screen anywhere can show it.
```

```powershell
# 11. F-17 — counter atomicity (fix first, then this proves it)
flutter test test/features/capture/capture_pipeline_test.dart
#   Add: Future.wait([pipeline.run(a), pipeline.run(b)]) then expect cap_txn == '2'.
#   EXPECT today: '1' about half the time.
```

---

## 9. Honesty section — where I stopped

- **No Flutter/Dart SDK in this sandbox.** Everything is source reading + `static_verify.py` (exit 0) + the arithmetic/regEx replays in §4. `C` means "certain from the code as written", not "observed". The four findings I would not ship without device confirmation: **F-01** (needs the 02:00 test on hardware), **F-08** (`appops`), **F-16** (real WorkManager behaviour on HyperOS), **F-13** (release APK smoke).
- **Phase 09 is unauditable — the code is not here.** Your risk (b) cannot be scored. If it exists elsewhere, **it inherits F-01 and F-04**, because every midnight/day-boundary computation it needs is built on the same `IstDates` helpers and the same `_occurredAt` pattern.
- **`docs/oem-survival.md` was read as documentation, not verified.** Its claims about MIUI/HyperOS/ColorOS are only settleable by `tools/oem_test.sh` on real hardware.
- **Not audited, on purpose:** onboarding beyond the notification step, the typography/theme system, the SVG asset set, and the AI model pack plumbing. Low risk for your questions — say the word and I'll do them as a focused pass.
