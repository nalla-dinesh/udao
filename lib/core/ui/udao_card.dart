// phase-01
// UDAO card — surface + border + mode elevation + optional accent edge.
import 'package:flutter/material.dart';

import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import 'haptics.dart';

enum UdaoCardAccent { none, flame, lime, gold, sky }

class UdaoCard extends StatelessWidget {
  const UdaoCard({
    required this.child,
    this.accent = UdaoCardAccent.none,
    this.padding = const EdgeInsets.all(UdaoSpacing.lg),
    this.margin,
    this.onTap,
    super.key,
  });

  final Widget child;
  final UdaoCardAccent accent;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    final Color? accentColor = switch (accent) {
      UdaoCardAccent.none => null,
      UdaoCardAccent.flame => sem.flame,
      UdaoCardAccent.lime => sem.lime,
      UdaoCardAccent.gold => sem.gold,
      UdaoCardAccent.sky => sem.sky,
    };

    // A rounded BoxDecoration cannot carry a non-uniform Border (accent on
    // one side only), so the accent edge is a positioned strip inside the
    // clipped card. A Stack (NOT Row+stretch — stretch forces infinite
    // height in unbounded contexts like scroll views) sizes to the content
    // and the strip stretches between top:0 and bottom:0.
    final Widget body = accentColor == null
        ? Padding(padding: padding, child: child)
        : Stack(
            children: <Widget>[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: accentColor),
              ),
              Padding(padding: padding, child: child),
            ],
          );

    final Widget card = Container(
      margin: margin,
      clipBehavior: accentColor == null ? Clip.none : Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(UdaoRadius.card),
        border: Border.fromBorderSide(BorderSide(color: sem.cardBorder)),
        boxShadow: sem.raisedShadow,
      ),
      child: body,
    );

    if (onTap == null) {
      return card;
    }
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          UdaoHaptics.tap();
          onTap?.call();
        },
        child: card,
      ),
    );
  }
}
