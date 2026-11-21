# ADR-0003 — No codegen in v1 (hand-written models)

- **Status:** Accepted (Phase 00)
- **Date:** 2026-10-27

## Context

UDAO v1 is being built with an AI agent writing code it cannot compile
(the build sandbox has no SDKs — a hard constraint of the workflow).
Codegen (`freezed`, `json_serializable`, `build_runner`) produces code the
agent must take on faith; a typo in an annotation surfaces only on the
human's machine, burning the human's time on agent mistakes. Codegen also
adds a build step to CI and a second source of truth (`.g.dart` drift).

## Decision

1. **No `build_runner`, `freezed`, or `json_serializable` in v1.**
2. All models are hand-written immutable classes with:
   - `const` constructors, `final` fields;
   - manual `==`/`hashCode`/`toString`;
   - manual `toJson()`/`fromJson()` with strict type validation;
   - round-trip unit tests (the compiler-shaped hole that codegen normally
     plugs is plugged by tests instead).
3. Localization is a hand-written delegate (lib/l10n) — no `flutter gen-l10n`.
4. Riverpod providers are hand-written (no riverpod_generator).

## Consequences

**Positive:** every line is agent-verifiable by reading; `flutter pub get`
plus `flutter analyze` is the whole build; no generated-file drift; faster
CI; smaller diff noise.

**Negative:** model boilerplate (≈40 lines/class); manual equality code is
a bug surface; adding a field touches 4 places (ctor, ==, toJson,
fromJson) — enforced by round-trip + equality tests.

**Revisit:** if v2 exceeds ~50 models or introduces codegen-capable
tooling, re-evaluate — the ADR is about v1's build trust model, not a
forever-ban.
