// phase-01
// Step 1 — brand mark + tagline. Big, quiet, confident.
import 'package:flutter/material.dart';

import '../../../core/theme/udao_spacing.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/app_svg.dart';
import '../../../core/theme/udao_theme_extension.dart';
import '../../../l10n/app_localizations.dart';

class BrandStep extends StatelessWidget {
  const BrandStep({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UdaoSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AppSvg(
              AppIcons.logoMark,
              width: 120,
              height: 120,
              color: sem.flameVivid,
            ),
            const SizedBox(height: UdaoSpacing.xl),
            Text(
              l10n.appName,
              style: text.displayMedium?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: UdaoSpacing.md),
            Text(
              l10n.obBrandTagline,
              style: text.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
