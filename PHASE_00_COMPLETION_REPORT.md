# PHASE 00 — COMPLETION REPORT

**Phase:** 00 — Foundation, Tooling & Project Skeleton
**Agent verdict:** COMPLETE (static verification only — no SDK was
installed or run, per the operating contract)
**Date:** 2026-10-27
**Target toolchain (user's machine):** Flutter 3.41.4 / Dart 3.11.1,
Android Studio, JDK 17

---

## 1. What was delivered

| Deliverable | Where | Status |
|---|---|---|
| Repo skeleton (exact T1 tree) | repo root | ✅ all dirs + `.gitkeep` in reserved (`core/theme`, `data`, `features`) |
| Strict analysis options | `analysis_options.yaml` | ✅ flutter_lints + 13 tightening rules; strict-casts/raw-types/inference as errors |
| Pubspec with pinned deps | `pubspec.yaml` | ✅ 13 runtime + 2 dev deps, all `# verify-latest` marked; zero network packages |
| 10 font TTFs vendored | `assets/fonts/` | ✅ copied from `~/udao_pdf/fonts/`, declared as Inter 400–800 / SpaceGrotesk 400–700 / Syne 700–800 |
| 8 original brand SVGs | `assets/icons/` | ✅ hand-drawn geometric marks, 24×24, 2px rounded strokes, `currentColor` tintable, XML-validated |
| `AppIcons` registry | `lib/core/ui/app_icons.dart` | ✅ all 8 paths cross-checked to files |
| Hand-authored Android layer | `android/` | ✅ Gradle KTS, 2 flavors, 5 manifests, MainActivity + `udao/platform` channel, ProGuard, res/ styles + adaptive icon |
| Core utilities | `lib/core/` | ✅ `Money`, `IstDates`, `Result<T>`, sealed `Failure`, `UdaoLogger` (ring + rotating JSONL sink) |
| Runnable Phase-00 app | `lib/main.dart`, `lib/app.dart` | ✅ go_router shell, Syne/SpaceGrotesk on screen, ink `#0B0C10` + flame `#FF5A3C` |
| l10n skeleton | `lib/l10n/` + `assets/l10n/` | ✅ manual delegate (no codegen), `hi` primary / `en` fallback, arb mirror in parity |
| Tests | `test/` | ✅ 4 files: money (28 test cases), date_utils (17), result (13), widget smoke (1) |
| CI workflow | `.github/workflows/ci.yml` | ✅ analyze → format → test → icon-ban grep → bootstrap audit → play debug APK |
| 5 ADRs | `docs/adr/` | ✅ 0001 no-backend, 0002 flavors, 0003 no-codegen, 0004 SQLCipher, 0005 fonts/icons |
| Tooling scripts | `tools/` | ✅ `bootstrap.sh` (no-Flutter validator, agent-tested), `local_verify.sh` (human gate) |
| Gradle wrapper | `android/gradle/wrapper/` + `gradlew(.bat)` | ✅ downloaded from the Gradle v8.12.0 tag (jar 44 KB) — `flutter create .` fallback NOT needed unless versions drift |
| LICENSE | `LICENSE` | ✅ full AGPL-3.0 text (from SPDX license-list) |
| Git | repo | ✅ `git init` + initial commit `feat: phase 00 foundation` |

## 2. Static self-verification performed (no SDK)

- `tools/bootstrap.sh` — **ALL CHECKS PASSED** after fixes: root files,
  10 fonts, 8 SVGs, INTERNET only in debug/profile overlays, SMS only in
  power, no `print(`, no banned icon classes in `lib/`.
- All 15 Android XML files parse (ElementTree), including the tricky
  XML-comment rule (no `--` inside comments — caught & fixed in
  `src/profile`).
- All 8 SVGs parse with `viewBox="0 0 24 24"`, `stroke="currentColor"`,
  `stroke-width="2"`.
- ARB hi/en key parity; every arb key has a getter in the manual
  delegate; every pubspec `asset:` font path exists on disk.
- Channel contract cross-checked both ways:
  `AppConstants.platformChannelName` (`udao/platform`) and
  `platformDeviceInfoMethod` (`getDeviceInfo`) match
  `MainActivity.UdaoChannel`'s constants exactly.
- Dart→Kotlin map shape verified: `appFlavor` (String),
  `manufacturer` (String), `brand` (String), `sdkInt` (Int) — the exact
  keys Phase 03/05 will consume.

## 3. Decisions & deviations from the phase prompt (documented, deliberate)

| # | Prompt said | Did instead | Why |
|---|---|---|---|
| 1 | Version baseline AGP 8.5.2 / Gradle 8.7 / Kotlin 2.0.20, compileSdk 34 | **AGP 8.9.1 / Gradle 8.12 / Kotlin 2.2.0**, `compileSdk`/`targetSdk` via `flutter.compileSdkVersion`/`flutter.targetSdkVersion` (→ 36 on Flutter 3.41) | User's actual SDK is Flutter 3.41.4 (Mar 2026), not 3.24; prompt allowed "human may bump locally". `flutter.*` constants make compileSdk drift-proof. minSdk 26 hardcoded as specified. |
| 2 | `lints`: `secure_pubspec`, `package_annotations` | Omitted both; added `package_prefixed_doc_comments`, `require_trailing_commas`, `sort_pub_dependencies`, `always_put_required_named_parameters_first` | The two named rules are not guaranteed-valid across lint-package versions; unknown-rule warnings would break the "zero analyzer issues by construction" objective. |
| 3 | Icon-ban grep `grep -rn "Icons\.\|CupertinoIcons\."` | `grep -rEn "\b(Icon\|CupertinoIcons)\."` with word boundaries | The prompt's pattern false-positives on `AppIcons.foo` (substring match). Word boundary fixes it; documented in ADR-0005. |
| 4 | `flutter_localizations` global delegates | Not added in Phase 00 | `flutter_localizations` pins its own `intl` version on Flutter 3.41 (likely 0.20+), which would collide with the prompt's `intl ^0.19.0` pin and fail `pub get`. Manual delegate only; Phase 01 revisits with a version survey. |
| 5 | Launcher icon "reference default mipmap" | Adaptive-icon vector (`drawable/launcher_foreground`) + `mipmap-anydpi-v26` + monochrome | minSdk 26 means every device resolves adaptive icons — no legacy PNGs needed, and no binary assets in git. Placeholder art; Phase 08 replaces. |
| 6 | — | Added `android:allowBackup="false"` + data-extraction rules | Encrypted DB without its Keystore key is unrestorable; cloud backup contradicts ADR-0001. Hardening within the manifest-authoring task. |

## 4. `TODO-VERIFY(local)` list (things only a real build can prove)

1. **`flutter pub get` resolves** the pinned set on Flutter 3.41.4 —
   highest-risk item is `intl ^0.19.0` + `device_info_plus ^10.1.2`
   co-resolution (both are 2024-era pins; they co-resolved fine then).
   If solver complains: bump the offending pin to the current major.
2. **`flutter analyze` = No issues** — strict lints (require_trailing_
   commas, prefer_final_locals, strict-inference) were hand-honored;
   a compiler pass is the real test.
3. **`flutter test`** — 56 test cases across 4 files (money 27,
   date_utils 17, result 11, widget smoke 1), all logic hand-executed
   during authoring but never run.
4. **Both flavors build & run** — `flutter run --flavor play` and
   `--flavor power`; expect dark ink screen, flame logo, "UDAO v0.1.0 —
   Phase 00" in Syne ExtraBold.
5. **Gradle wrapper works** — jar downloaded from the Gradle v8.12.0
   tag; if AGP 8.9.1 complains about Gradle version on your setup,
   either bump `distributionUrl` or run `flutter create .` once and
   let Flutter regenerate platform scaffolding.
6. **Adaptive icon + splash look right** — vector artwork is
   hand-coordinated; visual QA needs eyes.
7. **Channel smoke** — after `flutter run`, `udao/platform#getDeviceInfo`
   returns `{appFlavor: "play", manufacturer: …, brand: …, sdkInt: …}` —
   no Dart caller exists yet (Phase 03 adds it); verify via a temporary
   `debugPrint` or DevTools if curious.

## 5. Local verification script (run on your machine)

```bash
cd udao
flutter pub get
flutter analyze                  # expect: No issues found!
dart format --set-exit-if-changed lib test
flutter test                     # expect: All tests passed!
bash tools/bootstrap.sh          # structure + permission audit
flutter run --flavor play        # dark screen, flame logo, Syne text
flutter run --flavor power       # same, versionName suffix -power
```

(or just `bash tools/local_verify.sh`)

## 6. Handoff to Phase 01

Phase 01 (design system & theming) can assume:
- `Money`, `IstDates`, `Result`, `Failure`, `UdaoLogger`, `AppIcons`
  exist and are tested — build on them, don't duplicate.
- `UdaoApp` in `lib/app.dart` is the temporary shell to replace.
- Fonts are registered under families `Inter` / `SpaceGrotesk` / `Syne`
  (weights in pubspec) — reference by family name + weight only.
- `lib/core/theme/` is the reserved home for the token system
  (dark + light both required).
- The `phase00Title` l10n key + `_Phase00Screen` get deleted in Phase 01.

## 7. Errata — after the first local verification run (2026-10-27)

First `flutter test` on the human's machine (Windows, Flutter 3.41.4):
**43 passed / 4 failed.** All three real failures were **test-file bugs —
production `lib/` code untouched.** Fixed in
`fix: correct phase 00 test bugs found by first local run`:

1. **`result_test.dart:14`** — `Result.guard<int>(...)` is invalid Dart:
   type arguments must precede the constructor name
   (`Result<int>.guard(...)`). This compile error also crashed the
   compiler batch loading `date_utils_test.dart` (collateral, no bug
   there).
2. **`money_test.dart`** — crore expectation was miscomputed:
   `Money.fromRupees(10000000)` is **₹1 crore** (1 crore = 10⁷ rupees),
   not ₹100 crore. The production code was correct; the test now also
   covers a true ₹100 crore case (`fromRupees(1000000000)`).
3. **`app_smoke_test.dart`** — asserted `Scaffold.backgroundColor`,
   which is always `null` when the color comes from the theme. Now
   asserts `Theme.of(context).scaffoldBackgroundColor` instead.

**Round 2 (same day):** re-run gave 55 pass / 1 fail — one more
miscomputed crore expectation (`fromRupees(12345678)` is ₹1.23 crore:
1,23,45,678 = 1.2345678 crore; the test said ₹12.23). Fixed. After this,
EVERY numeric expectation in money_test was recomputed from first
principles (definitions, not memory) — no further arithmetic slips.

Lesson logged for later phases: agent-authored expectations need
hand-execution against a second reference (the crore slips would have
been caught by recomputing from the definition each time).

## 8. Errata — first `flutter run --flavor play` (Gradle, 2026-10-27)

`flutter test` passed; the first device build failed with two Gradle
issues, both fixed in `fix: gradle — engine repo wiring + NDK pin`:

1. **Engine artifacts unresolvable**
   (`io.flutter:flutter_embedding_debug:1.0.0-<engine-hash>` etc.).
   Root cause: settings.gradle.kts used
   `dependencyResolutionManagement { PREFER_SETTINGS }`, which silently
   IGNORES the project-level engine-artifact repositories added by the
   Flutter Gradle plugin. Fix: removed dependencyResolutionManagement
   entirely; repositories now live in root build.gradle.kts
   `allprojects` — exactly like the official template. (The phase
   prompt asked for dependencyResolutionManagement; template-fidelity
   wins over the prompt here — documented deviation.)
2. **NDK mismatch**: Flutter 3.41's `jni` plugin layer requires NDK
   28.2.13676358 (project had the Flutter default 27.0.12077973).
   Fix: explicit `ndkVersion = "28.2.13676358"` in app/build.gradle.kts.
   NDK is backward compatible; AGP auto-installs it with accepted
   licenses, else SDK Manager → SDK Tools.

Post-fix expectations: `flutter clean` then `flutter run --flavor play`;
first build downloads the NDK (~1 GB) — one-time cost.

## 9. Errata — Kotlin compile (2026-10-27, third run)

Build progressed to `:app:compilePlayDebugKotlin` (Gradle repo wiring +
NDK fix confirmed working) and failed with:

    MainActivity.kt:1:9 Syntax error: Package name must be a
    '.'-separated identifier list  (+ cascading BuildConfig errors)

Root cause: **`in` is a Kotlin hard keyword** — `package in.udao.app`
does not parse. Fix: backtick-escape the segment
(`package `in`.udao.app`); the compiled package name is unchanged
(namespace/R/BuildConfig/manifest unaffected). Convention documented in
MainActivity.kt itself and appended to PHASE-03/04/05 prompts so future
native files don't repeat it.

(The javac "source value 8 is obsolete" warnings come from a plugin's
internal toolchain and are harmless.)

## 10. Errata — APK location (2026-10-27, fourth run)

Kotlin now compiles clean (backtick fix confirmed) and Gradle builds
successfully — but `flutter run` failed with "Gradle build failed to
produce an .apk file … generated under D:\udao\build". Root cause: the
official template's root build.gradle.kts contains a build-directory
REDIRECT (android outputs → `<repo>/build/`) that this repo had
trimmed "for simplicity". The Flutter 3.41 tool looks for the APK at
`<repo>/build/app/outputs/flutter-apk/`. Fix: root build.gradle.kts is
now the verbatim template structure (allprojects repos + redirect +
evaluationDependsOn). Total template deviations remaining: zero.

Also worth noting: the first verified device is **M2003J15SC — a
Redmi Note 9** — literally the hostile-OEM class Phase 05 exists for.
