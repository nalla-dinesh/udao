# Phase-06 Completion Report — On-Device AI Core

**Status: production code complete, statically verified (0 errors), analyzer-shadow clean.**
**Sandbox law:** no Flutter/Dart/Android SDK here — `flutter analyze` + `flutter test`
run on the Windows box (expect small fix-ups; TODO-VERIFY(local) marks the
device-only seams).

---

## 1. What shipped

### 1.1 Native seam (Kotlin) — ADR-0007
- **`android/app/src/main/kotlin/in/udao/app/ai/AiBridge.kt`** (NEW): our own thin
  MediaPipe seam over `com.google.mediapipe:tasks-genai:0.10.35` (pinned, the
  2026-04 latest).
  - MethodChannel `udao/ai`: `loadModel, unload, isLoaded, createSession,
    closeSession, generate, generateVision, cancelGenerate` (8 methods, parity
    pinned by static_verify §6p + `test/features/ai/bridge_contract_test.dart`).
  - EventChannel `udao/ai/stream`: token/done/error events with sessionId
    routing (multi-session safe).
  - **Cancel = `cancelGenerateResponseAsync()`** (from MediaPipe sources, not
    the guide); `session.cancel()` deliberately absent.
  - Engine discipline: mutex-serialised load/generate/unload, refuse 2nd
    concurrent generation, refuse model >60% of total RAM, `.part` + atomic
    rename copy, free on memory pressure, `BitmapImageBuilder` vision path.
- **`MainActivity.kt`**: `totalRamMb` via `ActivityManager.MemoryInfo` (own
  channel — device_info_plus RAM field names drift between majors; researched
  and rejected).
- **Gradle**: `implementation("com.google.mediapipe:tasks-genai:0.10.35")`.
- **`.gitignore`**: `*.task`, `*.litertlm`, `*.gguf` — model binaries NEVER in
  the repo (verified: zero binaries in lib/assets).
- **Zero new Dart deps.** `flutter_gemma` (discontinued) and `flutter_edge_ai`
  (native-assets hooks, multi-package, network installs, maintenance-only
  engine) both researched and rejected → ADR-0007.

### 1.2 Model management (`lib/features/ai/model/`)
- `model_manager.dart`: discovery PAD staging → imported dir → kv registry;
  import validation (`.task` ext, 50 MB–5 GB, SHA-256 stored + re-verified at
  every load — corruption fails closed); single resident model; 5-min idle
  unload; preload toggle (default OFF); memory-pressure unload; tiering.
- `model_tier.dart`: RAM <5 GB → FunctionGemma-270m class, ≥6 GB → E2B,
  ≥8 GB → E4B; unknown RAM → conservative small; fits() is advisory only.
- `model_file_store.dart`: dart:io store + in-memory test double.
- `model_source.dart`: BundledAsset / ImportedFile / Absent.

### 1.3 Runtime (`lib/features/ai/runtime/`)
- `llm_runtime.dart` + `llm_events.dart`: `Stream<LlmEvent> generate(LlmRequest)`
  + cancel/isLoaded; sealed Token/Done(usage)/Error; ModelFailure codes
  (`model-absent`, `ai-not-loaded`, `ai-load-failed`, `ai-oom`,
  `ai-generation-error`, `ai-busy`, `ai-no-vision`, `ai-invalid-output`).
- `ai_engine.dart`: AiInferenceEngine over the channels (Dart side of §6p).
- `gemma_runtime.dart`: session-per-request, Gemma IT turn scaffolding,
  cumulative→delta diffing (robust to either engine semantic), stop-marker
  trim, error mapping, silent-cancel poller, cancel propagates to the bridge.
- `template_only_runtime.dart`: ALWAYS available; roast-tagged requests get
  the template floor (**roast NEVER dies without a model**), free-form asks
  stream an honest `model-absent`.

