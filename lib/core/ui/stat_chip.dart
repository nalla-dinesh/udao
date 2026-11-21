// phase-01
// Compact label + Syne/SG value chip with optional trend glyph.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';

class StatChip extends StatelessWidget {
  const StatChip({
    required this.label,
    required this.value,
    this.trendUp,
    super.key,
  });

  final String label;
  final String value;

  /// `null` — no trend glyph; `true` — up (success); `false` — down
  /// (flame, because in UDAO spending more down-trends your dignity).
  final bool? trendUp;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UdaoSpacing.lg,
        vertical: UdaoSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(UdaoRadius.card),
        border: Border.all(color: sem.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label.toUpperCase(),
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: UdaoSpacing.xs),
              Text(
                value,
                style: text.headlineSmall?.copyWith(color: scheme.onSurface),
              ),
            ],
          ),
          if (trendUp != null) ...<Widget>[
            const SizedBox(width: UdaoSpacing.md),
            PhosphorIcon(
              trendUp! ? PhosphorIconsBold.trendUp : PhosphorIconsBold.trendDown,
              size: 20,
              color: trendUp! ? sem.success : sem.flame,
            ),
          ],
        ],
      ),
    );
  }
}
