// phase-03
// The capture permission gate — the first screen after onboarding.
//
// Notification access cannot be requested with a runtime dialog (the
// user must flip a system toggle), so this screen PRIMES, deep-links,
// re-polls on resume, and once granted runs a 30-second live test
// flight so the user SEES money landing before trusting the app.
//
// The health state itself lives in listenerHealthProvider (polled on
// resume + every 60s); this widget only renders it.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/routes.dart';
import '../../../core/theme/udao_spacing.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/app_svg.dart';
import '../../../core/ui/permission_priming_card.dart';
import '../../../core/ui/section_header.dart';
import '../../../core/ui/stat_chip.dart';
import '../../../core/ui/udao_button.dart';
import '../../../core/ui/udao_card.dart';
import '../../../core/utils/date_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../bridge/capture_raw_event.dart';
import '../bridge/listener_status.dart';
import '../capture_providers.dart';
import '../pipeline/ledger_events.dart';

class ListenerGateScreen extends ConsumerStatefulWidget {
  const ListenerGateScreen({super.key});

  @override
  ConsumerState<ListenerGateScreen> createState() => _ListenerGateScreenState();
}

class _ListenerGateScreenState extends ConsumerState<ListenerGateScreen> {
  static const int _monitorSeconds = 30;

  static const ListenerStatus _offStatus = ListenerStatus(
    connected: false,
    lastEventAt: 0,
    componentEnabled: false,
  );

  StreamSubscription<CaptureRawEvent>? _raw;
  StreamSubscription<TxnCaptured>? _captured;
  Timer? _ticker;
  int _remaining = _monitorSeconds;
  bool _passed = false;
  bool _openedSettings = false;
  bool _monitorStarted = false;
  final List<({String label, String value})> _chips =
      <({String label, String value})>[];

  @override
  void initState() {
    super.initState();
    // The daemon (main) also listens; this subscription only feeds
    // the test-flight chips. Broadcast stream — no interference.
    _raw = ref
        .read(captureBridgeProvider)
        .liveEvents
        .listen((CaptureRawEvent event) {
      if (!mounted || _passed) {
        return;
      }
      _addChip(label: 'RAW', value: event.pkg);
    });
    _captured = ref
        .read(ledgerEventsProvider)
        .stream
        .listen((TxnCaptured event) => _onCaptured(event));
  }

  @override
  void dispose() {
    _raw?.cancel();
    _captured?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _startMonitor() {
    _ticker?.cancel();
    _remaining = _monitorSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (_remaining > 0) {
          _remaining--;
        }
        if (_remaining == 0) {
          _ticker?.cancel();
        }
      });
    });
  }

  void _onCaptured(TxnCaptured event) {
    if (!mounted || _passed) {
      return;
    }
    _ticker?.cancel();
    setState(() {
      _passed = true;
      final int rupees = event.amountPaise ~/ 100;
      _chips.add(
        (
          label: 'PARSED',
          value:
              '\u20b9$rupees \u00b7 ${event.merchantClean} \u00b7 ${event.categoryId ?? 'Other'}'
        ),
      );
    });
  }

  void _addChip({required String label, required String value}) {
    setState(() {
      _chips.add((label: label, value: value));
      if (_chips.length > 6) {
        _chips.removeAt(0);
      }
    });
  }

  Future<void> _openSettings() async {
    setState(() => _openedSettings = true);
    await ref.read(captureBridgeProvider).openListenerSettings();
    // The provider's AppLifecycleListener re-polls on resume.
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ListenerStatus status =
        ref.watch(listenerHealthProvider).valueOrNull ?? _offStatus;

    // Grant detection: arm the test flight exactly once (flag set
    // BEFORE the post-frame callback so rebuilds cannot double-queue).
    if (status.granted && !_monitorStarted) {
      _monitorStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startMonitor();
        }
      });
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(UdaoSpacing.lg),
          children: <Widget>[
            SectionHeader(number: '00', label: l10n.gateTitle),
            const SizedBox(height: UdaoSpacing.xl),
            if (status.granted) ...<Widget>[
              _grantedCard(l10n, status),
              const SizedBox(height: UdaoSpacing.lg),
              _testFlightCard(l10n),
            ] else ...<Widget>[
              _primingCard(l10n, status),
            ],
            const SizedBox(height: UdaoSpacing.xxl),
            UdaoButton(
              label: l10n.gateDoneCta,
              onTap: () => context.go(Routes.aaj),
              variant: status.granted
                  ? UdaoButtonVariant.flameFilled
                  : UdaoButtonVariant.glass,
            ),
          ],
        ),
      ),
    );
  }

  Widget _primingCard(AppLocalizations l10n, ListenerStatus status) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        PermissionPrimingCard(
          title: l10n.gatePrimeTitle,
          body: _openedSettings && !status.granted
              ? l10n.gateReturnedNote
              : l10n.gatePrimeBody,
          ctaLabel: l10n.gateOpenCta,
          iconAsset: AppIcons.verdictBell,
          onCta: _openSettings,
        ),
        const SizedBox(height: UdaoSpacing.md),
        Text(
          l10n.gateAndroid15Note,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: UdaoSpacing.md),
        // Access is OFF, full stop — the prime state must say so
        // unconditionally (phase-03 errata round 2: the old
        // neverConnected ternary showed "Nothing captured yet" to the
        // freshest, most confused user).
        Text(
          l10n.gateStatusOff,
          style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _grantedCard(AppLocalizations l10n, ListenerStatus status) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final DateTime? last = status.lastEventAt == 0
        ? null
        : IstDates.toIst(
            DateTime.fromMillisecondsSinceEpoch(status.lastEventAt),
          );
    return UdaoCard(
      accent: UdaoCardAccent.lime,
      child: Column(
        children: <Widget>[
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutBack,
            builder: (BuildContext context, double scale, Widget? child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: AppSvg(
              AppIcons.chindiBadge,
              width: 64,
              height: 64,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: UdaoSpacing.md),
          Text(
            l10n.gateStatusListening,
            style: text.titleMedium?.copyWith(color: scheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: UdaoSpacing.sm),
          if (last != null)
            Text(
              '${l10n.settingsCaptureLast}: ${IstDates.isoDate(last)} '
              '${last.hour.toString().padLeft(2, '0')}:'
              '${last.minute.toString().padLeft(2, '0')}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            )
          else
            // Granted but nothing captured yet.
            Text(
              l10n.gateStatusNever,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _testFlightCard(AppLocalizations l10n) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return UdaoCard(
      child: Column(
        children: <Widget>[
          Text(
            l10n.gateTestTitle,
            style: text.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: UdaoSpacing.sm),
          Text(
            _passed ? l10n.gateCapturedChip : l10n.gateTestBody,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: UdaoSpacing.md),
          Text(
            l10n.gateTestHint,
            style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: UdaoSpacing.md),
          Text(
            _passed ? '\u2713' : '$_remaining s',
            style: text.headlineMedium?.copyWith(
              color: _passed ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          if (_chips.isNotEmpty) ...<Widget>[
            const SizedBox(height: UdaoSpacing.lg),
            Wrap(
              spacing: UdaoSpacing.md,
              runSpacing: UdaoSpacing.md,
              children: <Widget>[
                for (final ({String label, String value}) chip in _chips)
                  StatChip(label: chip.label, value: chip.value),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
