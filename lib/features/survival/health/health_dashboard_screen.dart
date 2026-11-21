// phase-05
// The capture-health dashboard — the one screen where the user can
// SEE whether UDAO's ears still work, and fix them without calling
// anyone. Everything on it is honest by construction:
//
//   * The stamp (SHARP / DHYAN DO / BAND) comes from live listener
//     state + last-event age — never from wishful defaults.
//   * Every probe that cannot answer on this device says "pata
//     nahi" instead of guessing.
//   * The sparkline plots the ledger's own per-day counters.
//   * Diagnostics export shares a JSON SUMMARY — raw notification
//     text NEVER leaves the database (24h purge + hash-only rows).
//   * Battery honesty: "<1%/day passive" — passive = listener +
//     30-min watchdog, keep-alive service excluded because it is
//     the user's explicit choice.
//
// Widget-test note: [captureStatsProvider] and [healthClockProvider]
// are the injection points — tests override them with fixtures, no
// real DB is ever opened.
import 'dart:async';
import 'dart:convert';

import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/routes.dart';
import '../../../core/log/udao_logger.dart';
import '../../../core/ui/stat_chip.dart';
import '../../../core/ui/udao_button.dart';
import '../../../core/ui/udao_card.dart';
import '../../../core/ui/udao_snack_bar.dart';
import '../../../data/db/dao/capture_health_dao.dart';
import '../../../l10n/app_localizations.dart';
import '../../capture/bridge/listener_status.dart';
import '../../capture/capture_providers.dart';
import '../survival_providers.dart';
import '../oem/oem_detector.dart';
import 'battery_optimization_card.dart';
import 'survival_models.dart';
import 'watchdog_planner.dart';

/// Per-day capture counters feed (7-day window of the dashboard).
/// OVERRIDDEN in widget tests with fixture lists.
final FutureProvider<List<CaptureDayStats>> captureStatsProvider =
    FutureProvider<List<CaptureDayStats>>((Ref ref) async {
  final List<CaptureDayStats> stats =
      (await CaptureHealthDao(ref.watch(dbProvider).db).statsByDay(days: 14))
              .valueOrNull ??
          <CaptureDayStats>[];
  return stats.take(7).toList(growable: false);
});

/// Clock seam (stamps + diagnostics timestamps) — tests fix it.
final Provider<int> healthClockProvider = Provider<int>(
  (Ref ref) => DateTime.now().millisecondsSinceEpoch,
);

/// Diagnostics payload builder — PURE (test pins the shape and the
/// "no raw text" invariant: only counters + enums + timestamps).
String buildDiagnosticsJson({
  required int generatedAt,
  required String oemSlug,
  required String appVersionNote,
  required bool listenerConnected,
  required int lastEventAt,
  required PowerState power,
  required WatchdogSnapshot watchdog,
  required KeepAliveState keepAlive,
  required List<CaptureDayStats> stats,
}) {
  return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'schema': 'udao.diagnostics.v1',
    'generatedAt': generatedAt,
    'oem': oemSlug,
    'note': appVersionNote,
    'listener': <String, Object?>{
      'connected': listenerConnected,
      'lastEventAt': lastEventAt,
    },
    'power': <String, Object?>{
      'ignoringBatteryOptimizations': power.ignoringBatteryOptimizations,
      'powerSaverMode': power.powerSaverMode,
      'backgroundRestricted': power.backgroundRestricted,
      'standbyBucket': power.standbyBucket,
      'deviceIdle': power.deviceIdle,
    },
    'watchdog': <String, Object?>{
      'lastPingAt': watchdog.lastPingAt,
      'lastAction': watchdog.lastAction,
      'startedDown': watchdog.startedDown,
      'listenerOk': watchdog.listenerOk,
      'oemSuspect': watchdog.oemSuspect,
    },
    'keepAlive': <String, Object?>{
      'running': keepAlive.running,
      'beats': keepAlive.beats,
      'lastBeatAt': keepAlive.lastBeatAt,
    },
    'capture7d': <Map<String, Object?>>[
      for (final CaptureDayStats s in stats)
        <String, Object?>{
          'dayStartMs': s.dayStartMs,
          'seen': s.seen,
          'parsed': s.parsed,
          'deduped': s.deduped,
        },
    ],
    'privacy': 'no raw notification/sms text included, by design',
  });
}

