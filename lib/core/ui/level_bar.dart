// phase-01
// LevelBar — the Chindi Ladder progress strip. Completed segments
// lime, current segment flame (pulsing), upcoming segments skeleton.
import 'package:flutter/material.dart';

import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';

class LevelBar extends StatefulWidget {
  const LevelBar({
    required this.currentIndex,
    this.segmentCount = 6,
    this.label,
    super.key,
  });

  /// 0-based index of the segment the user is currently on.
  final int currentIndex;
  final int segmentCount;
  final String? label;

  @override
  State<LevelBar> createState() => _LevelBarState();
}

class _LevelBarState extends State<LevelBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return RepaintBoundary(
      child: Semantics(
        label: widget.label,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedBuilder(
              animation: _pulse,
              builder: (BuildContext context, Widget? child) {
                final double t = _pulse.value;
                return Row(
                  children: <Widget>[
                    for (int i = 0; i < widget.segmentCount; i++) ...<Widget>[
                      if (i > 0) const SizedBox(width: UdaoSpacing.xs),
                      Expanded(
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              UdaoRadius.pill,
                            ),
                            color: i < widget.currentIndex
                                ? sem.lime
                                : i == widget.currentIndex
                                    ? sem.flame.withValues(
                                        alpha: 0.55 + 0.45 * t,
                                      )
                                    : sem.skeleton,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            if (widget.label != null) ...<Widget>[
              const SizedBox(height: UdaoSpacing.xs),
              Text(
                widget.label!,
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
