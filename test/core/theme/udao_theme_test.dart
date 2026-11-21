// phase-01
// Theme wiring: both modes carry the right scheme, the UdaoSemantic
// extension, scaffold colors and the 12-slot text theme.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_colors.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/core/theme/udao_theme_extension.dart';

void main() {
  test('dark theme wiring', () {
    final ThemeData t = UdaoTheme.dark();

    expect(t.colorScheme.primary, UdaoColors.flame);
    expect(t.colorScheme.onPrimary, UdaoColors.ink);
    expect(t.colorScheme.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, UdaoColors.inkBg);

    final UdaoSemantic? sem = t.extension<UdaoSemantic>();
    expect(sem, isNotNull);
    expect(sem!.flame, UdaoColors.flame);
    expect(sem.flameVivid, UdaoColors.flame);
    expect(sem.roastCardGradient, hasLength(2));
    expect(sem.raisedShadow, isEmpty, reason: 'dark mode uses borders');
  });

  test('light theme wiring', () {
    final ThemeData t = UdaoTheme.light();

    expect(t.colorScheme.primary, UdaoColors.flameDeep);
    expect(t.colorScheme.onPrimary, UdaoColors.white);
    expect(t.colorScheme.brightness, Brightness.light);
    expect(t.scaffoldBackgroundColor, UdaoColors.paperBg);

    final UdaoSemantic? sem = t.extension<UdaoSemantic>();
    expect(sem, isNotNull);
    expect(sem!.flame, UdaoColors.flameDeep);
    expect(sem.flameVivid, UdaoColors.flame);
    expect(
      sem.raisedShadow,
      isNotEmpty,
      reason: 'light mode uses the soft raised shadow',
    );
  });

  test('typography: 12 slots, brand fonts, tight metrics', () {
    final TextTheme t = UdaoTheme.dark().textTheme;

    expect(t.displayLarge!.fontSize, 48);
    expect(t.displayLarge!.fontFamily, 'Syne');
    expect(t.displayLarge!.fontWeight, FontWeight.w800);
    expect(t.displayMedium!.fontSize, 40);
    expect(t.displaySmall!.fontSize, 28);
    expect(t.headlineMedium!.fontFamily, 'SpaceGrotesk');
    expect(t.headlineMedium!.fontWeight, FontWeight.w700);
    expect(t.titleLarge!.fontFamily, 'SpaceGrotesk');
    expect(t.titleLarge!.fontWeight, FontWeight.w500);
    expect(t.bodyMedium!.fontFamily, 'Inter');
    expect(t.bodyMedium!.height, 1.6);
    expect(t.labelLarge!.letterSpacing, 1.2);
    expect(t.labelSmall!.fontSize, 10);
  });
}
