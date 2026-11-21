// phase-05
// The OEM setup flow: detected maker → numbered steps with deep-link
// buttons → manual fallback (always) → acknowledge ("ho gaya").
//
// Ack is VERSIONED kv (`survival.oemSetupAck.v1`): bumping the key
// re-surfaces the flow after a breaking change (e.g. MIUI 16
// renamed everything). Deep links fail CLOSED — a miss shows the
// manual steps inline, never a dead end.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/udao_button.dart';
import '../../../core/ui/udao_card.dart';
import '../../../core/ui/udao_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../capture/capture_providers.dart';
import '../survival_providers.dart';
import 'oem_detector.dart';
import 'oem_guide_data.dart';

class OemSetupFlowScreen extends ConsumerStatefulWidget {
  const OemSetupFlowScreen({super.key});

  @override
  ConsumerState<OemSetupFlowScreen> createState() =>
      _OemSetupFlowScreenState();
}

class _OemSetupFlowScreenState extends ConsumerState<OemSetupFlowScreen> {
  bool _busyLink = false;
  bool _acked = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<OemId> oemAsync = ref.watch(oemIdProvider);
    final OemId oem = oemAsync.valueOrNull ?? OemId.stock;
    final OemSetupGuide guide = OemGuideData.forId(oem);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.survivalOemSetupTitle(oem.label))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          UdaoCard(
            accent: UdaoCardAccent.sky,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.survivalOemSetupSummaryTitle,
                  style: text.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(guide.summary, style: text.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < guide.steps.length; i++)
            _StepCard(
              index: i + 1,
              step: guide.steps[i],
              busy: _busyLink,
              onDeepLink: _busyLink
                  ? null
                  : (String component) => unawaited(_openDeepLink(component)),
            ),
          const SizedBox(height: 12),
          _ManualFallbackCard(guide: guide),
          const SizedBox(height: 12),
          UdaoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.survivalOemNotesTitle, style: text.titleMedium),
                const SizedBox(height: 6),
                for (final String note in guide.notes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('• $note', style: text.bodyMedium),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: UdaoButton(
                  label: _acked
                      ? l10n.survivalOemAckDone
                      : l10n.survivalOemAckCta,
                  size: UdaoButtonSize.md,
                  variant: UdaoButtonVariant.limeFilled,
                  onTap: _acked ? null : () => unawaited(_ack()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _openDeepLink(String component) async {
    setState(() => _busyLink = true);
    try {
      final bool ok =
          await ref.read(survivalBridgeProvider).openOemScreen(component);
      if (mounted) {
        UdaoSnackBar.show(
          context,
          message: ok
              ? AppLocalizations.of(context).survivalOemLinkOpened
              : AppLocalizations.of(context).survivalOemLinkMissed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyLink = false);
      }
    }
  }

  Future<void> _ack() async {
    try {
      await markOemSetupAcked(
        ref.read(kvDaoProvider),
        now: DateTime.now(),
      );
    } on Object {
      // Best effort: the ack is a UX nicety, not data.
    }
    if (mounted) {
      setState(() => _acked = true);
      UdaoSnackBar.show(
        context,
        message: AppLocalizations.of(context).survivalOemAckSaved,
      );
    }
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.step,
    required this.busy,
    required this.onDeepLink,
  });

  final int index;
  final OemGuideStep step;
  final bool busy;
  final void Function(String component)? onDeepLink;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: UdaoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.survivalOemStepTitle(index), style: text.titleMedium),
            const SizedBox(height: 6),
            Text(step.detail, style: text.bodyMedium),
            if (step.deepLink != null) ...<Widget>[
              const SizedBox(height: 12),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: UdaoButton(
                      label: step.deepLink!.label,
                      size: UdaoButtonSize.sm,
                      variant: UdaoButtonVariant.flameFilled,
                      onTap: busy
                          ? null
                          : () => onDeepLink?.call(step.deepLink!.component),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ManualFallbackCard extends StatelessWidget {
  const _ManualFallbackCard({required this.guide});

  final OemSetupGuide guide;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return UdaoCard(
      accent: UdaoCardAccent.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(guide.manualTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          for (int i = 0; i < guide.manualSteps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${i + 1}. ${guide.manualSteps[i]}',
                style: text.bodyMedium,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            l10n.survivalOemDkmaNote(guide.oem.dontKillMyAppUrl),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
