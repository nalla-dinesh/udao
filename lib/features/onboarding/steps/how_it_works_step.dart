// phase-01
// Step 2 — the three pillars: Silent Capture, Roast Engine, Khel.
import 'package:flutter/material.dart';

import '../../../core/theme/udao_spacing.dart';
import '../../../core/theme/udao_theme_extension.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/app_svg.dart';
import '../../../l10n/app_localizations.dart';

class HowItWorksStep extends StatelessWidget {
  const HowItWorksStep({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(UdaoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.obHowTitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          const SizedBox(height: UdaoSpacing.xl),
          _PillarCard(
            svgAsset: AppIcons.verdictBell,
            color: context.semantic.sky,
            title: l10n.obHowCaptureTitle,
            body: l10n.obHowCaptureBody,
          ),
          const SizedBox(height: UdaoSpacing.md),
          _PillarCard(
            svgAsset: AppIcons.roastFlame,
            color: context.semantic.flame,
            title: l10n.obHowRoastTitle,
            body: l10n.obHowRoastBody,
          ),
          const SizedBox(height: UdaoSpacing.md),
          _PillarCard(
            svgAsset: AppIcons.ladder,
            color: context.semantic.lime,
            title: l10n.obHowKhelTitle,
            body: l10n.obHowKhelBody,
          ),
        ],
      ),
    );
  }
}

class _PillarCard extends StatelessWidget {
  const _PillarCard({
    required this.svgAsset,
    required this.color,
    required this.title,
    required this.body,
  });

  final String svgAsset;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    // Accent edge as a positioned strip — a rounded BoxDecoration cannot
    // carry a non-uniform Border, and Row+stretch would force infinite
    // height inside this unbounded scroll view. The Stack sizes to the
    // content; the strip pins itself to the left edge.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(UdaoRadius.card),
        border: Border.fromBorderSide(BorderSide(color: sem.cardBorder)),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: color),
          ),
          Padding(
            padding: const EdgeInsets.all(UdaoSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppSvg(svgAsset, width: 36, height: 36, color: color),
                const SizedBox(width: UdaoSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: text.titleMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: UdaoSpacing.xs),
                      Text(
                        body,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