class HealthDashboardScreen extends ConsumerStatefulWidget {
  const HealthDashboardScreen({super.key});

  @override
  ConsumerState<HealthDashboardScreen> createState() =>
      _HealthDashboardScreenState();
}

class _HealthDashboardScreenState
    extends ConsumerState<HealthDashboardScreen> {
  static const ListenerStatus _fallbackStatus = ListenerStatus(
    connected: false,
    lastEventAt: 0,
    componentEnabled: false,
  );

  bool _busyKeepAlive = false;
  bool _busyRebind = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    final ListenerStatus listener =
        ref.watch(listenerHealthProvider).valueOrNull ?? _fallbackStatus;
    final int nowMs = ref.watch(healthClockProvider);
    final HealthVerdict verdict = WatchdogPlanner.verdict(
      listenerConnected: listener.connected,
      lastEventAt: listener.lastEventAt,
      nowMs: nowMs,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.survivalHealthTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _StampCard(verdict: verdict, listener: listener, nowMs: nowMs),
          const SizedBox(height: 12),
          _GapAlertCard(nowMs: nowMs),
          const SizedBox(height: 12),
          _ListenerCard(
            listener: listener,
            busyRebind: _busyRebind,
            onRebind: _onRebind,
            onToggle: _onToggleRebind,
          ),
          const SizedBox(height: 12),
          _WatchdogCard(nowMs: nowMs),
          const SizedBox(height: 12),
          _SparklineCard(nowMs: nowMs),
          const SizedBox(height: 12),
          _KeepAliveCard(
            busy: _busyKeepAlive,
            onToggle: _onToggleKeepAlive,
          ),
          const SizedBox(height: 12),
          const BatteryOptimizationCard(),
          const SizedBox(height: 12),
          _DeviceTruthCard(nowMs: nowMs),
          const SizedBox(height: 12),
          _ExitInfoCard(nowMs: nowMs),
          const SizedBox(height: 12),
          _OemCard(nowMs: nowMs),
          const SizedBox(height: 12),
          _DiagnosticsCard(onExport: _onExport),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              l10n.survivalBatteryHonesty,
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Actions (unawaited-modal lesson: snackbars only, no awaits
  //    on anything that outlives the frame) ─────────────────────────

  Future<void> _onRebind() async {
    setState(() => _busyRebind = true);
    try {
      await ref.read(captureBridgeProvider).requestRebind();
      unawaited(ref.read(listenerHealthProvider.notifier).refresh());
      if (mounted) {
        UdaoSnackBar.show(
          context,
          message: AppLocalizations.of(context).survivalRebindSent,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyRebind = false);
      }
    }
  }

  Future<void> _onToggleRebind() async {
    setState(() => _busyRebind = true);
    try {
      await ref.read(captureBridgeProvider).rebindViaToggle();
      await Future<void>.delayed(const Duration(seconds: 2));
      unawaited(ref.read(listenerHealthProvider.notifier).refresh());
      if (mounted) {
        UdaoSnackBar.show(
          context,
          message: AppLocalizations.of(context).survivalToggleSent,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyRebind = false);
      }
    }
  }

  Future<void> _onToggleKeepAlive() async {
    final bool running =
        ref.read(keepAliveProvider).valueOrNull?.running ?? false;
    setState(() => _busyKeepAlive = true);
    try {
      if (running) {
        await ref.read(keepAliveProvider.notifier).stop();
      } else {
        await ref.read(keepAliveProvider.notifier).start();
      }
      if (mounted) {
        UdaoSnackBar.show(
          context,
          message: running
              ? AppLocalizations.of(context).survivalKeepAliveStopped
              : AppLocalizations.of(context).survivalKeepAliveStarted,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyKeepAlive = false);
      }
    }
  }

  Future<void> _onExport() async {
    try {
      final int nowMs = ref.read(healthClockProvider);
      final String json = buildDiagnosticsJson(
        generatedAt: nowMs,
        oemSlug: ref.read(oemIdProvider).valueOrNull?.name ?? 'stock',
        appVersionNote: 'play-flavor policies: no battery permission',
        listenerConnected:
            ref.read(listenerHealthProvider).valueOrNull?.connected ?? false,
        lastEventAt:
            ref.read(listenerHealthProvider).valueOrNull?.lastEventAt ?? 0,
        power: await ref.read(powerStateProvider.future),
        watchdog: await ref.read(watchdogSnapshotProvider.future),
        keepAlive: ref.read(keepAliveProvider).valueOrNull ??
            KeepAliveState.stopped,
        stats: await ref.read(captureStatsProvider.future),
      );
      await Share.share(json);
    } on Object catch (e, s) {
      udaoLog.error('diagnostics export failed', error: e);
      udaoLog.fatal('diagnostics export stack', error: s);
      if (mounted) {
        UdaoSnackBar.show(
          context,
          message: AppLocalizations.of(context).survivalExportFailed,
        );
      }
    }
  }
}


// ── Stamp card ───────────────────────────────────────────────────────

class _StampCard extends ConsumerWidget {
  const _StampCard({
    required this.verdict,
    required this.listener,
    required this.nowMs,
  });

  final HealthVerdict verdict;
  final ListenerStatus listener;
  final int nowMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    final (String stamp, String body, UdaoCardAccent accent) = switch (verdict) {
      HealthVerdict.sharp => (
          l10n.survivalStampSharp,
          l10n.survivalStampSharpBody,
          UdaoCardAccent.lime,
        ),
      HealthVerdict.watch => (
          l10n.survivalStampWatch,
          l10n.survivalStampWatchBody,
          UdaoCardAccent.gold,
        ),
      HealthVerdict.dead => (
          l10n.survivalStampDead,
          l10n.survivalStampDeadBody,
          UdaoCardAccent.flame,
        ),
    };

    return UdaoCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(stamp, style: text.headlineMedium),
          const SizedBox(height: 6),
          Text(body, style: text.bodyMedium),
          const SizedBox(height: 10),
          Text(
            l10n.survivalLastEvent(_relativeAge(listener.lastEventAt, nowMs)),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _relativeAge(int lastEventAt, int nowMs) {
    if (lastEventAt <= 0) {
      return '—';
    }
    final int hours = (nowMs - lastEventAt) ~/ 3600000;
    if (hours < 1) {
      return '<1h';
    }
    if (hours < 24) {
      return '${hours}h';
    }
    return '${hours ~/ 24}d';
  }
}

// ── Gap alert (pending weekly-job finding) ───────────────────────────

class _GapAlertCard extends ConsumerWidget {
  const _GapAlertCard({required this.nowMs});

  final int nowMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<Map<String, Object?>?> pending =
        ref.watch(gapAlertPendingProvider);
    final Map<String, Object?>? payload = pending.valueOrNull;

    if (payload == null) {
      return const SizedBox.shrink();
    }

    final int silent = (payload['silentWeekdays'] as num?)?.toInt() ?? 0;
    final Object? hoursRaw = payload['listenerSilentHours'];

    return UdaoCard(
      accent: UdaoCardAccent.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalGapAlertTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            hoursRaw == null
                ? l10n.survivalGapAlertSilent(silent)
                : l10n.survivalGapAlertSilentAndStale(
                    silent,
                    (hoursRaw as num).toStringAsFixed(0),
                  ),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: UdaoButton(
                  label: l10n.survivalGapAlertSeen,
                  size: UdaoButtonSize.sm,
                  variant: UdaoButtonVariant.limeFilled,
                  onTap: () => unawaited(_flush(ref)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _flush(WidgetRef ref) async {
    await flushGapAlert(
      bridge: ref.read(survivalBridgeProvider),
      kv: ref.read(kvDaoProvider),
      onCleared: () => ref.invalidate(gapAlertPendingProvider),
    );
  }
}

// ── Listener card ────────────────────────────────────────────────────

class _ListenerCard extends ConsumerWidget {
  const _ListenerCard({
    required this.listener,
    required this.busyRebind,
    required this.onRebind,
    required this.onToggle,
  });

  final ListenerStatus listener;
  final bool busyRebind;
  final Future<void> Function() onRebind;
  final Future<void> Function() onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalListenerTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            listener.connected
                ? l10n.survivalListenerBound
                : l10n.survivalListenerUnbound,
            style: text.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            listener.componentEnabled
                ? l10n.survivalComponentEnabled
                : l10n.survivalComponentDisabled,
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          if (busyRebind)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          // Phase-04 lesson: two CTAs side-by-side must wrap in
          // Expanded inside a Row — never raw, never Spacer.
          Row(
            children: <Widget>[
              Expanded(
                child: UdaoButton(
                  label: l10n.survivalRebindCta,
                  size: UdaoButtonSize.sm,
                  variant: UdaoButtonVariant.flameFilled,
                  onTap: busyRebind ? null : () => unawaited(onRebind()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: UdaoButton(
                  label: l10n.survivalToggleCta,
                  size: UdaoButtonSize.sm,
                  variant: UdaoButtonVariant.glass,
                  onTap: busyRebind ? null : () => unawaited(onToggle()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Watchdog card ────────────────────────────────────────────────────

class _WatchdogCard extends ConsumerWidget {
  const _WatchdogCard({required this.nowMs});

  final int nowMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final WatchdogSnapshot snapshot =
        ref.watch(watchdogSnapshotProvider).valueOrNull ??
            WatchdogSnapshot.empty;

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalWatchdogTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            WatchdogPlanner.explainLastRun(snapshot),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            snapshot.lastPingAt > 0
                ? l10n.survivalWatchdogLastPing(
                        _age(snapshot.lastPingAt, nowMs),
                      )
                : l10n.survivalWatchdogNeverRan,
            style: text.bodySmall,
          ),
          if (snapshot.oemSuspect) ...<Widget>[
            const SizedBox(height: 6),
            Text(l10n.survivalWatchdogOemNote, style: text.bodySmall),
          ],
        ],
      ),
    );
  }

  static String _age(int at, int nowMs) {
    final int minutes = (nowMs - at) ~/ 60000;
    if (minutes < 60) {
      return '${minutes}m';
    }
    return '${minutes ~/ 60}h';
  }
}

// ── Sparkline + counters ─────────────────────────────────────────────

class _SparklineCard extends ConsumerWidget {
  const _SparklineCard({required this.nowMs});

  final int nowMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final List<CaptureDayStats> stats =
        ref.watch(captureStatsProvider).valueOrNull ?? <CaptureDayStats>[];

    final int seen = stats.fold<int>(0, (int a, CaptureDayStats s) => a + s.seen);
    final int parsed =
        stats.fold<int>(0, (int a, CaptureDayStats s) => a + s.parsed);
    final int deduped =
        stats.fold<int>(0, (int a, CaptureDayStats s) => a + s.deduped);

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalSparkTitle, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.survivalSparkSubtitle, style: text.bodySmall),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparklinePainter(
                points: stats.map((CaptureDayStats s) => s.seen).toList(
                      growable: false,
                    ),
                color: Theme.of(context).colorScheme.primary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 12),
          if (stats.isEmpty)
            Text(l10n.survivalSparkEmpty, style: text.bodySmall)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                StatChip(label: l10n.survivalStatSeen, value: '$seen'),
                StatChip(label: l10n.survivalStatParsed, value: '$parsed'),
                StatChip(label: l10n.survivalStatDeduped, value: '$deduped'),
              ],
            ),
        ],
      ),
    );
  }
}

/// 7-point seen-count sparkline. Flat data → honest flat line.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.points, required this.color});

  final List<int> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final Paint dot = Paint()..color = color;

    if (points.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        line..strokeWidth = 1,
      );
      return;
    }

    final int maxVal = points.reduce((int a, int b) => a > b ? a : b);
    final double dx = points.length == 1
        ? 0
        : size.width / (points.length - 1);
    final double usableHeight = size.height - 8;
    double yFor(int v) =>
        maxVal == 0 ? size.height - 4 : size.height - 4 - (v / maxVal) * usableHeight;

    final List<Offset> offsets = <Offset>[
      for (int i = 0; i < points.length; i++)
        Offset(i * dx, yFor(points[i])),
    ];

    if (offsets.length == 1) {
      canvas.drawCircle(offsets.single, 3, dot);
      return;
    }
    canvas.drawPoints(PointMode.polygon, offsets, line);
    for (final Offset o in offsets) {
      canvas.drawCircle(o, 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

// ── Keep-alive card ──────────────────────────────────────────────────

class _KeepAliveCard extends ConsumerWidget {
  const _KeepAliveCard({required this.busy, required this.onToggle});

  final bool busy;
  final Future<void> Function() onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final KeepAliveState state = ref.watch(keepAliveProvider).valueOrNull ??
        KeepAliveState.stopped;

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalKeepAliveTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            state.running
                ? l10n.survivalKeepAliveOn(state.beats)
                : l10n.survivalKeepAliveOff,
            style: text.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(l10n.survivalKeepAliveNote, style: text.bodySmall),
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
                  label: state.running
                      ? l10n.survivalKeepAliveStop
                      : l10n.survivalKeepAliveStart,
                  size: UdaoButtonSize.sm,
                  variant: state.running
                      ? UdaoButtonVariant.danger
                      : UdaoButtonVariant.flameFilled,
                  onTap: busy ? null : () => unawaited(onToggle()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Device truth card ────────────────────────────────────────────────

class _DeviceTruthCard extends ConsumerWidget {
  const _DeviceTruthCard({required this.nowMs});

  final int nowMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final PowerState power =
        ref.watch(powerStateProvider).valueOrNull ?? _unknownPower;

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalDeviceTruthTitle, style: text.titleMedium),
          const SizedBox(height: 8),
          _truthRow(
            l10n.survivalTruthBatteryOpt,
            power.ignoringBatteryOptimizations
                ? l10n.survivalTruthExempt
                : l10n.survivalTruthOptimized,
          ),
          _truthRow(
            l10n.survivalTruthPowerSaver,
            power.powerSaverMode ? l10n.survivalTruthOn : l10n.survivalTruthOff,
          ),
          _truthRow(
            l10n.survivalTruthBackgroundRestricted,
            power.backgroundRestricted == null
                ? l10n.survivalTruthUnknown
                : (power.backgroundRestricted!
                    ? l10n.survivalTruthYes
                    : l10n.survivalTruthNo),
          ),
          _truthRow(
            l10n.survivalTruthStandbyBucket,
            power.standbyBucketLabel,
          ),
          _truthRow(
            l10n.survivalTruthDeviceIdle,
            power.deviceIdle ? l10n.survivalTruthYes : l10n.survivalTruthNo,
          ),
        ],
      ),
    );
  }

  static const PowerState _unknownPower = PowerState(
    ignoringBatteryOptimizations: false,
    powerSaverMode: false,
    backgroundRestricted: null,
    standbyBucket: null,
    deviceIdle: false,
  );

  static Widget _truthRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(value, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

// ── Exit info card ───────────────────────────────────────────────────

class _ExitInfoCard extends ConsumerWidget {
  const _ExitInfoCard({required this.nowMs});

  final int nowMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final List<ExitInfo> exits =
        ref.watch(exitInfosProvider).valueOrNull ?? <ExitInfo>[];

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalExitTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          if (exits.isEmpty)
            Text(l10n.survivalExitEmpty, style: text.bodySmall)
          else
            for (final ExitInfo e in exits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${_age(e.timestamp)} — ${e.label}',
                  style: text.bodyMedium,
                ),
              ),
        ],
      ),
    );
  }

  static String _age(int ts) {
    if (ts <= 0) {
      return '—';
    }
    final int days = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ts),
    ).inDays;
    return days <= 0 ? 'aaj' : '${days}d pehle';
  }
}

// ── OEM card ─────────────────────────────────────────────────────────

class _OemCard extends ConsumerWidget {
  const _OemCard({required this.nowMs});

  final int nowMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<OemId> oem = ref.watch(oemIdProvider);

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalOemTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            l10n.survivalOemDetected(oem.valueOrNull?.label ?? '…'),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: UdaoButton(
                  label: l10n.survivalOemSetupCta,
                  size: UdaoButtonSize.sm,
                  variant: UdaoButtonVariant.limeFilled,
                  onTap: () => _openSetup(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openSetup(BuildContext context) {
    // Route hop only — fire and forget (phase-04 lesson: never
    // await navigation from build-time callbacks).
    unawaited(context.push(Routes.oemSetup));
  }
}

// ── Diagnostics export ───────────────────────────────────────────────

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({required this.onExport});

  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.survivalExportTitle, style: text.titleMedium),
          const SizedBox(height: 6),
          Text(l10n.survivalExportBody, style: text.bodyMedium),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: UdaoButton(
                  label: l10n.survivalExportCta,
                  size: UdaoButtonSize.sm,
                  variant: UdaoButtonVariant.glass,
                  onTap: () => unawaited(onExport()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
