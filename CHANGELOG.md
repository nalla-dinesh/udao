# Changelog

All notable changes to UDAO are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### 0.1.0 — Phase 00: Foundation, tooling & project skeleton

### Added

- Flutter repo skeleton with strict analysis options (strict-casts /
  strict-raw-types / strict-inference as errors, tightened lint set).
- Hand-authored Android platform layer: Gradle KTS, `play` / `power`
  flavors, manifest split (`main` / `play` / `power` / `debug` / `profile`),
  `MainActivity` with the `udao/platform` MethodChannel
  (`getDeviceInfo` → flavor / manufacturer / brand / SDK int).
- **No `INTERNET` permission in `main` / `play` / `power` manifests** —
  it exists only in the dev-only `debug` / `profile` overlays for the
  Dart VM service (never in release builds).
- R8 (minify + shrink resources) with UDAO ProGuard keep rules.
- Adaptive launcher icon (vector flame + white U) — placeholder art,
  replaced by the real brand pass in Phase 08.
- Brand fonts vendored: Syne (display), Space Grotesk (numerals),
  Inter (body) — 10 static TTFs, all OFL.
- 8 original brand SVG marks in `assets/icons/` exposed via `AppIcons`.
- Core utilities: `Money` (paise-int — doubles banned in monetary code),
  `IstDates` (IST wall-clock convention, Monday weeks, salary windows),
  `Result<T>` sealed type with `guard`, sealed `Failure` hierarchy,
  `UdaoLogger` (500-entry ring buffer + rotating JSONL file sink).
- Manual Hinglish-first localizations (`hi` primary, `en` fallback).
- CI workflow: analyze / format / test / icon-ban grep / debug APK build.
- 5 ADRs, `tools/bootstrap.sh` structure validator,
  `tools/local_verify.sh` local gate, `AGENT_LOG.md` phase tracker.

[Unreleased]: https://github.com/udao/udao/compare/v0.0.0...HEAD
