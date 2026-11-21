# ADR-0001 — No Firebase, no backend, no INTERNET permission (play flavor)

- **Status:** Accepted (Phase 00)
- **Date:** 2026-10-27
- **Deciders:** Product owner + build agent

## Context

UDAO's core promise to an 18–28 Indian audience is **"sab kuch on-device"**:
their money data — every transaction, roast, and private confession — never
leaves the phone. India's DPDP Act 2023 makes data minimization a legal
posture, not just a marketing line; and the target segment is uniquely
hostile to apps that feel like data harvests. Competitors (Cleo et al.)
route conversations and transactions through cloud LLMs and analytics SDKs.

## Decision

1. **No Firebase** (no Crashlytics, Analytics, Remote Config, FCM, Auth).
2. **No backend of any kind.** No http/dio/network packages in pubspec.
3. **The `play` flavor's manifest declares no `INTERNET` permission** —
   network access is impossible at the OS level, making the privacy claim
   verifiable by anyone who decompiles the APK.
4. Crash reporting is local (`UdaoLogger` ring buffer + JSONL sink) with
   opt-in export through the OS share sheet — the user physically hands
   over their own logs.
5. UDAO Pro billing uses Play Billing; the purchase flow is mediated by
   the Play Store app, not by UDAO's own network calls.

`INTERNET` appears only in `src/debug` and `src/profile` overlays for the
Dart VM service (hot reload) and is never merged into release builds.

## Consequences

**Positive:** strongest possible privacy story; zero server costs; zero
data-breach surface; offline-first by construction; DPDP compliance is
trivial to argue.

**Negative:** no remote kill-switch or feature flags (bad news ships until
the next release); no server-side personalization; crash triage depends on
users exporting diagnostics; telemetry is self-reported surveys instead of
dashboards.

**Mitigations:** staged Play rollouts as the remote kill-switch; the
diagnostics bundle (Phase 08) makes crash export one tap; the beta program
(Phase 09) substitutes for telemetry.
