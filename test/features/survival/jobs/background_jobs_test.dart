// phase-05
// Background-job scheduling math + payloads, pinned pure (no
// workmanager, no DB): nightly 01:30 IST targeting, Sunday-20:00
// weekly targeting, the 24h raw-text cutoff boundary, rollup and
// gap-alert payload shapes, and the locked workmanager contract
// strings (unique names + kv keys).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/features/capture/gap/gap_detector.dart';
import 'package:udao/features/survival/jobs/background_jobs.dart';

void main() {
  group('JobWindows.nextNightlyTarget (01:30 IST)', () {
    test('00:30 → today 01:30', () {
      final DateTime t = JobWindows.nextNightlyTarget(
        DateTime.utc(2026, 10, 28, 0, 30),
      );
      expect(t, DateTime.utc(2026, 10, 28, 1, 30));
    });

    test('01:29 → today 01:30', () {
      final DateTime t = JobWindows.nextNightlyTarget(
        DateTime.utc(2026, 10, 28, 1, 29),
      );
      expect(t, DateTime.utc(2026, 10, 28, 1, 30));
    });

    test('01:30 exactly → tomorrow (not zero-delay)', () {
      final DateTime t = JobWindows.nextNightlyTarget(
        DateTime.utc(2026, 10, 28, 1, 30),
      );
      expect(t, DateTime.utc(2026, 10, 29, 1, 30));
    });

    test('02:00 (already inside window tail) → tomorrow 01:30', () {
      final DateTime t = JobWindows.nextNightlyTarget(
        DateTime.utc(2026, 10, 28, 2, 0),
      );
      expect(t, DateTime.utc(2026, 10, 29, 1, 30));
    });

    test('23:45 → tomorrow 01:30', () {
      final DateTime t = JobWindows.nextNightlyTarget(
        DateTime.utc(2026, 10, 28, 23, 45),
      );
      expect(t, DateTime.utc(2026, 10, 29, 1, 30));
    });
  });

  group('JobWindows.nextWeeklyTarget (Sunday 20:00 IST)', () {
    test('Wednesday → coming Sunday 20:00', () {
      // 2026-10-28 is a Wednesday.
      final DateTime t = JobWindows.nextWeeklyTarget(
        DateTime.utc(2026, 10, 28, 12, 0),
      );
      expect(t, DateTime.utc(2026, 11, 1, 20, 0));
      expect(t.weekday, DateTime.sunday);
    });

    test('Sunday 19:00 → today 20:00', () {
      final DateTime t = JobWindows.nextWeeklyTarget(
        DateTime.utc(2026, 11, 1, 19, 0),
      );
      expect(t, DateTime.utc(2026, 11, 1, 20, 0));
    });

    test('Sunday 21:00 → next Sunday 20:00', () {
      final DateTime t = JobWindows.nextWeeklyTarget(
        DateTime.utc(2026, 11, 1, 21, 0),
      );
      expect(t, DateTime.utc(2026, 11, 8, 20, 0));
    });
  });

  test('delayUntil clamps negatives to zero', () {
    expect(
      JobWindows.delayUntil(
        DateTime.utc(2026, 10, 28, 5, 0),
        DateTime.utc(2026, 10, 28, 1, 30),
      ),
      Duration.zero,
    );
  });

  group('NightlySweepLogic', () {
    test('raw-text cutoff is exactly 24h back', () {
      final DateTime now = DateTime.utc(2026, 10, 28, 3, 0, 0);
      final DateTime cutoff = NightlySweepLogic.rawTextCutoff(now);
      expect(cutoff, DateTime.utc(2026, 10, 27, 3, 0, 0));
      // Boundary semantics: the DAO purge is `received_at < cutoff`,
      // so a row aged exactly 24h SURVIVES; one aged 24h+1ms dies.
      expect(
        cutoff.isBefore(
          DateTime.utc(2026, 10, 27, 3, 0, 0).add(
            const Duration(milliseconds: 1),
          ),
        ),
        isTrue,
      );
    });

    test('rollup payload shape (kv mirror for the dashboard)', () {
      final String json = NightlySweepLogic.rollupPayload(
        now: DateTime.utc(2026, 10, 28, 3, 0),
        purgedRows: 42,
      );
      final Map<String, Object?> decoded =
          jsonDecode(json) as Map<String, Object?>;
      expect(decoded['purgedRows'], 42);
      expect(decoded['lastRunAt'], isA<int>());
    });
  });

  group('WeeklyGapLogic.gapAlertPayload', () {
    GapReport report(GapSeverity severity, {double? silentHours}) => GapReport(
          severity: severity,
          reasons: const <GapReason>[GapReason.weekdaySilence],
          actions: const <GapAction>[GapAction.checkListener],
          silentWeekdays: 3,
          baselinePerDay: 4.2,
          listenerSilentHours: silentHours,
        );

    test('severity none → no payload (no nag)', () {
      expect(
        WeeklyGapLogic.gapAlertPayload(
          now: DateTime.utc(2026, 10, 28),
          report: report(GapSeverity.none),
        ),
        isNull,
      );
    });

    test('watch severity → payload with reasons', () {
      final String? raw = WeeklyGapLogic.gapAlertPayload(
        now: DateTime.utc(2026, 10, 28),
        report: report(GapSeverity.watch),
      );
      expect(raw, isNotNull);
      final Map<String, Object?> decoded =
          jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['severity'], 'watch');
      expect(decoded['silentWeekdays'], 3);
      expect(decoded['reasons'], contains('weekday_silence'));
    });

    test('concern severity with stale listener hours', () {
      final String? raw = WeeklyGapLogic.gapAlertPayload(
        now: DateTime.utc(2026, 10, 28),
        report: report(GapSeverity.concern, silentHours: 71.5),
      );
      final Map<String, Object?> decoded =
          jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['listenerSilentHours'], 71.5);
    });
  });

  group('workmanager contract strings (locked)', () {
    test('task + unique names stay stable', () {
      expect(BackgroundJobs.nightlySweepUnique, 'udao-nightly-sweep-v1');
      expect(BackgroundJobs.nightlySweepTask, 'udaoNightlySweepTask');
      expect(BackgroundJobs.weeklyGapUnique, 'udao-weekly-gap-v1');
      expect(BackgroundJobs.weeklyGapTask, 'udaoWeeklyGapTask');
    });

    test('kv keys are versioned', () {
      expect(BackgroundJobs.kvNightlySweep, 'survival.nightlySweep.v1');
      expect(
        BackgroundJobs.kvGapAlertPending,
        'survival.gapAlertPending.v1',
      );
    });
  });

  test('IST convention sanity for the window math', () {
    // The job file's window math is pure UTC-shifted IST (IstDates
    // convention) — pin one anchor so nobody "fixes" it to local time.
    final DateTime ist = IstDates.toIst(DateTime.utc(2026, 10, 28, 20, 0));
    expect(ist, DateTime.utc(2026, 10, 29, 1, 30));
  });
}
