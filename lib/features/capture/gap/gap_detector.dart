// phase-04
// The capture-gap detector — pure logic, injectable clock, no IO:
// the WorkManager job (Phase 05 scheduling) and the gap screen both
// call [GapDetector.detect] with per-day counts from the ledger.
//
// Heuristics (spec T5):
//   (a) a WEEKDAY with zero captured txns while the user's 30-day
//       baseline is ≥3/day → flag. Two+ such weekdays = concern.
//   (b) SMS-source txns exist but notification-source stopped >48h
//       ago → the listener is probably dead.
//   (c) weekend silence is normal — never flagged.
//   (d) today is incomplete — never flagged.
//
// The detector never fabricates certainty: it reports reasons and
// suggested actions; the copy stays humble ("lag raha hai").
import 'package:udao/core/utils/date_utils.dart';

/// Per-day capture aggregates (one per IST day).
class DayCount {
  const DayCount({
    required this.dayStartIst,
    required this.notification,
    required this.sms,
  });

  /// IST midnight epoch-ms of this day.
  final DateTime dayStartIst;
  final int notification;
  final int sms;

  int get total => notification + sms;

  bool get isWeekend =>
      dayStartIst.weekday == DateTime.saturday ||
      dayStartIst.weekday == DateTime.sunday;
}

enum GapSeverity { none, watch, concern }

enum GapReason {
  weekdaySilence('weekday_silence'),
  listenerStale('listener_stale');

  const GapReason(this.code);
  final String code;
}

enum GapAction { importStatement, checkListener }

class GapReport {
  const GapReport({
    required this.severity,
    required this.reasons,
    required this.actions,
    required this.silentWeekdays,
    required this.baselinePerDay,
    required this.listenerSilentHours,
  });

  final GapSeverity severity;
  final List<GapReason> reasons;
  final List<GapAction> actions;

  /// Weekdays (last 14, excl. today) with zero captured txns.
  final int silentWeekdays;

  /// Mean txns/day over active days of the 30-day window.
  final double baselinePerDay;

  /// Hours since the last notification-source txn (null when no
  /// notification txn exists in the window at all — a fresh install
  /// is not a dead listener).
  final double? listenerSilentHours;
}

class GapDetector {
  const GapDetector({
    this.listenerStaleAfter = const Duration(hours: 48),
    this.silentLookbackDays = 14,
    this.baselineMinPerDay = 3,
  });

  /// Listener rule (b) threshold — a dart-define/dev flag can pass a
  /// smaller value to fast-forward local testing.
  final Duration listenerStaleAfter;

  /// How many recent days rule (a) scans.
  final int silentLookbackDays;

  /// Below this baseline, weekday silence is not remarkable.
  final int baselineMinPerDay;

  GapReport detect({
    required DateTime now,
    required List<DayCount> days,
  }) {
    final DateTime nowIst = IstDates.toIst(now);
    final DateTime todayStart = IstDates.startOfDay(nowIst);

    final Map<int, DayCount> byDay = <int, DayCount>{
      for (final DayCount d in days)
        d.dayStartIst.millisecondsSinceEpoch ~/ 86400000: d,
    };

    // ---- baseline (rule a precondition) -----------------------------
    // Active days only: zero days in the baseline window would drag
    // the mean down and mask exactly the silence we are hunting.
    final List<DayCount> window = days
        .where(
          (DayCount d) =>
              d.dayStartIst.isAfter(
                todayStart.subtract(const Duration(days: 30)),
              ) &&
              d.dayStartIst.isBefore(todayStart),
        )
        .toList();
    final List<DayCount> active =
        window.where((DayCount d) => d.total > 0).toList();
    final double baseline = active.isEmpty
        ? 0
        : active
                .map((DayCount d) => d.total)
                .reduce((int a, int b) => a + b) /
            active.length;

    // ---- rule (a): weekday silence -----------------------------------
    int silentWeekdays = 0;
    if (baseline >= baselineMinPerDay) {
      for (int i = 1; i <= silentLookbackDays; i++) {
        final DateTime day =
            todayStart.subtract(Duration(days: i));
        if (day.weekday == DateTime.saturday ||
            day.weekday == DateTime.sunday) {
          continue; // (c) weekends are allowed to be silent
        }
        final DayCount? count =
            byDay[day.millisecondsSinceEpoch ~/ 86400000];
        if (count == null || count.total == 0) {
          silentWeekdays++;
        }
      }
    }

    // ---- rule (b): listener staleness --------------------------------
    double? listenerSilentHours;
    bool smsRecent = false;
    // Day-granular counts cannot express "SMS 4h ago", so the SMS
    // liveness check pads the window by one day: with the default
    // 48h rule, SMS on yesterday or the day before counts as alive;
    // with a fast-forwarded dev window, yesterday still counts.
    final DateTime smsCutoff =
        todayStart.subtract(listenerStaleAfter + const Duration(days: 1));
    for (final DayCount d in window) {
      if (d.sms > 0 && d.dayStartIst.isAfter(smsCutoff)) {
        smsRecent = true;
      }
    }
    DateTime? lastNotif;
    for (final DayCount d in window) {
      if (d.notification > 0 &&
          (lastNotif == null || d.dayStartIst.isAfter(lastNotif))) {
        lastNotif = d.dayStartIst;
      }
    }
    bool listenerStale = false;
    if (lastNotif != null && smsRecent) {
      final Duration silence = todayStart.difference(lastNotif);
      if (silence > listenerStaleAfter) {
        listenerSilentHours = silence.inMinutes / 60;
        listenerStale = true;
      }
    }

    // ---- assemble -----------------------------------------------------
    final List<GapReason> reasons = <GapReason>[];
    if (silentWeekdays > 0) {
      reasons.add(GapReason.weekdaySilence);
    }
    if (listenerStale) {
      reasons.add(GapReason.listenerStale);
    }

    GapSeverity severity = GapSeverity.none;
    if (silentWeekdays >= 2 || listenerStale) {
      severity = GapSeverity.concern;
    } else if (silentWeekdays == 1) {
      severity = GapSeverity.watch;
    }

    final List<GapAction> actions = <GapAction>[
      if (silentWeekdays > 0) GapAction.importStatement,
      if (listenerStale) GapAction.checkListener,
    ];

    return GapReport(
      severity: severity,
      reasons: reasons,
      actions: actions,
      silentWeekdays: silentWeekdays,
      baselinePerDay: baseline,
      listenerSilentHours: listenerSilentHours,
    );
  }
}
