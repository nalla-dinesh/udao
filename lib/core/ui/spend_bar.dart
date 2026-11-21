// phase-01
// SpendBar — category budget bar with animated fill. Overflow turns
// the bar flame-red (with a warning glyph); safe stays lime.
//
// The fill ratio is a double for DISPLAY only; amounts stay paise
// ints end to end.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/udao_motion.dart';
import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import '../utils/money.dart';

class SpendBar extends StatelessWidget {
  const SpendBar({
    required this.label,
    required this.spent,
    required this.budget,
    super.key,
  });

  final String label;
  final Money spent;
  final Money budget;

  /// 0.0–1.0 fill fraction. Zero budget with zero spend → 0.0;
  /// zero budget with any spend → 1.0 (treats it as blown).
  static double fillRatio(Money spent, Money budget) {
    if (budget.isZero) {
      return spent.isZero ? 0.0 : 1.0;
    }
    return (spent.paise / budget.paise).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    final bool overflow = spent > budget;
    final double ratio = fillRatio(spent, budget);
    final Color fillColor = overflow ? sem.flame : sem.lime;

    return Semantics(
      label: '$label ${spent.formatPlain()} of ${budget.formatPlain()}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (overflow) ...<Widget>[
                PhosphorIcon(
                  PhosphorIconsBold.warning,
                  size: 14,
                  color: sem.flame,
                ),
                const SizedBox(width: UdaoSpacing.xs),
              ],
              Text(
                '${spent.formatHi()} / ${budget.formatHi()}',
                style: text.labelSmall?.copyWith(
                  color: overflow ? sem.flame : scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: UdaoSpacing.xs),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: ratio),
            duration: UdaoMotion.base,
            curve: UdaoMotion.ease,
            builder: (BuildContext context, double t, Widget? child) {
              return Container(
                height: 10,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: sem.skeleton,
                  borderRadius: BorderRadius.circular(UdaoRadius.pill),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: t,
                  child: Container(color: fillColor),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
