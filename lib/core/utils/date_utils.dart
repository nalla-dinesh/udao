// IST date/time helpers.
//
// IST is a fixed UTC+05:30 offset (no DST). UDAO convention: every
// "IST" [DateTime] is a **UTC-shifted wall clock** — a [DateTime] in
// UTC whose readings equal Indian local time. `DateTime.utc(2026, 10, 27)`
// therefore means "27 Oct 2026, 00:00 IST". This keeps all boundary
// math pure, deterministic and testable without a timezone database.
//
// All functions accept AND return the IST convention — garbage in,
// garbage out if you feed them local-time [DateTime]s.
abstract final class IstDates {
  static const Duration istOffset = Duration(hours: 5, minutes: 30);

  /// Current IST wall clock.
  static DateTime nowIst() => DateTime.now().toUtc().add(istOffset);

  /// Normalises any [DateTime] to the IST wall-clock convention.
  static DateTime toIst(DateTime t) => t.toUtc().add(istOffset);

  /// 00:00:00.000 of the given IST day.
  static DateTime startOfDay(DateTime ist) =>
      DateTime.utc(ist.year, ist.month, ist.day);

  /// 23:59:59.999 of the given IST day (inclusive end).
  static DateTime endOfDay(DateTime ist) =>
      DateTime.utc(ist.year, ist.month, ist.day, 23, 59, 59, 999);

  /// 00:00 of the next IST day — prefer this over [endOfDay] for
  /// exclusive DB ranges (`ts >= start AND ts < nextStart`).
  static DateTime nextDayStart(DateTime ist) =>
      startOfDay(ist).add(const Duration(days: 1));

  /// Monday 00:00 of the given IST day's week. Weeks start Monday.
  static DateTime startOfWeek(DateTime ist) =>
      startOfDay(ist).subtract(Duration(days: ist.weekday - 1));

  /// Sunday 23:59:59.999 of the given IST day's week.
  static DateTime endOfWeek(DateTime ist) =>
      endOfDay(startOfWeek(ist).add(const Duration(days: 6)));

  /// 1st of the month, 00:00.
  static DateTime startOfMonth(DateTime ist) =>
      DateTime.utc(ist.year, ist.month, 1);

  /// Last instant of the month (inclusive end).
  static DateTime endOfMonth(DateTime ist) =>
      nextMonthStart(ist).subtract(const Duration(milliseconds: 1));

  /// 1st of the next month — salary-window boundary helper.
  static DateTime nextMonthStart(DateTime ist) =>
      DateTime.utc(ist.year, ist.month + 1, 1);

  /// 1st of the previous month — salary-cycle comparisons.
  static DateTime previousMonthStart(DateTime ist) =>
      DateTime.utc(ist.year, ist.month - 1, 1);

  /// True when both timestamps fall on the same IST calendar day.
  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Whole days from `a` to `b` (negative when `b` is before `a`).
  static int daysBetween(DateTime a, DateTime b) =>
      startOfDay(b).difference(startOfDay(a)).inDays;

  /// `2026-10-27`
  static String isoDate(DateTime ist) =>
      '${ist.year.toString().padLeft(4, '0')}-${_p2(ist.month)}-${_p2(ist.day)}';

  /// `2026-10-27T18:45:03+05:30`
  static String isoDateTime(DateTime ist) =>
      '${isoDate(ist)}T${_p2(ist.hour)}:${_p2(ist.minute)}:'
      '${_p2(ist.second)}+05:30';

  static String _p2(int n) => n.toString().padLeft(2, '0');
}
