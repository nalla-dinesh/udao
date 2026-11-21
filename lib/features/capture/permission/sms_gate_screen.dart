// phase-04
// SMS capture gate — POWER FLAVOR ONLY at runtime. The play build
// has no RECEIVE_SMS in its manifest, so this screen renders nothing
// but the honest "off in this build" card there (fail-closed on
// unknown flavor too — see app_flavor.dart).
//
// Copy rules (spec): say exactly WHY SMS is needed, WHAT is read
// (bank/transactional senders only — the native gate drops promos
// before they ever reach storage), WHAT IS NOT read (OTPs are
// dropped by the pipeline even when they come from real banks), the
// 24-hour raw WAL retention, and the Play-build status.
//
// No live test flight here (unlike the notification gate): an SMS
// cannot be triggered on demand — the screen says so instead of
// pretending.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/app_flavor.dart';
import '../../../core/result/result.dart';
import '../../../core/ui/udao_button.dart';
import '../../../core/ui/udao_card.dart';
import '../../../l10n/app_localizations.dart';
import '../ports/capture_ports_providers.dart';
import '../ports/permission_port.dart';

class SmsGateScreen extends ConsumerStatefulWidget {
  const SmsGateScreen({super.key});

  @override
  ConsumerState<SmsGateScreen> createState() => _SmsGateScreenState();
}

enum _SmsState { unknown, granted, denied, permanentlyDenied }

class _SmsGateScreenState extends ConsumerState<SmsGateScreen> {
  _SmsState _state = _SmsState.unknown;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final bool granted =
        await ref.read(permissionPortProvider).isGranted(CapturePermission.sms);
    if (mounted) {
      setState(() {
        _state = granted ? _SmsState.granted : _SmsState.denied;
      });
    }
  }

  Future<void> _request() async {
    final result =
        await ref.read(permissionPortProvider).request(CapturePermission.sms);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok<bool>(:final bool value):
        setState(() {
          _state = value ? _SmsState.granted : _SmsState.denied;
        });
      case Err<bool>(:final failure):
        setState(() {
          _state = failure.message == 'permanently_denied'
              ? _SmsState.permanentlyDenied
              : _SmsState.denied;
        });
    }
  }

  Future<void> _openSettings() async {
    await ref
        .read(permissionPortProvider)
        .openSystemSettings();
    // Re-check when the user comes back.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<AppFlavor> flavor = ref.watch(appFlavorProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.smsGateTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          switch (flavor) {
            AsyncData(value: AppFlavor.power) => _powerBody(l10n),
            AsyncData(value: AppFlavor.play) => _offCard(l10n),
            // Loading / unknown / error: fail CLOSED — nothing
            // actionable until the flavor is proven to be power.
            _ => _offCard(l10n),
          },
        ],
      ),
    );
  }

  Widget _offCard(AppLocalizations l10n) {
    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.smsGateOffTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            l10n.smsGateOffBody,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _powerBody(AppLocalizations l10n) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        UdaoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(l10n.smsGatePrimeTitle, style: text.titleMedium),
              const SizedBox(height: 8),
              Text(l10n.smsGatePrimeBody, style: text.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _honestFacts(l10n),
        const SizedBox(height: 16),
        _stateCard(l10n),
      ],
    );
  }

  /// The honest what-we-read / what-we-drop facts, plainly.
  Widget _honestFacts(AppLocalizations l10n) {
    final TextTheme text = Theme.of(context).textTheme;
    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.smsGateFactsTitle, style: text.titleSmall),
          const SizedBox(height: 8),
          _fact(l10n.smsGateFactRead),
          _fact(l10n.smsGateFactOtp),
          _fact(l10n.smsGateFactPromo),
          _fact(l10n.smsGateFactRetention),
          _fact(l10n.smsGateFactOffline),
        ],
      ),
    );
  }

  Widget _fact(String s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(padding: EdgeInsets.only(right: 8), child: Text('\u2022')),
          Expanded(child: Text(s, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }

  Widget _stateCard(AppLocalizations l10n) {
    switch (_state) {
      case _SmsState.unknown:
        return const SizedBox.shrink();
      case _SmsState.granted:
        return UdaoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.smsGateGrantedTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.smsGateGrantedBody,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        );
      case _SmsState.denied:
        return UdaoButton(
          label: l10n.smsGateAllowCta,
          size: UdaoButtonSize.lg,
          onTap: _request,
        );
      case _SmsState.permanentlyDenied:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.smsGatePermDeniedBody),
            const SizedBox(height: 12),
            UdaoButton(
              label: l10n.smsGateOpenSettings,
              variant: UdaoButtonVariant.glass,
              onTap: _openSettings,
            ),
          ],
        );
    }
  }
}
