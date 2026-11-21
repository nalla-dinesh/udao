# PHASE 01 — COMPLETION REPORT
## Design System, Dual Themes & Production UI Kit

**Repo state:** `main` @ post-Phase-00 (`399fa8b` → see `git log` for this phase's commit)
**Scope:** `udao-build-prompts/PHASE-01-design-system-theming.md` — tasks T1–T5, complete.
**Verification:** full static suite (balance, imports, bans, parity, coverage) **PASSED**. Runtime verification is the local step below (sandbox runs no Flutter toolchain, per build-agent constraints).

---

## T1 — Design tokens

| Layer | File | Contents |
|---|---|---|
| Color palette | `lib/core/theme/udao_colors.dart` | flame `#FF5A3C` + text-safe `flameDeep #C93A12`, lime/gold/sky/violet/success + `*Deep` twins, ink & paper ramps, transparent/white |
| Schemes | `lib/core/theme/udao_colors.dart` | `darkScheme` (primary flame, onPrimary ink) · `lightScheme` (primary flameDeep, onPrimary white) |
| Semantic extras | `lib/core/theme/udao_theme_extension.dart` | `UdaoSemantic` ThemeExtension — `flameVivid` (decor-only), `cardBorder`, skeleton pair, roast gradient, `verdictEvening`, `jarFill`, `raisedShadow` (light-only; dark uses borders). Read anywhere: `context.semantic` |
| Type | `lib/core/theme/udao_typography.dart` | 12-slot TextTheme: **Syne 800** display 48/40/28 · **SpaceGrotesk** headline 32/24/18 + title 18/16/14 · **Inter** body 15/13/12 (h 1.6) · SG label 12/10 caps (ls 1.2) |
| Space & shape | `lib/core/theme/udao_spacing.dart` | xs4·sm8·md12·lg16·xl24·xxl32 · radius sm8·md12·card14·lg16·pill999 |
| Motion | `lib/core/theme/udao_motion.dart` | fast150·base300·slow450·stagger60·shimmer1200 · spring `Cubic(0.2,0.9,0.25,1.15)` · `ease = easeOutCubic` |
| Theme assembly | `lib/core/theme/udao_theme.dart` | `UdaoTheme.dark()/light()` — scheme + extension + typography + page transitions; dark keeps borders, light gets the soft raised shadow |

Contrast: **every text pair ≥ 4.5:1 at its worst-case background in BOTH modes** (flame on roast-card surface 5.11 · limeDeep on paper 4.51 — tightest margins). Full tables + method + reproduce script: `docs/design/contrast-audit.md`. Enforced live by `test/core/theme/contrast_test.dart`, which reads the actual `UdaoColors` constants — a token regression fails CI before review can miss it.

## T2 — UI kit (18 components, `lib/core/ui/`)

`AppSvg` (tint + never-crash loader) · `UdaoHaptics` (kill-switch: tap/impact/celebrate) · `SkeletonBlock/Line` (shimmer via repaint-wired painter) · `SectionHeader` · `StatChip` · `UdaoCard` (5 accents) · **`UdaoButton`** (flameFilled/limeFilled/glass/danger × sm/md/lg, 48dp+, press-scale 0.97 spring, loading = pulsing skeleton — spinners banned repo-wide) · **`MoneyDisplay`** (300ms paise-exact count-up, `formatHi` desi short format, delta chip w/ caret + 16% tint bg, clamped text-scale 1.3) · **`RoastCard`** (gradient ink, severity stamp, 3-line Syne clamp, 48dp share stamp) · `ChindiBadge` (locked state + 2s just-unlocked glow) · `LevelBar` (pulsing current segment) · `StreakFlame` (intensity ramps 5→30d: lime→gold→flame, size 28→42, freeze snowflake) · `SpendBar` (animated fill, overflow→flame+warning glyph) · `UdaoEmptyState` · `UdaoBottomNav` (spring pill indicator, badges, 0 Material widgets) · `UdaoSnackBar` (top-anchored overlay stamp, PAATAA/DHYAAN/ROAST intents, auto-dismiss 3.5s) · `UdaoDialog` + `UdaoConfirmDialog` (bottom sheets, drag handle + flame rule) · `PermissionPrimingCard` · `VerdictBell` (notification mock).

Shared rules: haptics before every action · `Semantics` labels (Hinglish) on interactive/hero elements · `RepaintBoundary` on animated self-painters · doubles for display ratios only — money stays paise ints.

## T3 — App shell & routing

- `lib/app.dart` rewritten: `MaterialApp.router`, **dark+light** via `ThemeMode.system`, Hinglish localizations (hi primary, en fallback — unknown locales resolve en).
- `lib/core/router/udao_router.dart`: `StatefulShellRoute.indexedStack` ×5 branches (`/aaj /chat /khel /ledger /settings`), `goBranch(i, initialLocation: i==currentIndex)` on re-tap. Redirect reads `onboarding_done` via SharedPreferences; the **decision is the pure `udaoRedirect()`** (unit-tested). `SHOWCASE=true` dart-define reroutes `/aaj → /showcase`.
- Keys centralized in `lib/core/storage/local_prefs.dart`: `onboarding_done`, `user_name`, `personality`, `notification_intent`.

## T4 — Onboarding (5 steps)

Brand (120dp mark + tagline) → How it works (Capture/Roast/Khel pillars) → Notification priming (**VerdictBell live mock** + PermissionPrimingCard; intent recorded, real request = Phase 03 TODO) → Personality (Savage default w/ DEFAULT tag, Hype, Silent, Sensei) → Name (≤20, optional, trimmed) → finish persists everything, router flips to shell.

State: riverpod `Notifier` (`onboardingProvider`); pages animate via `PageController` — state mutations only, no setState. Progress stamps + back/next pinned outside the PageView.

## T5 — Showcase, localization, docs

- **ThemeShowcaseScreen** (debug or `SHOWCASE=true`): 10 numbered sections — colors grid, type ladder, buttons, cards, money, roast, stats, game, feedback (live snack/dialog/skeletons), nav+notification mocks — with an in-screen dark/light flip.
- **Goldens:** `test/golden/showcase_golden_test.dart` — 375×812 & 412×915, DPR 1.0, dark+light (4 baselines). **Auto-baseline comparator** (missing file → write+pass; existing → byte-exact, mismatch writes `.actual.png`). First local run creates `test/golden/goldens/` — commit it. Repeating animations are pumped to deterministic frames (never `pumpAndSettle`).
- **l10n:** hand-written delegate (`lib/l10n/app_localizations.dart`, ADR-0003: no codegen) — **64 keys**; `assets/l10n/app_{hi,en}.arb` are GENERATED from the delegate by script, so key parity is structural (verified by test + audit). Why both: the delegate is the runtime truth; the ARBs keep translation-tool compatibility.

## Tests — 30 files, 129 cases

- 49 component tests (every component ≥2: taps/callbacks, disabled/loading semantics, format exactness, overflow states, badge/level/streak/roast first-principles math).
- `contrast_test` (live WCAG, 23 pairs + the flameVivid <4.5 documentation assert) · `udao_theme_test` (scheme/extension/typography wiring).
- `udao_router_test` (pure redirect matrix) · `app_localizations_test` (voices, ARB parity, spot values, fallback) · `haptics_test` (kill-switch, frozen pref key).
- `onboarding_provider_test` (defaults, immutability, persistence incl. trim + empty-name skip).
- **Smoke:** fresh prefs → onboarding → 5 steps → shell + persisted flags; returning user → straight to shell. (Supersedes the Phase-00 smoke test, deleted with the Phase-00 screen it asserted.)
- Goldens ×4.

## Static verification (sandbox, all passed)

83 dart files: brace/paren balance · comment-stripped contamination scan · all relative + `package:udao` imports resolve · `unawaited`↔`dart:async` coherence · bans in `lib/` (raw `Colors.`, `withOpacity`, `TextStyle(`/`fontSize:` outside typography, spinners, `Icons.`/`CupertinoIcons`, `AppBar`, `ThemeData(`/`MaterialApp(` outside owners, Material SnackBar/dialog/nav, `withValues(opacity:)`) · ARB parity 64/64 · coverage matrix.

## Compile-risk gates closed during build

1. **phosphor_flutter 2.x API** — `PhosphorIcons.x` doesn't exist; all 29 references use style class `PhosphorIconsBold.*` (16 whitelisted glyphs).
2. **`Color.withValues`** takes `alpha:`, not `opacity:` — fixed in LevelBar pulse.
3. **`Money.fromRupees` is a non-const factory** — removed every `const` widget whose args called it (showcase + tests).
4. **`UdaoMotion` relocated** to its own file; imports corrected; unused imports pruned.
5. **CustomPainter repaint wiring** (`super(repaint: animation)`) — the shimmer actually sweeps.
6. **`unawaited_futures`** compliance at chindi glow, money count-up, dialog/push/show sites.
7. **Strict-lint hardening:** `prefer_const_declarations` traps removed (for-element groups in `Money._groupIndian` — output byte-identical, hand-checked vs the Phase-00 expectations; `List.empty(growable:true)` in the nav test).

## TODO-VERIFY(local) — run before review

```powershell
# In D:\udao (PowerShell, one command per line):
flutter pub get
dart format lib test          # Dart 3 tall style — first run rewrites; commit result
flutter analyze               # expect: No issues found!
flutter test                  # 129 cases; goldens self-baseline on first run
flutter run --flavor play --dart-define=SHOWCASE=true
```
(or just `powershell -ExecutionPolicy Bypass -File tools\local_verify.ps1`)

- Asset rendering in widget tests (`flutter test` loads real SVG/TTF assets — expected green; if a sandbox-unknown env quirk appears, it shows here first).
- Golden baselines are machine-stamped — regenerate intentionally by deleting under `test/golden/goldens/`.
- On-device: dark↔light system toggle, onboarding walk, SHOWCASE screen on a real display.

## Notes & decisions

- **flameVivid rule:** bright flame never styles text in light mode (2.84:1) — decorative marks only (logo, streak art, onboarding hero). Enforced socially via review + documented in the audit; `contrast_test` pins the reason.
- Removed `intl` from pubspec (`flutter_localizations` pins its own).
- Phase-00 `.gitkeep` in `lib/core/theme` retired (real files now).

**Phase 01 is code-complete.** Local green light on the six commands above closes it; Phase 02 (data layer) awaits your go-ahead.

---

## Errata — first local run (`flutter test`, Windows / Flutter 3.41.4)

First run: 65 passed, 23 load failures — all traced to 6 root causes, all fixed in the errata commit, static checker upgraded so this class can't recur:

| # | Error | Root cause | Fix |
|---|---|---|---|
| 1 | `udao_typography.dart:110 — No named parameter 'heightMultiplier'` | `TextStyle.apply()`'s params churn across SDK versions; my recall was wrong | `build()` now scales heights slot-wise via `copyWith` — no `apply()` dependency at all |
| 2 | `money_display.dart:47 — Money Function() can't be assigned to Money` | `Money.zero` is a **named const constructor** — bare reference is a tear-off, not a value | `Money.zero()` at 3 sites (money_display, spend_bar_test ×2) |
| 3 | `contrast_test — Member not found: 'paperOnSurface'` | No such constant — light onSurface lives in `lightScheme.onSurface` | Test now reads `UdaoColors.lightScheme.onSurface` |
| 4 | `'Widget'/'Text'/'Container' isn't a type` in 10 test files | `flutter_test` does NOT re-export widget types; the files used them without importing material | `import 'package:flutter/material.dart';` added to all 10 |
| 5 | `udao_button_test — getter 'enabled' isn't defined for Semantics` | The Semantics widget takes `enabled:` as a constructor param but exposes no public getter in 3.41.4 | Test asserts the disabled state via `AnimatedOpacity == 0.5` + Semantics presence |
| 6 | `AutoBaselineComparator — missing getTestUri` | `GoldenFileComparator` interface gained `getTestUri` | Implemented (version-suffix URI builder) |
| 7 | *(runtime, caught in self-review)* stat_chip test expected caret glyphs | Component renders `trendUp/trendDown` | Test expectations corrected |

**Checker v2 (new permanent guards):** widget-type usage without a providing import (lib AND test), `UdaoColors.<member>` existence vs the real class, constructor tear-off detection (`Money.zero` bare), `Semantics` getter introspection, and a lib↔test icon-expectation cross-check.

---

## Errata round 2 — second local run (same machine/toolchain)

Run 2 on `995459e`: **120 passed, 8 failed** — compile layer fully green; all 8 were runtime paint/lifecycle issues traced to 4 root causes:

| # | Error | Root cause | Fix |
|---|---|---|---|
| 8 | `A borderRadius can only be given on borders with uniform colors` (5 test failures: app_smoke, permission_priming ×2, udao_card, snack_bar) | `BoxDecoration` cannot pair `borderRadius` with a non-uniform `Border` (accent color on the left side only) — asserts during paint | Same stamp look rebuilt paint-safe: uniform outline border + 3px accent as a `ColoredBox` strip inside a `Clip.antiAlias` row (udao_card, how_it_works_step `_PillarCard`, udao_snack_bar) |
| 9 | `Looking up a deactivated widget's ancestor is unsafe` in `chindi_badge` (2 failures) | `late final _glow = AnimationController(vsync: this)` is lazy — for `justUnlocked: false` the ONLY access is `dispose()`, so the controller got created (→ TickerMode lookup) on a deactivated element | Controller now assigned eagerly in `initState`; `dispose` is always safe |
| 10 | `section_header_test — Found 0 widgets with text "SEE ALL"` | Test omitted `onAction`; the action pill (correctly) renders only when wired to a callback — a tappable-looking label with no `onTap` is dead UI | Test passes `onAction: _noop` (widget design unchanged) |
| 11 | snack_bar tap test — tap landed at `Offset(377.4, -4.5)` off-screen; notice never dismissed | The overlay entry and its entrance tween start on the same frame at t=0 (still −48px up); a single `pump(400ms)` renders the tween's first frame, not its end | Test pumps the insert frame (`pump()`), then the settle frame (`pump(400ms)`), then taps |

Residual risk noted for Phase 02+: none open — golden tests passed in run 2 (SVG assets load fine in the test harness).

---

## Errata round 3 — third local run

Run 3 on `e95bbb8`: **124 passed, 4 failed** (app_smoke + all 3 snack-bar tests) — a single regression introduced by the round-2 accent-strip fix itself:

| # | Error | Root cause | Fix |
|---|---|---|---|
| 12 | `BoxConstraints forces an infinite height` (RenderFlex/Row) | Round 2 built the accent strip as `Row(crossAxisAlignment: CrossAxisAlignment.stretch)` — stretch sets the cross size from `constraints.maxHeight`, which is **infinite** inside unbounded contexts (onboarding scroll view, snackbar overlay). It only worked in the bounded-height widget tests. | Strip rebuilt on a `Stack`: the content `Padding` sizes the stack, and `Positioned(left: 0, top: 0, bottom: 0, width: 3)` pins the accent bar to the left edge — layout-safe in bounded AND unbounded contexts (udao_card, how_it_works_step, udao_snack_bar) |

Lesson recorded for the checker: **`CrossAxisAlignment.stretch` is banned in this codebase** — any future strip/edge treatment uses `Stack` + `Positioned`.
