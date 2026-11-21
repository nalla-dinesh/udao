// phase-05
// Workmanager wiring for the two DART background jobs (ADR-0006).
//
//   NightlySweepTask — daily in the 01:00–04:00 IST window
//     (best-effort: WorkManager periodic work is inexact by design —
//     we bias the FIRST run into the window and the period keeps
//     drifting within ±hours; battery-not-low constraint only):
//       * raw-text privacy purge (>24h) via CaptureHealthDao
//       * rollup counter row in kv (last run + rows purged)
//     (The WAL's own 7-day trim lives Kotlin-side — the background
//     isolate has no access to MainActivity-registered channels, and
//     WalWriter.sweep runs from HealthPinger; see ADR-0006.)
//
//   WeeklyGapTask — Sundays ~20:00 IST:
//       * GapDetector over the last 30 days (same feed as /gap)
//       * severity != none → gap-alert payload into kv; the NEXT app
//         open flushes it as the BAND/notification card (the
//         background isolate cannot reach the survival channel —
//         honest, documented latency, no crash risk).
//
// Everything with logic worth testing is pure: [NightlySweepLogic],
// [WeeklyGapLogic], [JobWindows] — the workmanager shell stays thin.
import 'dart:convert';

import 'package:workmanager/workmanager.dart';

import '../../../core/log/udao_logger.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/db/dao/capture_health_dao.dart';
import '../../../data/db/dao/kv_dao.dart';
import '../../../data/db/dao/txn_dao.dart';
import '../../../data/db/udao_database.dart';
import '../../capture/gap/gap_detector.dart';

/// Task names — the workmanager contract (also used by tests to pin
/// the uniqueName/taskName pair).
abstract final class BackgroundJobs {
  static const String nightlySweepUnique = 'udao-nightly-sweep-v1';
  static const String nightlySweepTask = 'udaoNightlySweepTask';
  static const String weeklyGapUnique = 'udao-weekly-gap-v1';
  static const String weeklyGapTask = 'udaoWeeklyGapTask';

  /// kv keys (versioned — bump suffix on breaking change).
  static const String kvNightlySweep = 'survival.nightlySweep.v1';
  static const String kvGapAlertPending = 'survival.gapAlertPending.v1';
}

/// The workmanager entry point. Top-level + vm:entry-point so the
/// background isolate can resolve it. NEVER throws.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? inputData) async {
    switch (task) {
      case BackgroundJobs.nightlySweepTask:
        return await NightlySweepLogic.executeWithRealDaos();
      case BackgroundJobs.weeklyGapTask:
        return await WeeklyGapLogic.executeWithRealDaos();
      default:
        return true;
    }
  });
}

/// Pure scheduling math — target instants inside the windows.
abstract final class JobWindows {
  /// Nightly target: 01:30 IST (inside the 01:00–04:00 window, with
  /// slack on both sides for WorkManager's inexactness).
  static DateTime nextNightlyTarget(DateTime nowIst) {
    final DateTime today = DateTime.utc(nowIst.year, nowIst.month, nowIst.day, 1, 30);
    return nowIst.isBefore(today) ? today : today.add(const Duration(days: 1));
  }

  /// Weekly target: Sunday 20:00 IST.
  static DateTime nextWeeklyTarget(DateTime nowIst) {
    final DateTime today = IstDates.startOfDay(nowIst);
    final int daysAhead = DateTime.sunday - today.weekday;
    DateTime target = today.add(Duration(days: daysAhead)).add(
          const Duration(hours: 20),
        );
    if (!target.isAfter(nowIst)) {
      target = target.add(const Duration(days: 7));
    }
    return target;
  }

  static Duration delayUntil(DateTime nowIst, DateTime target) {
    final Duration d = target.difference(nowIst);
    return d.isNegative ? Duration.zero : d;
  }
}

/// Nightly sweep — decision core pure, DAO calls isolated.
abstract final class NightlySweepLogic {
  /// Rows strictly older than this get their raw_text blanked.
  /// Boundary: exactly-24h-old rows SURVIVE (only < cutoff dies).
  static DateTime rawTextCutoff(DateTime now) => now.subtract(const Duration(hours: 24));

  /// kv payload: last run + what it did (dashboard shows this).
  static String rollupPayload({required DateTime now, required int purgedRows}) {
    return jsonEncode(<String, Object?>{
      'lastRunAt': now.millisecondsSinceEpoch,
      'purgedRows': purgedRows,
    });
  }

