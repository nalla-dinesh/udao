// phase-01
// UdaoEmptyState — original SVG illustration + Hinglish line +
// optional action. Screens are never blank.
import 'package:flutter/material.dart';

import '../theme/udao_spacing.dart';
import 'app_svg.dart';
import 'udao_button.dart';

class UdaoEmptyState extends StatelessWidget {
  const UdaoEmptyState({
    required this.illustration,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String illustration;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UdaoSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppSvg(
              illustration,
              width: 96,
              height: 96,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: UdaoSpacing.xl),
            Text(
              title,
              style: text.headlineSmall?.copyWith(color: scheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: UdaoSpacing.sm),
            Text(
              body,
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: UdaoSpacing.xl),
              UdaoButton(
                label: actionLabel!,
                variant: UdaoButtonVariant.glass,
                onTap: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
