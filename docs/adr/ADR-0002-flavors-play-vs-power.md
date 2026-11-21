# ADR-0002 — Product flavors: `play` vs `power`

- **Status:** Accepted (Phase 00)
- **Date:** 2026-10-27

## Context

Google Play's SMS policy restricts `RECEIVE_SMS`/`READ_SMS` to a narrow
exception set (SMS-based money management, with declaration and review).
Bank-SMS capture meaningfully improves statement-grade coverage for
transactions that generate no notification. We want both: a frictionless
Play presence AND a no-compromise build for enthusiasts.

## Decision

One Gradle flavor dimension `dist` with two flavors:

| | `play` | `power` |
|---|---|---|
| Capture sources | notifications only | notifications + bank SMS |
| Extra permissions | none | `RECEIVE_SMS`, `READ_SMS` |
| Distribution | Google Play | GitHub releases / F-Droid |
| `INTERNET` | none | none |
| applicationId | `in.udao.app` | `in.udao.app` (same) |
| versionNameSuffix | `-play` | `-power` |

- Both flavors share ONE applicationId — power is the same app distributed
  outside Play (signatures differ anyway: Play App Signing vs local
  keystore, so cross-source upgrades were never possible).
- Flavor is exposed to Dart through the `udao/platform` MethodChannel
  (`appFlavor` in `getDeviceInfo`) — no compile-time Dart defines needed.
- SMS code ships in both flavors but is runtime-gated on flavor +
  permission (Phase 04); the `play` build never requests it.
- `src/debug`/`src/profile` overlays (dev-only INTERNET) apply to both.

## Consequences

**Positive:** Play review stays clean (notification-only capture, no
dangerous permissions); power users get full coverage; one codebase.

**Negative:** every QA cycle must test BOTH flavors; the device matrix
(Phase 09) doubles its flavor column; users confused about which build to
install need a clear README/website distinction.

**Mitigations:** CI builds a `play` debug APK as the smoke gate; Phase 09's
device matrix carries a flavor column; the GitHub release page leads with
"phone pe Play Store hai toh wahi le, SMS capture chahiye toh power".
