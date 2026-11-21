# UDAO — *paise udte dekho*

**A fully on-device, Hinglish-first, agentic expense tracker with attitude.**

UDAO watches the money that leaves your phone — UPI notifications, bank SMS, imported statements, receipts — writes it all into an **encrypted ledger only you can read**, and then does what no tracker dares: it **roasts you** about it. Every evening it delivers a verdict. When you go a day without spending, the streak game pays you off. Nothing ever leaves the device. There is no server, no account, no analytics, no network code at all.

| | |
|---|---|
| **Platform** | Flutter (Dart ≥ 3.5) · Android (minSdk 26) · power + play flavors |
| **Storage** | SQLite over **SQLCipher** (encrypted at rest) + write-ahead WAL for zero-loss capture |
| **Intelligence** | On-device **Gemma 3n** via MediaPipe tasks-genai — with a template engine floor so nothing ever dies |
| **Network calls** | **Zero.** No permission, no code path, no dependency that can dial out (ADR-0001) |
| **Voice** | Hinglish first (`hi`), English fallback — 410 l10n keys, hand-written delegate |
| **Tests** | 90 files, ~876 passing (unit + widget + e2e pipeline), analyzer-clean, static-verify gate |

---

## 1. Why UDAO exists

Every expense tracker dies the same death: **manual entry**. You stop typing, the ledger rots, the app becomes a lie. UDAO inverts the model — the ledger writes itself from the notifications your phone already receives, and the product's engagement loop is not shame-addictive dashboards but **entertainment with honesty**: a roast engine that knows exactly what you spent, a verdict every evening, and a streak game that pays you for the one thing trackers never reward — *not* spending.

The blueprint promise, phase by phase, is tracked in `AGENT_LOG.md` and fully delivered through phase 09: auto-capture, roast, chat agent, budgets, streak game, notifications, share cards, export.

## 2. The laws (non-negotiables)

These are enforced by architecture, tests, and static checks — not by policy documents nobody rereads:

1. **No network. Ever.** (ADR-0001) The dependency list is audited; no package with a network surface ships; the `play` flavor's manifest contains **no `INTERNET` permission at all** — verify it yourself by decompiling the APK. Model files arrive by user import, not download.
2. **Encrypted at rest.** (ADR-0004) The ledger is SQLCipher; the key lives in Android secure storage. A stolen phone yields ciphertext.
3. **Nothing fake.** If a state can't be read, the app says *"pata nahi"* — never a healthy guess (power state, standby bucket, token counts labeled *estimated*). A no-spend streak is never backfilled; the game only claims days the ledger can prove.
4. **The roast never harms.** A hard guardrail runs on **every** generated line — slurs, alarmist language, panic/medical-anxiety triggers, and roasting essentials (rent, medicine, education) are blocked; 280-char cap. Template floor means a roast exists even with zero model loaded.
5. **No codegen.** (ADR-0003) Hand-written models with round-trip tests, a hand-written l10n delegate. Every line is auditable by reading it.
6. **Your data leaves only through your fingers.** Export/share is an explicit tap (CSV sheet, PNG card). There is no other path out.

## 3. The 60-second tour

- **Aaj** — today's spend as a huge count-up hero, vs-yesterday delta, the day's movement, your *Lakshman Rekha* (budget) strip, and (after 5 PM) the evening verdict card you can share as a PNG.
- **Chat** — an agent that *actually knows your ledger*: ask "is mahine kya jyaada gaya?", it calls tools (`query_spends`, `predict_month_end`, `set_budget`, …) and answers in Hinglish, streamed, on-device.
- **Khel** — the no-spend streak game: flame hero, freezes to save a streak, the Chindi Ladder (3→50 days), badges, challenges. Shareable.
- **Ledger** — day-grouped history with merchant-tinted rows and per-day totals.
- **Settings** — capture health dashboard, AI model import, budgets, OEM survival guides, CSV export.

## 4. Architecture map

