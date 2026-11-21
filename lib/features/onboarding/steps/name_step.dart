// phase-01
// Step 5 — optional name (≤20 chars, uncontrolled field) + the
// "setup done" send-off. The Next button below turns into the final
// CTA on this step.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/udao_spacing.dart';
import '../../../core/theme/udao_theme_extension.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/app_svg.dart';
import '../../../l10n/app_localizations.dart';

class NameStep extends ConsumerWidget {
  const NameStep({required this.onChanged, super.key});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(UdaoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.obNameTitle,
            style: text.headlineMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: UdaoSpacing.lg),
          TextField(
            maxLength: 20,
            onChanged: onChanged,
            style: text.titleMedium?.copyWith(color: scheme.onSurface),
            decoration: InputDecoration(
              hintText: l10n.obNameHint,
              hintStyle: text.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UdaoRadius.card),
                borderSide: BorderSide(color: sem.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UdaoRadius.card),
                borderSide: BorderSide(color: sem.flame, width: 2),
              ),
            ),
          ),
          const SizedBox(height: UdaoSpacing.xl),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppSvg(
                  AppIcons.logoMark,
                  width: 64,
                  height: 64,
                  color: sem.flameVivid,
                ),
                const SizedBox(height: UdaoSpacing.lg),
                Text(
                  l10n.obDoneMessage,
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
