// phase-01
// `UdaoTheme.dark()` / `UdaoTheme.light()` — the two complete app
// themes. Assembles ColorScheme + UdaoSemantic + typography + shape +
// motion into `ThemeData`. Nothing in lib/ may construct a ThemeData
// with Material defaults.
import 'package:flutter/material.dart';

import 'udao_colors.dart';
import 'udao_spacing.dart';
import 'udao_theme_extension.dart';
import 'udao_typography.dart';

abstract final class UdaoTheme {
  static ThemeData dark() => _base(
        scheme: UdaoColors.darkScheme,
        semantic: UdaoSemantic.dark,
        scaffoldBg: UdaoColors.inkBg,
      );

  static ThemeData light() => _base(
        scheme: UdaoColors.lightScheme,
        semantic: UdaoSemantic.light,
        scaffoldBg: UdaoColors.paperBg,
      );

  static ThemeData _base({
    required ColorScheme scheme,
    required UdaoSemantic semantic,
    required Color scaffoldBg,
  }) {
    final TextTheme textTheme = UdaoTypography.build();
    return ThemeData(
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      extensions: <ThemeExtension<Object?>>[semantic],
      textTheme: textTheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: UdaoPageTransitionBuilder(),
          TargetPlatform.iOS: UdaoPageTransitionBuilder(),
        },
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: UdaoColors.transparent,
        indicatorColor: UdaoColors.transparent,
        elevation: 0,
      ),
      // Phase-07 UI pass — fintech-standard pill CTAs and soft cards
      // (research: pill buttons convert better; ≥1rem card radius).
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(
            horizontal: UdaoSpacing.xl,
            vertical: UdaoSpacing.md,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: scheme.primary),
        ),
      ),
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<StadiumBorder>(StadiumBorder()),
        ),
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UdaoRadius.lg),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UdaoRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        counterStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: UdaoSpacing.lg,
          vertical: UdaoSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UdaoRadius.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UdaoRadius.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(UdaoRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }
}

/// Slide + fade page transition (300ms, ease-out; reverse eases in).
class UdaoPageTransitionBuilder extends PageTransitionsBuilder {
  const UdaoPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.04, 0),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }
}
