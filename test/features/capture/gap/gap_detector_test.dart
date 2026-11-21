// phase-04
// Eight gap-detector scenarios against the pure detector with an
// injected clock: normal baseline, weekday silence (watch/concern),
// dead-listener, weekend silence (never flagged), today incomplete
// (never flagged), low baseline (not remarkable), fast-forwarded
// staleness window, and fresh install (no notification history).
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/features/capture/gap/gap_detector.dart';

/// 2026-10-28 is a WEDNESDAY — weekday maths is stable in IST.
final DateTime now = DateTime.utc(2026, 10, 28, 9, 30);

DateTime istDay(int minusDays) => DateTime.utc(
      2026,
      10,
      28 - minusDays,
      0,
      0,
    );

/// Days where every weekday has 4 events, weekends 0-2.
List<DayCount> healthyDays({int silentWeekdays = 0}) {
  final List<DayCount> out = <DayCount>[];
  int silenced = 0;
  for (int i = 1; i <= 30; i++) {
    final DateTime d = istDay(i);
    final bool weekend =
        d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
    int n = 4;
    int s = 1;
    if (weekend) {
      n = 1;
      s = 0;
    } else if (silenced < silentWeekdays &&
        i > 3) { // keep recent 3 days populated
      n = 0;
      s = 0;
      silenced++;
    }
    out.add(DayCount(dayStartIst: d, notification: n, sms: s));
  }
  return out;
}

void main() {
  const GapDetector detector = GapDetector();

  test('1. healthy baseline: no gaps', () {
    final GapReport r =
        detector.detect(now: now, days: healthyDays());
    expect(r.severity, GapSeverity.none);
    expect(r.reasons, isEmpty);
    expect(r.baselinePerDay, greaterThanOrEqualTo(3));
  });

  test('2. one silent weekday: watch + import action', () {
    final GapReport r = detector.detect(
      now: now,
      days: healthyDays(silentWeekdays: 1),
    );
    expect(r.severity, GapSeverity.watch);
    expect(r.reasons, contains(GapReason.weekdaySilence));
    expect(r.actions, contains(GapAction.importStatement));
    expect(r.silentWeekdays, 1);
  });

  test('3. two silent weekdays: concern', () {
    final GapReport r = detector.detect(
      now: now,
      days: healthyDays(silentWeekdays: 2),
    );
    expect(r.severity, GapSeverity.concern);
    expect(r.silentWeekdays, 2);
  });

  test('4. dead listener: SMS alive, notifications stale >48h', () {
    final List<DayCount> days = healthyDays();
    // Kill notifications for the last 3 days (72h), keep SMS.
    for (int i = 1; i <= 3; i++) {
      final DateTime d = istDay(i);
      final int idx = days.indexWhere(
        (DayCount c) => c.dayStartIst == d,
      );
      days[idx] = DayCount(dayStartIst: d, notification: 0, sms: 3);
    }
    final GapReport r = detector.detect(now: now, days: days);
    expect(r.reasons, contains(GapReason.listenerStale));
    expect(r.severity, GapSeverity.concern);
    expect(r.actions, contains(GapAction.checkListener));
    expect(r.listenerSilentHours, greaterThan(48));
  });

  test('5. weekend silence alone is never flagged', () {
    final List<DayCount> days = healthyDays();
    for (int i = 1; i <= 30; i++) {
      final DateTime d = istDay(i);
      final bool weekend = d.weekday == DateTime.saturday ||
          d.weekday == DateTime.sunday;
      if (weekend) {
        final int idx = days.indexWhere(
          (DayCount c) => c.dayStartIst == d,
        );
        days[idx] = DayCount(dayStartIst: d, notification: 0, sms: 0);
      }
    }
    final GapReport r = detector.detect(now: now, days: days);
    expect(r.severity, GapSeverity.none);
  });

  test('6. today is incomplete: never counted', () {
    final GapReport r = detector.detect(
      now: now,
      days: <DayCount>[
        // Only "today" is populated and the last 30 days silent —
        // today must be excluded from the silence count, so the
        // baseline (from today alone) is 1 < 3 → nothing flagged.
        DayCount(dayStartIst: istDay(0), notification: 2, sms: 0),
      ],
    );
    expect(r.severity, GapSeverity.none);
  });

  test('7. low baseline: weekday silence is not remarkable', () {
    final List<DayCount> days = <DayCount>[
      for (int i = 1; i <= 10; i++)
        DayCount(dayStartIst: istDay(i), notification: 1, sms: 0),
    ];
    final GapReport r = detector.detect(now: now, days: days);
    expect(r.baselinePerDay, 1);
    expect(r.severity, GapSeverity.none);
  });

  test('8. fast-forward: dev flag shrinks the staleness window', () {
    const GapDetector ff = GapDetector(
      listenerStaleAfter: Duration(hours: 4),
    );
    final List<DayCount> days = healthyDays();
    // Notifications dead for exactly 48h (only yesterday silenced);
    // SMS stayed alive on yesterday.
    final DateTime d = istDay(1);
    final int idx =
        days.indexWhere((DayCount c) => c.dayStartIst == d);
    days[idx] = DayCount(dayStartIst: d, notification: 0, sms: 3);
    final GapReport normal =
        const GapDetector().detect(now: now, days: days);
    final GapReport fast = ff.detect(now: now, days: days);
    expect(
      normal.reasons,
      isNot(contains(GapReason.listenerStale)),
      reason: 'exactly 48h is not > 48h',
    );
    expect(fast.reasons, contains(GapReason.listenerStale));
  });

  test('fresh install (no notification history) is not a dead listener',
      () {
    final List<DayCount> days = <DayCount>[
      for (int i = 1; i <= 5; i++)
        DayCount(dayStartIst: istDay(i), notification: 0, sms: 2),
    ];
    final GapReport r = detector.detect(now: now, days: days);
    expect(r.reasons, isNot(contains(GapReason.listenerStale)));
  });

  test('day counts bucket by IST wall clock', () {
    // 2026-10-25 is a Sunday; a count on it must read weekend.
    final DayCount sunday = DayCount(
      dayStartIst: DateTime.utc(2026, 10, 25),
      notification: 0,
      sms: 0,
    );
    expect(sunday.isWeekend, isTrue);
    expect(IstDates.toIst(now).weekday, DateTime.wednesday);
  });
}