```
┌────────────────────────────────────────────────────────────────────┐
│  UI SHELL — go_router · Aaj / Chat / Khel / Ledger / Settings      │
│  (design system: UdaoCard, MoneyDisplay, SectionHeader, RoastCard) │
├────────────────────────────────────────────────────────────────────┤
│  FEATURE LAYER                                                      │
│  capture (pipeline, gap, import, receipt, quick-add)                │
│  ai (model mgr, runtimes, roast engine, agent, personas, guardrail) │
│  budget · khel · notify (spend roasts) · share (PNG cards)          │
├────────────────────────────────────────────────────────────────────┤
│  DATA LAYER — DAOs · repos · 11 bank/UPI parsers  (pure Dart)       │
├────────────────────────────────────────────────────────────────────┤
│  SQLCIPHER DB — 13 tables · WAL · versioned migrations  ENCRYPTED   │
└───────────────────────────────▲────────────────────────────────────┘
                                │  platform channels (method/event)
┌───────────────────────────────┴────────────────────────────────────┐
│  KOTLIN LAYER (in.udao.app)                                         │
│  CaptureBridge · UdaoNotificationListener · SmsGate (power)         │
│  WalWriter · BootReceiver                                           │
│  HealthPinger (30-min watchdog) · NotificationGateway ·             │
│  SurvivalBridge · KeepAliveService · ExitInfoProbe · PowerStateProbe│
│  AiBridge (MediaPipe tasks-genai 0.10.35 — LLM + vision sessions)   │
└────────────────────────────────────────────────────────────────────┘
```

**Boot sequence** (`lib/main.dart`): the ProviderContainer is created *before* the widget tree; the data-layer warm-up opens the DB, pushes the parser allowlist, **replays the WAL** (spends captured while the app was dead are never lost), starts the live event daemon, judges yesterday's Khel day, arms the WorkManager jobs, stamps the app-open day for the stress detector, and starts the spend-roast daemon. First frame is never blocked by any of this.

## 5. How money gets in (six capture ports)

| Port | What it catches | Notes |
|---|---|---|
| **Notification listener** | UPI/bank-app notifications (GPay, PhonePe, Paytm, banks) | The main port; needs explicit Notification Access grant; survives via the watchdog below |
| **SMS receiver** (power flavor only) | Bank transactional SMS | Runtime permission, gated screen; play builds honestly report it as unavailable |
| **QuickAdd** | Manual one-tap entry (amount pad + merchant + category chips) | The floor that always works |
| **Statement import** | PDF (via pdfrx text extraction) + CSV | 11 parsers, deduped against the live ledger |
| **Receipt camera** | Photo → MLKit OCR (fully offline) → line items | Optional vision-model ensemble leg; unknown layouts go to human confirm |
| **Chat agent** | *"kal 250 ki chai pe thi"* → `add_transaction` tool | Same validation + dedup as every other port |

Every port feeds the **same pipeline** — there is exactly one door into the ledger.

## 6. How the analysis works (the deep dive)

This is the heart of the product: raw noise in, an honest, roasted, categorized ledger out.

### 6.1 The ledger pipeline

```
raw event (notification / SMS / file / manual)
   │
   ▼
FILTERS ──── non-transactional noise dropped (OTP, promos, balances…)
   │
   ▼
PARSE ────── 11 bank/UPI parsers (HDFC, SBI, ICICI, Kotak, PNB, BoB,
   │         Axis, GPay, PhonePe, Paytm, generic-UPI) extract:
   │         amount · direction · merchant · occurredAt · source
   ▼
CONFIDENCE GATE ── < 0.60 → dropped (health row records why)
   │                0.60–0.79 → pending_review queue
   │                ≥ 0.80 → auto-accept
   ▼
DEDUP ────── dedupKey (normalized amount+merchant+time-window) —
   │         the same UPI notification from two apps lands ONCE
   ▼
CATEGORIZE ─ alias map over 16 seed categories → miss goes to
   │         learned patterns → LLM-fallback proposal (pending)
   ▼
WRITE ────── txn row + capture_event health row + kv metrics
   │
   ▼
TxnCaptured broadcast ── every screen refreshes live; the spend-roast
                          daemon decides whether to roast (see §6.4)
```

Two properties matter as much as the happy path: **nothing is lost** (the Kotlin `WalWriter` journals every raw event before Dart even sees it; boot + app-open replay the last 7 days), and **nothing is lied about** (every drop is a health row with a reason — the gap detector and the capture dashboard are built on exactly this data).

### 6.2 Parsing, honestly

Parsers are hand-written regex/rule machines per bank+app format — fast, offline, debuggable, and each ships with fixture tests taken from real message shapes. The `parser_registry` scores candidates and picks the best. Unknown-bank messages do **not** get guessed into the ledger: below the auto-accept floor they land in *pending review*, and (with a model loaded) the LLM-fallback parser proposes a parse **plus a learned regex** — you approve both once, and the next message from that bank parses by rule, not by model. Intelligence is used to *teach* the deterministic layer, not to replace it.

