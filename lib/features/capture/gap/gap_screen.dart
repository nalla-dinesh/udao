// phase-04
// The gap screen: renders the detector's honest report with one
// action per reason. Reached from the weekly notification deep-link
// (Phase 05 scheduling) and from Settings.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/routes.dart';
import '../../../core/result/result.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/udao_button.dart';
import '../../../core/ui/udao_card.dart';
import '../../../core/ui/udao_empty_state.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/db/dao/txn_dao.dart' show DaySourceCount;
import '../../../l10n/app_localizations.dart';
import '../capture_providers.dart' show txnDaoProvider;
import 'gap_detector.dart';

/// Dev fast-forward raw value (see gapReportProvider).
const String _gapFfRaw = String.fromEnvironment('GAP_FF_HOURS');

/// Recomputed on every visit (FutureProvider auto-disposes with the
/// route when not kept alive elsewhere).
final FutureProvider<GapReport> gapReportProvider =
    FutureProvider<GapReport>((Ref ref) async {
  final DateTime now = DateTime.now();
  final DateTime nowIst = IstDates.toIst(now);
  final DateTime toExclusive = IstDates.nextDayStart(nowIst);
  final DateTime from = IstDates.startOfDay(
    nowIst.subtract(const Duration(days: 30)),
  );

  final Result<List<DaySourceCount>> rows = await ref
      .watch(txnDaoProvider)
      .countByDaySource(fromIst: from, toIst: toExclusive);

  final List<DayCount> days = (rows.valueOrNull ?? <DaySourceCount>[])
      .map(
        (DaySourceCount r) => DayCount(
          // Wall-clock IST day from the DAO's IST-midnight bucket
          // start (see countByDaySource for the shift).
          dayStartIst: IstDates.toIst(
            DateTime.fromMillisecondsSinceEpoch(r.dayStartMs),
          ),
          notification: r.notification,
          sms: r.sms,
        ),
      )
      .toList(growable: false);

  // Dev fast-forward: GAP_FF_HOURS=<n> shrinks the 48h listener
  // rule for local testing (spec's local verification script).
  final GapDetector detector = GapDetector(
    listenerStaleAfter: Duration(hours: int.tryParse(_gapFfRaw) ?? 48),
  );
  return detector.detect(now: now, days: days);
});

class GapScreen extends ConsumerWidget {
  const GapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<GapReport> report = ref.watch(gapReportProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.gapTitle)),
      body: switch (report) {
        AsyncData<GapReport>(value: final GapReport r) =>
          r.severity == GapSeverity.none
              ? UdaoEmptyState(
                  illustration: AppIcons.jar,
                  title: l10n.gapAllGoodTitle,
                  body: l10n.gapAllGoodBody,
                )
              : _reportBody(context, l10n, r),
        // Riverpod 2.x AsyncValue is not sealed — a wildcard arm keeps
        // the switch exhaustive (loading/error render nothing until
        // the provider settles).
        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _reportBody(
    BuildContext context,
    AppLocalizations l10n,
    GapReport report,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          l10n.gapIntroCopy(report.silentWeekdays),
          style: text.titleMedium,
        ),
        const SizedBox(height: 16),
        for (final GapReason reason in report.reasons)
          _reasonCard(context, l10n, report, reason),
        const SizedBox(height: 8),
        Text(
          l10n.gapBaselineCopy(report.baselinePerDay.toStringAsFixed(1)),
          style: text.bodySmall,
        ),
      ],
    );
  }

  Widget _reasonCard(
    BuildContext context,
    AppLocalizations l10n,
    GapReport report,
    GapReason reason,
  ) {
    final TextTheme text = Theme.of(context).textTheme;
    switch (reason) {
      case GapReason.weekdaySilence:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: UdaoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.gapSilenceTitle, style: text.titleMedium),
                const SizedBox(height: 6),
                Text(l10n.gapSilenceBody, style: text.bodyMedium),
                const SizedBox(height: 12),
                UdaoButton(
                  label: l10n.gapImportCta,
                  onTap: () => context.push(Routes.importStatement),
                ),
              ],
            ),
          ),
        );
      case GapReason.listenerStale:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: UdaoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(l10n.gapListenerTitle, style: text.titleMedium),
                const SizedBox(height: 6),
                Text(
                  l10n.gapListenerBody(
                    ((report.listenerSilentHours ?? 0).round()),
                  ),
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 12),
                UdaoButton(
                  label: l10n.gapListenerCta,
                  variant: UdaoButtonVariant.glass,
                  onTap: () => context.push(Routes.captureGate),
                ),
              ],
            ),
          ),
        );
    }
  }
}
