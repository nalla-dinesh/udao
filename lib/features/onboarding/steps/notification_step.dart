// phase-01
// Step 3 — notification priming: live notification MOCK (VerdictBell)
// + the actual ask (PermissionPrimingCard). No real permission is
// requested here yet — that lands with the capture engine in Phase 03;
// for now we record the user's intent.
import 'package:flutter/material.dart';

import '../../../core/theme/udao_spacing.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/permission_priming_card.dart';
import '../../../core/ui/verdict_bell.dart';
import '../../../l10n/app_localizations.dart';

class NotificationStep extends StatelessWidget {
  const NotificationStep({
    required this.onAllow,
    required this.onLater,
    super.key,
  });

  final VoidCallback onAllow;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(UdaoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.obNotifTitle,
            style: text.headlineMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: UdaoSpacing.xl),
          Center(
            child: VerdictBell(
              appName: l10n.appName,
              title: l10n.obNotifDemoTitle,
              body: l10n.obNotifDemoBody,
              timeLabel: '8:30 PM',
            ),
          ),
          const SizedBox(height: UdaoSpacing.xl),
          PermissionPrimingCard(
            title: l10n.obNotifTitle,
            body: l10n.obNotifBody,
            ctaLabel: l10n.obNotifCta,
            onCta: onAllow,
            secondaryLabel: l10n.obNotifLater,
            onSecondary: onLater,
            iconAsset: AppIcons.verdictBell,
          ),
          // TODO-VERIFY(local): Phase 03 replaces onAllow/onLater with the
          // real notification-access request; the recorded intent
          // (`notification_intent`) drives that flow's copy.
        ],
      ),
    );
  }
}
