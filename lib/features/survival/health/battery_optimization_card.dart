// phase-05
// The battery-optimization card — T3's flavor-split surface.
//
//   POWER flavor (sideload): direct system dialog → battery list →
//     app details (full fallback chain, permission declared).
//   PLAY flavor: the LIST screen only (+ app details). The direct
//     dialog's permission is Play-restricted and NOT declared in
//     the play manifest — the bridge double-guards by flavor, so a
//     play build can never even try (ADR-0002/0006).
//
// Nag honesty: the full priming card shows at most once per 7 days
// (kv stamp); in between, a one-line compact reminder stays
// available — never hidden information, never spam.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_flavor.dart';
import '../../../core/ui/udao_button.dart';
import '../../../core/ui/udao_card.dart';
import '../../../core/ui/udao_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../capture/capture_providers.dart';
import '../survival_providers.dart';
import 'probe_bridge.dart';
import 'survival_models.dart';

class BatteryOptimizationCard extends ConsumerStatefulWidget {
  const BatteryOptimizationCard({super.key});

  @override
  ConsumerState<BatteryOptimizationCard> createState() =>
      _BatteryOptimizationCardState();
}

class _BatteryOptimizationCardState
    extends ConsumerState<BatteryOptimizationCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final SurvivalBridgeApi bridge = ref.watch(survivalBridgeProvider);
    final AppFlavor flavor =
        ref.watch(appFlavorProvider).valueOrNull ?? AppFlavor.unknown;
    final AsyncValue<PowerState> powerAsync = ref.watch(powerStateProvider);
    final bool exempt =
        powerAsync.valueOrNull?.ignoringBatteryOptimizations ?? false;

    if (exempt) {
      return UdaoCard(
        accent: UdaoCardAccent.lime,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.survivalBattExemptTitle, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(l10n.survivalBattExemptBody, style: text.bodyMedium),
          ],
        ),
      );
    }

    final bool powerBuild = flavor == AppFlavor.power;

    return UdaoCard(
      accent: UdaoCardAccent.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalBattNotExemptTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(l10n.survivalBattNotExemptBody, style: text.bodyMedium),
          if (!powerBuild) ...<Widget>[
            const SizedBox(height: 4),
            Text(l10n.survivalBattPlayNote, style: text.bodySmall),
          ],
          const SizedBox(height: 12),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Row(
            children: <Widget>[
              Expanded(
                child: UdaoButton(
                  label: powerBuild
                      ? l10n.survivalBattDirectCta
                      : l10n.survivalBattListCta,
                  size: UdaoButtonSize.sm,
                  variant: UdaoButtonVariant.flameFilled,
                  onTap: _busy ? null : () => unawaited(_fix(bridge)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: UdaoButton(
                  label: l10n.survivalBattDetailsCta,
                  size: UdaoButtonSize.sm,
                  variant: UdaoButtonVariant.glass,
                  onTap: _busy ? null : () => unawaited(_details(bridge)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _fix(SurvivalBridgeApi bridge) async {
    setState(() => _busy = true);
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      bool ok = false;
      // Power: direct dialog first; fall back to the list screen;
      // play: straight to the list (bridge refuses the direct ask).
      if (ref.read(appFlavorProvider).valueOrNull == AppFlavor.power) {
        ok = await bridge.requestIgnoreBatteryOptimizations();
      }
      if (!ok) {
        ok = await bridge.openBatteryOptimizationSettings();
      }
      // Stamp the nag — one full priming per 7 days, best effort.
      await markBatteryNag(
        ref.read(kvDaoProvider),
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (mounted) {
        UdaoSnackBar.show(
          context,
          message: ok
              ? l10n.survivalBattOpened
              : l10n.survivalBattOpenFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _details(SurvivalBridgeApi bridge) async {
    await bridge.openAppDetails();
  }
}
