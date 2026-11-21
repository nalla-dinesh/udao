// phase-01
// UDAO color tokens — the ONLY file in lib/ allowed to contain raw
// color literals (CI/audit grep enforced; see PHASE_01 report).
//
// Contrast discipline (docs/design/contrast-audit.md, all values
// computed with the WCAG 2.1 formula, not eyeballed):
//  * DARK  : pastels (#C9F24B lime, #FFC94D gold …) on ink surfaces —
//            every text pair ≥ 4.5:1.
//  * LIGHT : the same hues DEEPENED for paper (#5F7A0A lime text …) —
//            every text pair ≥ 4.5:1 on both #FFFFFF and #F7F5F0.
//            Bright #FF5A3C flame measures only 2.84:1 on paper, so the
//            light-mode PRIMARY is deep roast-red #C93A12 (4.70:1) while
//            [UdaoSemantic.flameVivid] keeps the bright flame for
//            decorative (non-text) use.
import 'package:flutter/material.dart';

abstract final class UdaoColors {
  // ── Brand core ──────────────────────────────────────────────────────
  /// The bright flame. Dark-mode primary; decorative-only in light mode.
  static const Color flame = Color(0xFFFF5A3C);

  /// Deep roast-red. Light-mode primary (AA on paper).
  static const Color flameDeep = Color(0xFFC93A12);

  /// Near-black warm ink — on-flame text (dark buttons/stamps).
  static const Color ink = Color(0xFF1A0C07);

  static const Color lime = Color(0xFFC9F24B);
  static const Color limeDeep = Color(0xFF5F7A0A);
  static const Color gold = Color(0xFFFFC94D);
  static const Color goldDeep = Color(0xFF8A6A00);
  static const Color sky = Color(0xFF5AC8FA);
  static const Color skyDeep = Color(0xFF0A6DA3);
  static const Color violet = Color(0xFFA78BFA);
  static const Color violetDeep = Color(0xFF5B3FC4);
  static const Color success = Color(0xFF4ADE80);
  static const Color successDeep = Color(0xFF15803D);
  static const Color errorBright = Color(0xFFFF6B6B);
  static const Color errorDeep = Color(0xFFB3261E);

  // ── Dark surfaces ───────────────────────────────────────────────────
  static const Color inkBg = Color(0xFF0B0C10);
  static const Color inkSurface = Color(0xFF14161D);
  static const Color inkSurfaceHigh = Color(0xFF1E2230);
  static const Color inkOnSurface = Color(0xFFF2F4F8);
  static const Color inkOnSurfaceVariant = Color(0xFFA9B1C2);
  static const Color inkOutline = Color(0xFF313647);

  // ── Light surfaces ──────────────────────────────────────────────────
  static const Color paperBg = Color(0xFFF7F5F0);
  static const Color paperSurface = Color(0xFFFFFFFF);
  static const Color paperSurfaceHigh = Color(0xFFEDEAE2);
  static const Color paperOnSurfaceVariant = Color(0xFF5A6172);
  static const Color paperOutline = Color(0xFFD9D4C8);

  // ── Neutral helpers ─────────────────────────────────────────────────
  static const Color transparent = Color(0x00000000);
  static const Color white = Color(0xFFFFFFFF);

  // ── ColorSchemes (hand-authored — fromSeed is banned by ADR-0005) ──
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: flame,
    onPrimary: ink,
    secondary: lime,
    onSecondary: ink,
    tertiary: gold,
    onTertiary: ink,
    error: errorBright,
    onError: ink,
    surface: inkSurface,
    onSurface: inkOnSurface,
    surfaceContainerHighest: inkSurfaceHigh,
    onSurfaceVariant: inkOnSurfaceVariant,
    outline: inkOutline,
  );

  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: flameDeep,
    onPrimary: white,
    secondary: limeDeep,
    onSecondary: white,
    tertiary: goldDeep,
    onTertiary: white,
    error: errorDeep,
    onError: white,
    surface: paperSurface,
    onSurface: inkSurface,
    surfaceContainerHighest: paperSurfaceHigh,
    onSurfaceVariant: paperOnSurfaceVariant,
    outline: paperOutline,
  );
}
