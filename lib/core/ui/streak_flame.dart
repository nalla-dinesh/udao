// phase-01
// StreakFlame — day count + flame whose size/heat grows with the
// streak (5 → 30 days). Supports the "freeze available" snowflake.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import 'app_icons.dart';
import 'app_svg.dart';

class StreakFlame extends StatelessWidget {
  const StreakFlame({
    required this.days,
    this.freezeAvailable = false,
    this.unitLabel = 'din',
    super.key,
  });

  final int days;
  final bool freezeAvailable;

  /// Streak unit, e.g. "din" (l10n).
  final String unitLabel;

  /// 0.0 at 5 days → 1.0 at 30 days (clamped both ends).
  static double flameIntensity(int days) =>
      ((days - 5) / (30 - 5)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    final double intensity = flameIntensity(days);
    final double flameSize = 28 + intensity * 14;
    final Color flameColor = intensity >= 0.66
        ? sem.flame
        : intensity >= 0.33
            ? sem.gold
            : sem.lime;

    return Semantics(
      label: '$days $unitLabel streak',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              AppSvg(
                AppIcons.streakFlame,
                width: flameSize,
                height: flameSize,
                color: flameColor,
              ),
              if (freezeAvailable)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: sem.sky),
                    ),
                    child: PhosphorIcon(
                      PhosphorIconsBold.snowflake,
                      size: 12,
                      color: sem.sky,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: UdaoSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$days',
                style: text.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              Text(
                unitLabel.toUpperCase(),
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