### 6.3 The AI core (all on-device)

**Model management** (`features/ai/model`): Gemma 3n `.task` files arrive by user import (SAF) or a PAD pack you configure — never auto-downloaded. Validation is fail-closed: extension, 50 MB–5 GB size band, **SHA-256 computed at import and re-verified on every load** (`ai-sha-mismatch` refuses to load a corrupted file). One resident model, 5-minute idle unload, RAM-tier suggestion via the app's own `udao/platform` channel (no device_info_plus RAM drift). See `docs/ai/models.md`.

**Runtimes** (`features/ai/runtime`): a sealed `LlmRuntime` interface with two implementations —
- `GemmaRuntime` — real MediaPipe sessions via `AiBridge.kt` (streaming tokens, cancel, RAM-refusal).
- `TemplateOnlyRuntime` — the floor. **Roasts and templates never die when no model is loaded.**

**The roast engine** (`features/ai/roast`): 60 hand-written Hinglish templates across categories (overspend, month-end, food-delivery, streak-win, no-spend, salary-day). Selection = relevance (shape-driven: the request carries merchant/amount/overspend%/delta/streak) + **freshness** (no reuse within 3 days, kv-tracked) + **intensity ramp** (the higher the overspend %, the sharper the shelf). Slots never leak unfilled. If a model is loaded *and* the template targets spend, the model rewrites the body in Savage voice — **numbers stay exactly as the template filled them**. The result is then **always** run through the guardrail (§2 law 4) and persisted to `roast_entry` for the telemetry/learned-pattern screens.

**Personas** (`features/ai/persona`): Savage (default), Hype, Silent, Sensei. A **stress detector** (2-of-3 signals: spending spike, app-open slump, roast-intent chat rate) switches the app to Sensei — the kind teacher — for 72 hours. A user pin always wins.

**The agent** (`features/ai/agent`): a 5-iteration tool loop with a balanced-JSON extractor and a repair-once retry. Ten read/write tools over the encrypted ledger: `query_spends`, `get_budgets`, `set_budget`, `get_subscriptions`, `predict_month_end`, `add_transaction`, `recategorize`, `get_streak`, `list_categories`, `export_report`. Without a model, chat degrades honestly to a "seedha-jawab mode" banner and the tools still work from the UI.

**Receipt vision**: MLKit OCR is the floor; with a vision-capable model the ensemble adds a multimodal leg — agreement ≥ 0.7 auto-accepts, anything lower goes to human confirm. Never a silent guess.

### 6.4 The voice: notifications (phase 09)

Three channels, one Kotlin gateway (`NotificationGateway` — no `flutter_local_notifications`, no new plugins):

| Channel | Id | What |
|---|---|---|
| `capture_service` | 1001 | keep-alive foreground-service notice (user opt-in) |
| `capture_health` | 1002/1003 | capture-down escalation (max 1/24 h), weekly gap alert |
| `udao_verdict` | 1004 | evening verdict teaser + spend-moment roasts |

The **evening teaser** is posted by the Kotlin watchdog in the 20:00–22:59 IST window, once per IST day — copy is deliberately generic because the worker cannot read the encrypted ledger; the data-driven verdict lives on the Aaj screen the notification opens. The **spend roast** is a foreground Dart daemon (wired in `main()`): a captured **debit ≥ ₹200**, inside 08:00–22:00 IST, max **3 per day** (kv-counted), quiet hours respected, credits never roasted, body always guardrail-passed engine output. `MainActivity` makes the one-time `POST_NOTIFICATIONS` runtime ask (without it, Android 13+ silently drops every notification).

**Share cards** are WYSIWYG: the live `RepaintBoundary` is rasterized at 3× (`toImage`) to a PNG and handed to the OS sheet via `share_plus` — what the user sees is exactly what the friend receives (roast card on Aaj, streak hero on Khel). **CSV export** (Settings) is the ledger's only other door out.

### 6.5 What the analysis tells you

