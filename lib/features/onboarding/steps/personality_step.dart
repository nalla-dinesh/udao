// phase-01
// Step 4 — personality picker. Savage is the default and is marked
// DEFAULT so the choice feels pre-made (it is).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/udao_spacing.dart';
import '../../../core/theme/udao_theme_extension.dart';
import '../../../core/ui/udao_card.dart';
import '../../../l10n/app_localizations.dart';
import '../onboarding_provider.dart';

class PersonalityStep extends ConsumerWidget {
  const PersonalityStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final OnboardingState onboarding = ref.watch(onboardingProvider);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    final List<(
      UdaoPersonality,
      IconData,
      Color,
      String,
      String,
      String?,
    )> personalities = <(
      UdaoPersonality,
      IconData,
      Color,
      String,
      String,
      String?,
    )>[
      (
        UdaoPersonality.savage,
        PhosphorIconsBold.fire,
        sem.flame,
        l10n.personalitySavage,
        l10n.personalitySavageDesc,
        'DEFAULT',
      ),
      (
        UdaoPersonality.hype,
        PhosphorIconsBold.rocket,
        sem.gold,
        l10n.personalityHype,
        l10n.personalityHypeDesc,
        null,
      ),
      (
        UdaoPersonality.silent,
        PhosphorIconsBold.moon,
        sem.sky,
        l10n.personalitySilent,
        l10n.personalitySilentDesc,
        null,
      ),
      (
        UdaoPersonality.sensei,
        PhosphorIconsBold.graduationCap,
        sem.violet,
        l10n.personalitySensei,
        l10n.personalitySenseiDesc,
        null,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(UdaoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.obPersonalityTitle,
            style: text.headlineMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: UdaoSpacing.lg),
          for (
            final (
              UdaoPersonality value,
              IconData icon,
              Color color,
              String title,
              String desc,
              String? tag,
            ) in personalities
          )
            Padding(
              padding: const EdgeInsets.only(bottom: UdaoSpacing.md),
              child: UdaoCard(
                accent: onboarding.personality == value
                    ? _accentFor(value)
                    : UdaoCardAccent.none,
                onTap: () => ref
                    .read(onboardingProvider.notifier)
                    .setPersonality(value),
                child: Row(
                  children: <Widget>[
                    PhosphorIcon(icon, size: 28, color: color),
                    const SizedBox(width: UdaoSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                title.toUpperCase(),
                                style: text.titleMedium?.copyWith(
                                  color: scheme.onSurface,
                                ),
                              ),
                              if (tag != null) ...<Widget>[
                                const SizedBox(width: UdaoSpacing.sm),
                                Text(
                                  tag,
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: UdaoSpacing.xs),
                          Text(
                            desc,
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
            ),
        ],
      ),
    );
  }

  static UdaoCardAccent _accentFor(UdaoPersonality value) {
    return switch (value) {
      UdaoPersonality.savage => UdaoCardAccent.flame,
      UdaoPersonality.hype => UdaoCardAccent.gold,
      UdaoPersonality.silent => UdaoCardAccent.sky,
      UdaoPersonality.sensei => UdaoCardAccent.lime,
    };
  }
}
