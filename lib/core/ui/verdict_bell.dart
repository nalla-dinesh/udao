// phase-01
// VerdictBell — an Android-notification preview MOCK used in
// onboarding demos and the settings test-roast. Presentational only;
// real notifications arrive in Phase 03.
import 'package:flutter/material.dart';

import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import 'app_icons.dart';
import 'app_svg.dart';

class VerdictBell extends StatelessWidget {
  const VerdictBell({
    required this.appName,
    required this.title,
    required this.body,
    required this.timeLabel,
    super.key,
  });

  final String appName;
  final String title;
  final String body;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Semantics(
      label: '$appName notification: $title. $body',
      child: Container(
        padding: const EdgeInsets.all(UdaoSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(UdaoRadius.card),
          border: Border.all(color: sem.cardBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppSvg(
              AppIcons.verdictBell,
              width: 28,
              height: 28,
              color: sem.verdictEvening,
            ),
            const SizedBox(width: UdaoSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        appName.toUpperCase(),
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        timeLabel.toUpperCase(),
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: UdaoSpacing.xs),
                  Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: UdaoSpacing.xs),
                  Text(
                    body,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
