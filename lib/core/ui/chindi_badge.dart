// phase-01
// ChindiBadge — circular level badge. Locked state greys out with a
// lock; `justUnlocked` fires a 2s lime glow ring that fades away.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/udao_theme_extension.dart';
import 'haptics.dart';

class ChindiBadge extends StatefulWidget {
  const ChindiBadge({
    required this.level,
    this.unlocked = true,
    this.justUnlocked = false,
    this.size = 64,
    super.key,
  });

  final int level;
  final bool unlocked;
  final bool justUnlocked;
  final double size;

  @override
  State<ChindiBadge> createState() => _ChindiBadgeState();
}

class _ChindiBadgeState extends State<ChindiBadge>
    with SingleTickerProviderStateMixin {
  /// Created eagerly in [initState] — a `late final` field initializer
  /// would otherwise run inside [dispose] for never-unlocked badges and
  /// look up TickerMode on a deactivated element.
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.justUnlocked) {
      UdaoHaptics.celebrate();
      unawaited(_glow.forward());
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    final Widget circle = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.unlocked
            ? scheme.surface
            : scheme.surfaceContainerHighest,
        border: Border.all(
          color: widget.unlocked ? sem.flame : sem.cardBorder,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: widget.unlocked
          ? Text(
              '${widget.level}',
              style: text.displaySmall?.copyWith(color: sem.flame),
            )
          : PhosphorIcon(
              PhosphorIconsBold.lock,
              size: widget.size * 0.35,
              color: scheme.onSurfaceVariant,
            ),
    );

    return RepaintBoundary(
      child: Semantics(
        label: widget.unlocked
            ? 'level ${widget.level} badge'
            : 'level ${widget.level} locked',
        child: widget.justUnlocked
            ? AnimatedBuilder(
                animation: _glow,
                builder: (BuildContext context, Widget? child) {
                  final double t = _glow.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Transform.scale(
                        scale: 1.0 + 0.5 * t,
                        child: Opacity(
                          opacity: 1.0 - t,
                          child: Container(
                            width: widget.size,
                            height: widget.size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: sem.lime, width: 2),
                            ),
                          ),
                        ),
                      ),
                      child!,
                    ],
                  );
                },
                child: circle,
              )
            : circle,
      ),
    );
  }
}
