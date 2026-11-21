// phase-01
// UDAO typography — Syne (display), Space Grotesk (headings/numerals),
// Inter (body). Every text style in the app comes from here; raw
// `TextStyle(` literals outside this file are banned (audit grep).
//
// Hinglish body copy gets `height: 1.6` — Devanagari-mixed lines need
// the extra leading to stop descenders from colliding.
import 'package:flutter/material.dart';

abstract final class UdaoTypography {
  static const String syne = 'Syne';
  static const String spaceGrotesk = 'SpaceGrotesk';
  static const String inter = 'Inter';

  /// The complete 12-slot map — no gaps, so any `Theme.of(context)
  /// .textTheme.X` lookup resolves to a branded style.
  static const TextTheme base = TextTheme(
    displayLarge: TextStyle(
      fontFamily: syne,
      fontWeight: FontWeight.w800,
      fontSize: 48,
      height: 1.05,
    ),
    displayMedium: TextStyle(
      fontFamily: syne,
      fontWeight: FontWeight.w800,
      fontSize: 40,
      height: 1.05,
    ),
    displaySmall: TextStyle(
      fontFamily: syne,
      fontWeight: FontWeight.w800,
      fontSize: 28,
      height: 1.1,
    ),
    headlineLarge: TextStyle(
      fontFamily: spaceGrotesk,
      fontWeight: FontWeight.w700,
      fontSize: 32,
      height: 1.15,
    ),
    headlineMedium: TextStyle(
      fontFamily: spaceGrotesk,
      fontWeight: FontWeight.w700,
      fontSize: 24,
      height: 1.2,
    ),
    headlineSmall: TextStyle(
      fontFamily: spaceGrotesk,
      fontWeight: FontWeight.w700,
      fontSize: 18,
      height: 1.25,
    ),
    titleLarge: TextStyle(
      fontFamily: spaceGrotesk,
      fontWeight: FontWeight.w500,
      fontSize: 18,
      height: 1.3,
    ),
    titleMedium: TextStyle(
      fontFamily: spaceGrotesk,
      fontWeight: FontWeight.w500,
      fontSize: 16,
      height: 1.35,
    ),
    titleSmall: TextStyle(
      fontFamily: spaceGrotesk,
      fontWeight: FontWeight.w500,
      fontSize: 14,
      height: 1.35,
    ),
    bodyLarge: TextStyle(
      fontFamily: inter,
      fontWeight: FontWeight.w400,
      fontSize: 15,
      height: 1.6,
    ),
    bodyMedium: TextStyle(
      fontFamily: inter,
      fontWeight: FontWeight.w500,
      fontSize: 13,
      height: 1.6,
    ),
    bodySmall: TextStyle(
      fontFamily: inter,
      fontWeight: FontWeight.w400,
      fontSize: 12,
      height: 1.5,
    ),
    labelLarge: TextStyle(
      fontFamily: spaceGrotesk,
      fontWeight: FontWeight.w700,
      fontSize: 12,
      letterSpacing: 1.2,
    ),
    labelSmall: TextStyle(
      fontFamily: spaceGrotesk,
      fontWeight: FontWeight.w700,
      fontSize: 10,
      letterSpacing: 1.2,
    ),
  );

  /// Builds the app text theme. [heightMultiplier] scales line heights
  /// for accessibility settings. Slot-wise `copyWith` on purpose —
  /// `TextTheme.apply`'s parameter names churn across SDK versions.
  static TextTheme build({double heightMultiplier = 1.0}) {
    if (heightMultiplier == 1.0) {
      return base;
    }
    TextStyle scale(TextStyle style) {
      final double? height = style.height;
      return height == null
          ? style
          : style.copyWith(height: height * heightMultiplier);
    }
    return base.copyWith(
      displayLarge: scale(base.displayLarge!),
      displayMedium: scale(base.displayMedium!),
      displaySmall: scale(base.displaySmall!),
      headlineLarge: scale(base.headlineLarge!),
      headlineMedium: scale(base.headlineMedium!),
      headlineSmall: scale(base.headlineSmall!),
      titleLarge: scale(base.titleLarge!),
      titleMedium: scale(base.titleMedium!),
      titleSmall: scale(base.titleSmall!),
      bodyLarge: scale(base.bodyLarge!),
      bodyMedium: scale(base.bodyMedium!),
      bodySmall: scale(base.bodySmall!),
      labelLarge: scale(base.labelLarge!),
      labelSmall: scale(base.labelSmall!),
    );
  }
}