  /// Production entry (background isolate). Never throws — false
  /// makes WorkManager retry with the registered exponential backoff.
  static Future<bool> executeWithRealDaos() async {
    try {
      final UdaoDatabase db = UdaoDatabase.instance;
      final CaptureHealthDao healthDao = CaptureHealthDao(db.db);
      final KvDao kv = KvDao(db.db);
      final DateTime now = DateTime.now();
      final int purged =
          (await healthDao.purgeRawTextOlderThan(rawTextCutoff(now))).valueOrNull ?? 0;
      await kv.set(
        BackgroundJobs.kvNightlySweep,
        rollupPayload(now: now, purgedRows: purged),
      );
      return true;
    } on Object catch (e, s) {
      udaoLog.error('nightly sweep failed', error: e);
      udaoLog.fatal('nightly sweep stack', error: s);
      return false;
    }
  }
}

/// Weekly gap job — report → pending-alert payload.
abstract final class WeeklyGapLogic {
  /// The payload the dashboard flushes as a notification + card.
  /// severity none → null (nothing to nag about).
  static String? gapAlertPayload({required DateTime now, required GapReport report}) {
    if (report.severity == GapSeverity.none) {
      return null;
    }
    return jsonEncode(<String, Object?>{
      'generatedAt': now.millisecondsSinceEpoch,
      'severity': report.severity.name,
      'silentWeekdays': report.silentWeekdays,
      'listenerSilentHours': report.listenerSilentHours,
      'reasons': <String>[for (final GapReason r in report.reasons) r.code],
    });
  }

  /// Production entry (background isolate).
  static Future<bool> executeWithRealDaos() async {
    try {
      final UdaoDatabase db = UdaoDatabase.instance;
      final TxnDao txnDao = TxnDao(db.db);
      final KvDao kv = KvDao(db.db);

      final DateTime now = DateTime.now();
      final DateTime nowIst = IstDates.toIst(now);
      final DateTime toExclusive = IstDates.nextDayStart(nowIst);
      final DateTime from =
          IstDates.startOfDay(nowIst.subtract(const Duration(days: 30)));

      final List<DaySourceCount> rows =
          (await txnDao.countByDaySource(fromIst: from, toIst: toExclusive))
                  .valueOrNull ??
              <DaySourceCount>[];
      final List<DayCount> dayCounts = <DayCount>[
        for (final DaySourceCount r in rows)
          DayCount(
            dayStartIst: IstDates.toIst(
              DateTime.fromMillisecondsSinceEpoch(r.dayStartMs),
            ),
            notification: r.notification,
            sms: r.sms,
          ),
      ];
      final GapReport report =
          const GapDetector().detect(now: now, days: dayCounts);

      final String? payload = gapAlertPayload(now: now, report: report);
      if (payload != null) {
        await kv.set(BackgroundJobs.kvGapAlertPending, payload);
      } else {
        await kv.delete(BackgroundJobs.kvGapAlertPending);
      }
      return true;
    } on Object catch (e, s) {
      udaoLog.error('weekly gap job failed', error: e);
      udaoLog.fatal('weekly gap job stack', error: s);
      return false;
    }
  }
}

/// One-time init + (re)registration, called from main() AFTER the
/// data-layer warm-up — idempotent thanks to KEEP policies, so a
/// second app open never resets the schedule. try/catch-wrapped:
/// a scheduling failure must never block the app itself.
Future<void> initializeBackgroundJobs() async {
  try {
    await Workmanager().initialize(callbackDispatcher);

    final DateTime nowIst = IstDates.nowIst();

    await Workmanager().registerPeriodicTask(
      BackgroundJobs.nightlySweepUnique,
      BackgroundJobs.nightlySweepTask,
      frequency: const Duration(hours: 24),
      initialDelay: JobWindows.delayUntil(
        nowIst,
        JobWindows.nextNightlyTarget(nowIst),
      ),
      constraints: Constraints(requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
    );

    await Workmanager().registerPeriodicTask(
      BackgroundJobs.weeklyGapUnique,
      BackgroundJobs.weeklyGapTask,
      frequency: const Duration(days: 7),
      initialDelay: JobWindows.delayUntil(
        nowIst,
        JobWindows.nextWeeklyTarget(nowIst),
      ),
      constraints: Constraints(requiresBatteryNotLow: true),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
    );
  } on Object catch (e, s) {
    udaoLog.error('background jobs init failed', error: e);
    udaoLog.fatal('background jobs init stack', error: s);
  }
}
