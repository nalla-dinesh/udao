// phase-01
// PermissionPrimingCard — icon + why-this-permission Hinglish copy +
// CTA. Used by onboarding, settings and (Phase 05) health flows.
// The actual permission requests land in Phases 03/04.
import 'package:flutter/material.dart';

import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import 'app_icons.dart';
import 'app_svg.dart';
import 'udao_button.dart';
import 'udao_card.dart';

class PermissionPrimingCard extends StatelessWidget {
  const PermissionPrimingCard({
    required this.title,
    required this.body,
    required this.ctaLabel,
    this.onCta,
    this.secondaryLabel,
    this.onSecondary,
    this.iconAsset,
    super.key,
  });

  final String title;
  final String body;
  final String ctaLabel;
  final VoidCallback? onCta;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Defaults to the verdict bell mark.
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return UdaoCard(
      accent: UdaoCardAccent.sky,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppSvg(
                iconAsset ?? AppIcons.verdictBell,
                width: 40,
                height: 40,
                color: sem.sky,
              ),
              const SizedBox(width: UdaoSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: text.headlineSmall?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: UdaoSpacing.sm),
                    Text(
                      body,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: UdaoSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: UdaoButton(label: ctaLabel, onTap: onCta),
          ),
          if (secondaryLabel != null && onSecondary != null) ...<Widget>[
            const SizedBox(height: UdaoSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: UdaoButton(
                label: secondaryLabel!,
                variant: UdaoButtonVariant.glass,
                onTap: onSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
