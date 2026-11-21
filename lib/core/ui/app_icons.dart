// Registry of UDAO's original brand SVG marks (assets/icons/).
//
// Render with `flutter_svg` and ALWAYS pass a color filter — the SVGs
// use `currentColor` so a single artwork can be tinted per theme:
//
// ```dart
// SvgPicture.asset(
//   AppIcons.roastFlame,
//   colorFilter: ColorFilter.mode(context.colors.flame, BlendMode.srcIn),
// )
// ```
//
// Generic system glyphs (arrows, close, settings, …) come from
// `phosphor_flutter`. Material `Icons` / `CupertinoIcons` classes are
// BANNED in lib/ — CI enforces it (.github/workflows/ci.yml).
abstract final class AppIcons {
  /// The mark: a bold U with a flame rising out of it.
  static const String logoMark = 'assets/icons/logo-mark.svg';

  /// Full flame — roast severity, burn marks.
  static const String roastFlame = 'assets/icons/roast-flame.svg';

  /// Shield + coin — the Chindi (stingy) badge.
  static const String chindiBadge = 'assets/icons/chindi-badge.svg';

  /// Flame with speed lines — streak momentum.
  static const String streakFlame = 'assets/icons/streak-flame.svg';

  /// Savings jar with a coin inside.
  static const String jar = 'assets/icons/jar.svg';

  /// The Chindi Ladder — rank rungs.
  static const String ladder = 'assets/icons/ladder.svg';

  /// Sword through a subscription card — the Slayer.
  static const String subscriptionSlayer =
      'assets/icons/subscription-slayer.svg';

  /// Bell — the evening verdict call.
  static const String verdictBell = 'assets/icons/verdict-bell.svg';
}