### 1.4 Agent loop + 10 tools (`lib/features/ai/agent/`)
- `agent_loop.dart`: ≤5 iterations (hard cap, honest capped answer text),
  first-balanced-JSON tool extraction (prose/nested-brace tolerant), schema
  validation, repair-once, cancellation, metrics-only logs (`iter N ms=… tokens~…`,
  `tool X ms=… ok=…` — never content), history capped to last 6 turns.
- `agent_tools.dart`: query_spends, get_budgets, set_budget,
  get_subscriptions, predict_month_end (daily-avg × days), add_transaction,
  recategorize, get_streak, list_categories, export_report — each ≤60 lines,
  every error an honest `{'ok': false}`.
- `tool_prompt.dart`: EN scaffolding + Hinglish answer rules + ₹ + never
  invent transactions; schemas rendered from the SAME AgentTool objects the
  validator uses (prompt/validator cannot drift).
- `context_builder.dart`: ~2000-char deterministic snapshot (month spends +
  deltas, streak, WALLET BUDGET, SUBSCRIPTIONS, recent roast ids
  anti-repeat, PERSONA, TODAY) with injectable clock.

### 1.5 Persona + guardrail (`lib/features/ai/persona/`)
- savage (default, temp .9) / hype (.8) / silent (.3) / sensei (.6) with
  templateTag + allowedSurfaces.
- `guardrail.dart` — HARD, on EVERY generated line (chat answers, roasts,
  model rewrites, Hype included): slurs, person-directed alarmism, panic/
  medical triggers, essential-category screen (roast context), 280-char trim,
  4 safe fallback templates, `ai.guardrail.blocks` counter, fail-open.
- `stress_detector.dart`: 2-of-3 behavioural proxies (7d vs 30d spend-rate
  drop >50%, app-open days 14v14 drop >50% with prior≠0, 3+ consecutive
  budget-pace breach days) → router forces Sensei 72 h; `stampAppOpenDay`
  called from main.dart; pin wins (manual override is king).
- `persona_router.dart`: base from prefs, stress window, pin, clearStress.

### 1.6 Roast engine (`lib/features/ai/roast/`)
- `roast_templates.dart`: **exactly 60** templates (12 food, 8 shopping,
  8 subscriptions, 10 overspend, 8 streak-win, 6 month-end, 4 salary-day,
  4 no-spend), slots {merchant}/{amount}/{delta}/{days}/{count}/{streak}.
- `roast_engine.dart`: score = relevance×10 − freshness(−100 within 3 d) −
  |intensity − wanted|; slot fill (a slot NEVER leaks); model-variation pass
  rewrites in Savage voice only when loaded AND targetsSpend; guardrail
  ALWAYS last; roast_entry insert + markUsed (last 20).
- `roast_floor.dart`: day-of-year rotation for the template-only runtime.

### 1.7 LLM fallback parser + learned patterns (`lib/features/ai/parser_fallback/`)
- `llm_parser.dart`: strict-JSON out, 5 real-corpus few-shots, confidence
  floor 0.65, honest codes; `FallbackParseService` updates pending rows
  (NEVER auto-inserts) + proposes a learned regex in kv.
- `learned_pattern.dart`: escape literals → typed named groups; approve/
  dismiss in Settings (human-in-the-loop, nothing model-made enters the
  parse chain silently).

### 1.8 Chat + settings UI
- `chat_controller.dart` + `chat_models.dart` + `chat_history_store.dart`
  (kv, cap 50, DPDP clear-all) + `chat_screen.dart`: bub-ai/bub-user
  streaming bubbles, tool chips (name + args + ms + ✓), persona indicator,
  template-only banner, stress notice card, Hinglish suggested prompts, stop
  button, voice + receipt attachment, history + clear-all.
- `ai_settings_screen.dart`: model discovery/import/delete/load, tier advice
  (honest "file bada hai" signal), preload toggle (battery-honest copy),
  telemetry dashboard (estimated tokens, avg latency, tool ok/fail,
  guardrail blocks), learned patterns approve/dismiss, pending-review drain.
