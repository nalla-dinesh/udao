// phase-01
// 5-step onboarding: brand → how it works → notification priming →
// personality → name/done. PageView hosts the steps; progress stamps
// and next/back live outside it so they never re-animate on swipe.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/routes.dart';
import '../../core/theme/udao_colors.dart';
import '../../core/theme/udao_motion.dart';
import '../../core/theme/udao_spacing.dart';
import '../../core/theme/udao_theme_extension.dart';
import '../../core/ui/udao_button.dart';
import '../../l10n/app_localizations.dart';
import 'onboarding_provider.dart';
import 'steps/brand_step.dart';
import 'steps/how_it_works_step.dart';
import 'steps/name_step.dart';
import 'steps/notification_step.dart';
import 'steps/personality_step.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int stepCount = 5;

  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _animateTo(int page) {
    return _pageController.animateToPage(
      page,
      duration: UdaoMotion.slow,
      curve: UdaoMotion.ease,
    );
  }

  void _next() {
    final int current = ref.read(onboardingProvider).page;
    if (current < stepCount - 1) {
      ref.read(onboardingProvider.notifier).setPage(current + 1);
      unawaited(_animateTo(current + 1));
    } else {
      unawaited(_finish());
    }
  }

  void _back() {
    final int current = ref.read(onboardingProvider).page;
    if (current > 0) {
      ref.read(onboardingProvider.notifier).setPage(current - 1);
      unawaited(_animateTo(current - 1));
    }
  }

  Future<void> _finish() async {
    await ref.read(onboardingProvider.notifier).complete();
    if (!mounted) {
      return;
    }
    // Phase 03: capture permission gate sits between onboarding and
    // the shell (zero-capture = zero ledger, so this is the money
    // screen for the whole product). Re-reachable from settings.
    context.go(Routes.captureGate);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final OnboardingState onboarding = ref.watch(onboardingProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(UdaoSpacing.lg),
              child: _ProgressStamps(
                current: onboarding.page,
                count: stepCount,
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (int page) =>
                    ref.read(onboardingProvider.notifier).setPage(page),
                children: <Widget>[
                  const BrandStep(),
                  const HowItWorksStep(),
                  NotificationStep(
                    onAllow: () {
                      ref
                          .read(onboardingProvider.notifier)
                          .setNotifIntent(true);
                      _next();
                    },
                    onLater: _next,
                  ),
                  const PersonalityStep(),
                  NameStep(
                    onChanged: (String value) {
                      ref.read(onboardingProvider.notifier).setName(value);
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(UdaoSpacing.lg),
              child: Row(
                children: <Widget>[
                  if (onboarding.page > 0) ...<Widget>[
                    Expanded(
                      child: UdaoButton(
                        label: l10n.obBack,
                        variant: UdaoButtonVariant.glass,
                        onTap: _back,
                      ),
                    ),
                    const SizedBox(width: UdaoSpacing.md),
                  ],
                  Expanded(
                    child: UdaoButton(
                      label: onboarding.page == stepCount - 1
                          ? l10n.obDone
                          : l10n.obNext,
                      onTap: _next,
                    ),
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

class _ProgressStamps extends StatelessWidget {
  const _ProgressStamps({required this.current, required this.count});

  final int current;
  final int count;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Row(
      children: <Widget>[
        for (int i = 0; i < count; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: UdaoSpacing.sm),
          AnimatedContainer(
            duration: UdaoMotion.fast,
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i <= current ? scheme.primary : UdaoColors.transparent,
              borderRadius: BorderRadius.circular(UdaoRadius.sm),
              border: i <= current
                  ? null
                  : Border.all(color: sem.cardBorder),
            ),
            child: Text(
              '${i + 1}',
              style: text.labelSmall?.copyWith(
                color: i <= current
                    ? scheme.onPrimary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
