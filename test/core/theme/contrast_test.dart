// phase-01
// Live WCAG 2.1 contrast enforcement — the executable twin of
// docs/design/contrast-audit.md. If a token change drops any pair
// below 4.5:1, this file fails before review can miss it.
//
// Ratios are computed first-principles from the EXACT Color constants
// in UdaoColors (no hardcoded hex), against each pairing's worst-case
// background.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_colors.dart';

double _lum(Color c) {
  double lin(double x) =>
      x <= 0.04045 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double ratio(Color fg, Color bg) {
  final double lf = _lum(fg);
  final double lb = _lum(bg);
  final double hi = lf > lb ? lf : lb;
  final double lo = lf > lb ? lb : lf;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('dark theme: every text pairing clears 4.5:1 at worst-case bg',
      () {
    final List<(String, Color, Color, double)> pairs = <(String, Color, Color, double)>[
      // (name, fg, worst-case bg, minimum)
      ('onSurface', UdaoColors.inkOnSurface, UdaoColors.inkSurface, 4.5),
      ('onVariant', UdaoColors.inkOnSurfaceVariant, UdaoColors.inkSurface, 4.5),
      ('flame', UdaoColors.flame, UdaoColors.inkSurfaceHigh, 4.5),
      ('lime', UdaoColors.lime, UdaoColors.inkSurfaceHigh, 4.5),
      ('gold', UdaoColors.gold, UdaoColors.inkSurfaceHigh, 4.5),
      ('sky', UdaoColors.sky, UdaoColors.inkSurfaceHigh, 4.5),
      ('violet', UdaoColors.violet, UdaoColors.inkSurfaceHigh, 4.5),
      ('success', UdaoColors.success, UdaoColors.inkSurfaceHigh, 4.5),
      ('error', UdaoColors.errorBright, UdaoColors.inkSurfaceHigh, 4.5),
      ('onPrimary on flame', UdaoColors.ink, UdaoColors.flame, 4.5),
      ('ink on lime', UdaoColors.ink, UdaoColors.lime, 4.5),
      ('onError on error', const Color(0xFF2A0D0D), UdaoColors.errorBright, 4.5),
    ];

    for (final (String name, Color fg, Color bg, double min) in pairs) {
      final double r = ratio(fg, bg);
      expect(
        r,
        greaterThanOrEqualTo(min),
        reason:
            '$name $fg on $bg is $r — must be >= $min (dark theme)',
      );
    }
  });

  test('light theme: every text pairing clears 4.5:1 at worst-case bg',
      () {
    final List<(String, Color, Color, double)> pairs = <(String, Color, Color, double)>[
      ('onSurface', UdaoColors.lightScheme.onSurface, UdaoColors.paperBg, 4.5),
      ('onVariant', UdaoColors.paperOnSurfaceVariant, UdaoColors.paperBg, 4.5),
      ('flameDeep', UdaoColors.flameDeep, UdaoColors.paperBg, 4.5),
      ('limeDeep', UdaoColors.limeDeep, UdaoColors.paperBg, 4.5),
      ('goldDeep', UdaoColors.goldDeep, UdaoColors.paperBg, 4.5),
      ('skyDeep', UdaoColors.skyDeep, UdaoColors.paperBg, 4.5),
      ('violetDeep', UdaoColors.violetDeep, UdaoColors.paperBg, 4.5),
      ('successDeep', UdaoColors.successDeep, UdaoColors.paperBg, 4.5),
      ('errorDeep', UdaoColors.errorDeep, UdaoColors.paperBg, 4.5),
      ('white on flameDeep', UdaoColors.white, UdaoColors.flameDeep, 4.5),
      ('white on limeDeep', UdaoColors.white, UdaoColors.limeDeep, 4.5),
    ];

    for (final (String name, Color fg, Color bg, double min) in pairs) {
      final double r = ratio(fg, bg);
      expect(
        r,
        greaterThanOrEqualTo(min),
        reason:
            '$name $fg on $bg is $r — must be >= $min (light theme)',
      );
    }
  });

  test('flameVivid on paper is documented decorative-only (< 4.5)', () {
    // The reason light mode text uses flameDeep: the bright brand
    // flame cannot pass as text on paper.
    expect(ratio(UdaoColors.flame, UdaoColors.paperBg), lessThan(4.5));
  });
}
