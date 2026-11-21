// phase-01
// `UdaoSemantic` — per-mode semantic extras that don't fit Material's
// `ColorScheme`: brand hues, card borders, skeleton shimmer pair, the
// roast-card gradient and elevation shadows. Read it anywhere with
// `context.semantic`.
import 'package:flutter/material.dart';

import 'udao_colors.dart';

@immutable
class UdaoSemantic extends ThemeExtension<UdaoSemantic> {
  const UdaoSemantic({
    required this.flame,
    required this.flameVivid,
    required this.lime,
    required this.gold,
    required this.sky,
    required this.violet,
    required this.success,
    required this.cardBorder,
    required this.skeleton,
    required this.skeletonHighlight,
    required this.roastCardGradient,
    required this.verdictEvening,
    required this.jarFill,
    required this.raisedShadow,
  });

  /// Text-safe flame for this mode (dark: bright, light: deep).
  final Color flame;

  /// Always-bright flame — decorative use only (never text on paper).
  final Color flameVivid;
  final Color lime;
  final Color gold;
  final Color sky;
  final Color violet;
  final Color success;
  final Color cardBorder;
  final Color skeleton;
  final Color skeletonHighlight;

  /// Exactly two colors (top-left → bottom-right).
  final List<Color> roastCardGradient;
  final Color verdictEvening;
  final Color jarFill;
  final List<BoxShadow> raisedShadow;

  static const UdaoSemantic dark = UdaoSemantic(
    flame: UdaoColors.flame,
    flameVivid: UdaoColors.flame,
    lime: UdaoColors.lime,
    gold: UdaoColors.gold,
    sky: UdaoColors.sky,
    violet: UdaoColors.violet,
    success: UdaoColors.success,
    cardBorder: UdaoColors.inkOutline,
    skeleton: UdaoColors.inkSurfaceHigh,
    skeletonHighlight: Color(0xFF2C3247),
    roastCardGradient: <Color>[UdaoColors.inkSurfaceHigh, Color(0xFF33221C)],
    verdictEvening: UdaoColors.gold,
    jarFill: UdaoColors.lime,
    raisedShadow: <BoxShadow>[],
  );

  static const UdaoSemantic light = UdaoSemantic(
    flame: UdaoColors.flameDeep,
    flameVivid: UdaoColors.flame,
    lime: UdaoColors.limeDeep,
    gold: UdaoColors.goldDeep,
    sky: UdaoColors.skyDeep,
    violet: UdaoColors.violetDeep,
    success: UdaoColors.successDeep,
    cardBorder: UdaoColors.paperOutline,
    skeleton: UdaoColors.paperSurfaceHigh,
    skeletonHighlight: Color(0xFFDCD8CD),
    roastCardGradient: <Color>[UdaoColors.paperSurface, Color(0xFFFFEFE9)],
    verdictEvening: UdaoColors.goldDeep,
    jarFill: UdaoColors.limeDeep,
    raisedShadow: <BoxShadow>[
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    ],
  );

  @override
  UdaoSemantic copyWith({
    Color? flame,
    Color? flameVivid,
    Color? lime,
    Color? gold,
    Color? sky,
    Color? violet,
    Color? success,
    Color? cardBorder,
    Color? skeleton,
    Color? skeletonHighlight,
    List<Color>? roastCardGradient,
    Color? verdictEvening,
    Color? jarFill,
    List<BoxShadow>? raisedShadow,
  }) {
    return UdaoSemantic(
      flame: flame ?? this.flame,
      flameVivid: flameVivid ?? this.flameVivid,
      lime: lime ?? this.lime,
      gold: gold ?? this.gold,
      sky: sky ?? this.sky,
      violet: violet ?? this.violet,
      success: success ?? this.success,
      cardBorder: cardBorder ?? this.cardBorder,
      skeleton: skeleton ?? this.skeleton,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      roastCardGradient: roastCardGradient ?? this.roastCardGradient,
      verdictEvening: verdictEvening ?? this.verdictEvening,
      jarFill: jarFill ?? this.jarFill,
      raisedShadow: raisedShadow ?? this.raisedShadow,
    );
  }

  @override
  UdaoSemantic lerp(UdaoSemantic? other, double t) {
    if (other == null) {
      return this;
    }
    // Both gradients are exactly two colors by construction.
    final List<Color> a = roastCardGradient;
    final List<Color> b = other.roastCardGradient;
    return UdaoSemantic(
      flame: Color.lerp(flame, other.flame, t)!,
      flameVivid: Color.lerp(flameVivid, other.flameVivid, t)!,
      lime: Color.lerp(lime, other.lime, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      sky: Color.lerp(sky, other.sky, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      success: Color.lerp(success, other.success, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      skeleton: Color.lerp(skeleton, other.skeleton, t)!,
      skeletonHighlight: Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
      roastCardGradient: <Color>[
        Color.lerp(a[0], b[0], t)!,
        Color.lerp(a[1], b[1], t)!,
      ],
      verdictEvening: Color.lerp(verdictEvening, other.verdictEvening, t)!,
      jarFill: Color.lerp(jarFill, other.jarFill, t)!,
      raisedShadow: BoxShadow.lerpList(raisedShadow, other.raisedShadow, t)!,
    );
  }
}

/// `context.semantic` — the one-liner every component uses.
extension UdaoSemanticX on BuildContext {
  UdaoSemantic get semantic => Theme.of(this).extension<UdaoSemantic>()!;
}
