# ADR-0007 — On-device AI via a hand-rolled MediaPipe seam

**Status:** Accepted (Phase 06) · **Date:** 2026-10-31

## Context

Phase 06 needs on-device Gemma inference: chat agent, roast
variation, the LLM-fallback parser, and the receipt-vision ensemble
leg. The spec suggested `flutter_gemma` (MediaPipe `.task` models).

Verification (pub.dev, Oct 2026) found:

1. **`flutter_gemma` is DISCONTINUED** — final release 1.11.4
   (Oct-2026), replaced by `flutter_edge_ai`.
2. Its dependency tree pulls **`background_downloader`** — a network
   package. ADR-0001 bans network packages outright; worse, plugin
   manifest merging could leak an INTERNET permission into flavors
   that promise "no network".
3. It also depends on **`hooks`/`code_assets`** (Dart native-assets
   builds). This project deliberately avoids native-assets builds —
   the user's toolchain already hit a native-assets cache bug once
   (Phase 04 errata-3: stale `sqlite3.dll`, errno 183).
4. The successor `flutter_edge_ai` (2.5.4) is a six-package
   pluggable ecosystem whose MediaPipe engine is
   "maintenance-only upstream, prefer .litertlm".

## Decision

**Zero new Dart packages.** The on-device runtime is a Kotlin seam
(`android/.../ai/AiBridge.kt`) over
`com.google.mediapipe:tasks-genai:0.10.35` (pinned; verified on
maven.google.com — Apr-2026 latest), exposed through:

- MethodChannel `udao/ai` — loadModel / unload / isLoaded /
  createSession / closeSession / generate / generateVision /
  cancelGenerate
- EventChannel `udao/ai/stream` — cumulative-token, done and error
  events (sessionId-tagged)

This matches how the app already talks to Kotlin (capture bridge,
survival bridge), keeps ADR-0001 intact (no network code can enter
through a Gradle-only dependency), and gives exact control over
streaming, cancellation (`cancelGenerateResponseAsync()` — the only
real stop handle in tasks-genai; verified against the MediaPipe
sources, NOT the `cancel()` name the guide pages suggest) and
memory behavior.

## Consequences

- The Dart side is one thin adapter (`PlatformAiInferenceEngine`);
  everything above it (GemmaRuntime, TemplateOnlyRuntime, agent
  loop) is pure Dart and unit-testable with a fake engine.
- Kotlin API risk is concentrated in ~30 calls, all verified against
  the official Google AI Edge docs + source-derived references, and
  pinned by static_verify §6p parity checks.
- Gemma chat-template acceptance and the vision path carry
  `TODO-VERIFY(local)` markers — only a real device + model file can
  confirm runtime behavior; wiring, validation and fallbacks are
  complete.
- If `flutter_edge_ai` matures into a zero-network, zero-native-assets
  shape, the seam (AiInferenceEngine) can be reimplemented behind it
  without touching any feature code.
