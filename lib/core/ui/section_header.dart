// phase-01
// Section header — numbered editorial style ("01 · Aaj") with an
// optional trailing action pill (48dp touch target).
import 'package:flutter/material.dart';

import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import 'haptics.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.label,
    this.number,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String label;

  /// Editorial index, e.g. `01`.
  final String? number;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Padding(
      padding: const EdgeInsets.only(bottom: UdaoSpacing.md),
      child: Row(
        children: <Widget>[
          if (number != null) ...<Widget>[
            Text(
              number!,
              style: text.displaySmall?.copyWith(color: sem.flame),
            ),
            const SizedBox(width: UdaoSpacing.sm),
            Text(
              '·',
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: UdaoSpacing.sm),
          ],
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: text.labelLarge?.copyWith(color: scheme.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                UdaoHaptics.tap();
                onAction?.call();
              },
              child: SizedBox(
                height: 48,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: UdaoSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(UdaoRadius.pill),
                    border: Border.all(color: sem.flame),
                  ),
                  child: Text(
                    actionLabel!.toUpperCase(),
                    style: text.labelLarge?.copyWith(color: sem.flame),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