- **Lakshman Rekha — budgets** (phase 08): wallet-level and per-category lines, weekly/monthly IST windows, **rollover semantics** (unspent previous period lifts the current line; a blown period carries *nothing* — debt does not travel), exceeded = flame accent + cross stamp, live refresh on every capture. Chat and UI write the same rows (`id = categoryId ?? 'wallet'`).
- **Khel** (phase 07): no-spend-day streak with freezes (2/week, banking, protective never advancing), the Chindi Ladder (3/7/14/21/30/50 → Seedha→Chindi Samrat), badges, 7/30-day challenges. Judged in `main()` **after** WAL replay so yesterday's late-captured spends count before streak rules run.
- **Predictions**: `predict_month_end` extrapolates spend-to-date over the period window (the spend window is `[periodStart, now]` — never spends that haven't happened).
- **Subscriptions**: recurring-merchant detection feeding a "subscription slayer" view.
- **Gap detector**: 14-day capture-event reconstruction; if transactions went missing, you get one honest gap alert + the screen that shows exactly where.

## 7. Survival engineering (ADR-0006)

Android kills background work; UDAO's core promise is background capture. The strategy, all verified against OEM behavior and documented in `docs/oem-survival.md`:

- **30-minute `HealthPinger`** (WorkManager): checks listener health and runs a recovery ladder — `rebind → 5 s wait → component toggle → 5 s wait → escalate` (ONE high-priority notification per 24 h, cooldown persisted). Its snapshot mirrors into prefs for the Dart dashboard; a pure-Dart `WatchdogPlanner` is the parallel spec, pinned to the same constants by a contract test.
- **WAL + `BootReceiver`**: every raw event is journaled Kotlin-side before Dart sees it; boot and app-open replay the last 7 days. A dead-app day still lands in the ledger.
- **`KeepAliveService`** (specialUse FGS): explicitly opt-in, battery cost stated in the UI — the user's call, never hidden.
- **OEM matrix**: manufacturer-aware deep links (MIUI, ColorOS, Funtouch, One UI…) with try/catch and honest manual fallbacks; `ExitInfoProbe` reads process-death history to tell you *how* Android killed it.
- **Flavor split** (ADR-0002):

  | Flavor | Capture sources | Distribution | Notes |
  |---|---|---|---|
  | `play` | Notifications only | Google Play (closed testing) | Store-compliant; no SMS; manifest has no INTERNET permission |
  | `power` | Notifications + bank SMS | Sideload (GitHub/F-Droid) | Play's SMS policy means sideload-only; adds the ignore-battery-optimizations dialog |

  Both flavors share one `applicationId` (`in.udao.app`). Release builds: `flutter build apk --release --flavor power`.
- **The ADR-0006 law**: background Dart isolates (workmanager jobs) can never reach MainActivity-registered channels — so background notifications are Kotlin-only; the Dart spend-roast daemon is foreground-only by design.

## 8. Data model & privacy

13 tables (`lib/data/db/schema.dart`): `category, txn, budget, subscription, streak_state, badge, challenge_progress, jar, roast_entry, capture_event, pending_review, embedding, kv` — versioned with batched migrations. The `kv` table doubles as the app's durable state store (roast freshness, verdict day-cache, counters, persona pins).

- **At rest**: SQLCipher (key in secure storage). **In flight**: nothing — there is no flight.
- **DPDP posture**: chat history is user-clearable in one tap; telemetry is on-device only (token counts labeled *estimated* because MediaPipe reports no usage); zero third-party analytics.
- **Model binaries** never enter the repo (gitignored); they are user-imported files in app-private storage.

## 9. Tech stack & dependency philosophy

~22 runtime dependencies, every one pinned with a `# verify-latest` marker for the monthly sweep, **zero with network surfaces**: `sqflite_sqlcipher`, `flutter_riverpod` (hand-written providers — no codegen), `go_router`, `pdfrx` (PDF text, isolated behind one adapter seam), `google_mlkit_text_recognition` (offline OCR), `speech_to_text`, `share_plus`, `workmanager` (exact-pinned), `flutter_secure_storage`, `pointycastle` (receipt-vault AES-GCM). UI: custom dark design system (Syne/SpaceGrotesk/Inter, hand-drawn SVG icons — ADR-0005; no Material/Cupertino icon classes in `lib/`, CI-enforced). Localization: a **hand-written delegate** (ADR-0003), 410 keys, `hi` = Latin-script Hinglish (the product's voice), `en` fallback.

## 10. Repository layout

```
lib/
  main.dart                 # bootstrap: DB → WAL replay → daemons → jobs
  app.dart                  # UdaoApp + router + theme + locale resolution
  core/                     # result/errors/log/router/theme/ui/storage/platform
  data/
    db/  (schema, migrations, 11 DAOs)      parsers/ (11 bank/UPI parsers)
    repos/  csv/  models/
  features/
    capture/  (bridge, pipeline, gap, import, quick, receipt, permission)
    ai/       (model, runtime, roast, agent, persona, parser_fallback, telemetry)
    budget/  khel/  chat/  notify/  share/  survival/  onboarding/  settings/
    shell/    (the 5 tab screens)
  l10n/                     # hand-written delegate (arb mirrors in assets/l10n)
android/app/src/main/kotlin/in/udao/app/
  MainActivity.kt  capture/ (CaptureBridge, Listener, SmsGate, WalWriter,
  HealthPinger, BootReceiver)  survival/ (Gateway, Bridge, KeepAlive, probes)
  ai/ (AiBridge)
docs/     adr/ (0001–0007) · ai/ (models, asset-delivery) · oem-survival.md
test/     90 files: unit (parsers, repos, engines) · widget · e2e pipeline
tools/    static_verify.py · analyzer_shadow.py · local_verify.* · oem_test.sh
AGENT_LOG.md               # the build diary: every phase, every errata, every lesson
```

## 11. Build, run, verify

**Toolchain:** Flutter 3.41.x stable (scaffolded against 3.41.4 / Dart 3.11.1; ≥ 3.24 works), JDK 17, Android SDK with compileSdk 36 (resolved by the Flutter Gradle plugin).

```powershell
flutter pub get
flutter run                                # dev (debug defaults)
flutter analyze                            # expect: No issues found!
dart format --set-exit-if-changed lib test # CI runs this too
flutter test                               # expect ~876 passing, 0 failed
flutter build apk --release --flavor power # the release artifact
```

Or run the whole gate in one shot: `bash tools/local_verify.sh` (PowerShell twin: `tools/local_verify.ps1`).

Play flavor swaps SMS + battery-dialog behavior; everything else is identical. First launch: onboarding → notification-access grant (the capture gate explains why) → the ledger starts itself. To unlock the model-voice: download `gemma-3n-e2b-it-int4.task` (Hugging Face, `google/gemma-3n-E2B-it-litert-preview`, ~3.1 GB, 6 GB+ RAM) → Settings → AI → **Import model**. Everything works without it (template floor); the model is the upgrade.

Quality gates beyond `flutter analyze`: `tools/static_verify.py` (repo-specific bans — network imports, `Share.share` 11.x API, sealed-Failure violations, Result mis-uses, l10n arb↔delegate parity, Kotlin import whitelist, watchdog-constant pinning) and `tools/analyzer_shadow.py`. CI: `.github/workflows/ci.yml`.

## 12. Phase history

| Phase | Name | Delivered |
|---|---|---|
| 00 | Foundation | Repo, laws, ADRs 0001–0005, theme + component library |
| 01 | Shell | Router, 5 tabs, onboarding, hand-written l10n |
| 02 | Ledger core | SQLCipher DB, 13 tables, DAOs, ledger repo, 11 parsers, dedup, confidence policy |
| 03 | Capture | Notification listener, CaptureBridge, pipeline, categorizer, health rows |
| 04 | Import + QuickAdd | SMS (power), PDF/CSV import, receipt OCR, QuickAdd, gap detector |
| 05 | Survival | HealthPinger watchdog, WAL, WorkManager jobs, OEM matrix, battery flow |
| 06 | On-device AI | MediaPipe seam (ADR-0007), model manager, runtimes, roast engine + guardrail, personas, agent + 10 tools, chat screen |
| 07 | Khel | Streak game (freezes, ladder, badges, challenges), full UI overhaul |
| 08 | Lakshman Rekha | Budgets with rollover semantics, budget screen, Aaj strip |
| 09 | Awaaz | Verdict notifications, spend roasts, WYSIWYG share cards, CSV export, POST_NOTIFICATIONS fix |

Full detail — including every failure and its lesson — lives in `AGENT_LOG.md` (the errata columns are the most valuable documentation in the repo).

## 13. Known limitations (honesty section)

- Notification capture depends on Android not revoking listener access; the watchdog detects and escalates, it cannot silently resurrect itself on the most aggressive OEMs — the battery-optimization and keep-alive opt-ins exist for exactly this.
- Background timing (WorkManager windows, the 30-min ping) is best-effort and drifts; the UI says so.
- Model quality bounds chat quality; FunctionGemma-class small models limit agent reasoning by design. Template floor always answers.
- Token/usage counts are estimates (MediaPipe reports no usage) — labeled as such everywhere.
- `predict_month_end` extrapolates spend-to-date; it is a trend line, not a promise.