- `gemma_vision_parser.dart`: ReceiptModelParser via REAL pixel-multimodal
  (addImage + GraphOptions vision); strict-JSON prompt; ensemble rules ≥0.7
  → model → human-confirm; `model-absent` = closed honestly.

### 1.9 Docs
- `docs/adr/ADR-0007-ondevice-ai-mediapipe-seam.md` — why own seam, why not
  flutter_gemma/flutter_edge_ai.
- `docs/ai/models.md` — real artifacts + URLs (Kaggle/HF/litert-community),
  Gemma vs Apache licensing, PAD + SAF side-load + adb walkthrough.
- `docs/ai/asset-delivery.md` — on-demand pack `gemma3n_e2b`, file
  `gemma-3n-e2b-it-int4.task`, Play Core fetch deliberately deferred.

---

## 2. Verification (sandbox-side)

| Check | Result |
|---|---|
| `python3 tools/static_verify.py` (incl. new §6p AI contract) | **PASS, 0 errors** |
| `python3 tools/analyzer_shadow.py` (symbol-level import check) | **0 problems** |
| ARB parity en/hi | 318 = 318 keys ✓ |
| l10n getters in app_localizations.dart | 293 (≥60 phase-06) ✓ |
| Model binaries in repo | 0 ✓ |
| TODO-VERIFY(local) markers | 3 (gemma chat template, vision path, bridge load-result shape) |
| New AI test statements | 155 ai + 14 chat = **169** (19 files) |

§6p pins: channel parity (2), 8-method parity, `cancelGenerateResponseAsync`
present + `session.cancel()` absent, gradle pin, totalRamMb, gitignore +
no-binaries, no flutter_gemma import, RoastTemplate count == 60,
maxIterations == maxToolRounds == 5, guardrail in chat_controller AND
roast_engine, metric-only agent logs, ≥60 phase-06 l10n getters.

## 3. Tests (19 files, to run locally with run #3)

agent_loop (10: happy, repair, unknown-tool, cap, tool-error, cancel, error
mapping, empty, nested-JSON, history cap) · guardrail (~40 verdicts) ·
stress_detector (pure 2-of-3 ×8 + gatherer-on-DB ×7 + stamping) · persona +
router (×10) · tool_prompt (×8) · roast_templates (corpus ×9) · roast_engine
(×9) · runtime (TemplateOnly ×3 + Gemma diffing/error/trim/format ×5) ·
model_manager (discovery/import/load/SHA/idle/preload/pressure/delete ×16 +
tiering ×5) · parser_fallback (parser ×8 + learned pattern ×3 + store/service
×3) · context_builder (snapshot ×7) · ai_telemetry (×6) · agent_tools (10
tools on real DB ×13) · bridge_contract ×8 · chat_history_store ×5 ·
chat_controller ×6 · chat_screen widget ×3 + 1.

**Expected local total: ~597 (phase-05 baseline) + ~160 = ~755 green.**

## 4. Sandbox limitations → local run checklist
1. `flutter analyze` — expect minor fixes (Phosphor icon names, unused
   imports flagged as info). static_verify + analyzer-shadow are green, so
   nothing structural.
2. `flutter test` — run #3.
3. TODO-VERIFY(local)×3: real `.task` model chat-template acceptance,
   vision path, AiBridge load-result map keys.
4. Import a real E2B model on-device via AI Settings → SAF, then: roast,
   free-form ask, tool chips, cancel mid-stream, idle unload after 5 min.

## 5. Honesty ledger
- MediaPipe `maxTokens` default 512 = input+output total (docs) — we pass 1024.
- Tokens are chars/4 estimates, always labelled "estimated".
- Prediction is deliberately simple (daily-avg × days) — phase-07 upgrades it.
- PAD/Play-Core delivery is designed + documented, fetch wiring deferred.
