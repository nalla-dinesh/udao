import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/date_utils.dart';

void main() {
  // All fixtures are IST-convention DateTimes (UTC-shifted wall clocks).

  group('nowIst / toIst', () {
    test('nowIst is UTC+05:30 within tolerance', () {
      final before = DateTime.now().toUtc();
      final now = IstDates.nowIst();
      final after = DateTime.now().toUtc();
      expect(now.isUtc, isTrue);
      final skew = now.difference(before.add(IstDates.istOffset));
      expect(skew >= const Duration(seconds: -5), isTrue);
      expect(skew <= after.difference(before) + const Duration(seconds: 5), isTrue);
    });

    test('toIst shifts a UTC instant', () {
      final utc = DateTime.utc(2026, 10, 27, 12, 0);
      final ist = IstDates.toIst(utc);
      expect(
        '${ist.year}-${ist.month}-${ist.day} ${ist.hour}:${ist.minute}',
        '2026-10-27 17:30',
      );
    });
  });

  group('day boundaries', () {
    final day = DateTime.utc(2026, 10, 27, 18, 45); // Tuesday evening

    test('startOfDay / endOfDay / nextDayStart', () {
      expect(IstDates.startOfDay(day), DateTime.utc(2026, 10, 27));
      expect(IstDates.endOfDay(day), DateTime.utc(2026, 10, 27, 23, 59, 59, 999));
      expect(IstDates.nextDayStart(day), DateTime.utc(2026, 10, 28));
    });

    test('endOfDay is the instant before nextDayStart', () {
      expect(
        IstDates.nextDayStart(day).difference(IstDates.endOfDay(day)),
        const Duration(milliseconds: 1),
      );
    });

    test('month rollover at day boundary', () {
      final oct31 = DateTime.utc(2026, 10, 31, 23, 30);
      expect(IstDates.nextDayStart(oct31), DateTime.utc(2026, 11, 1));
    });
  });

  group('week boundaries (Monday start)', () {
    test('Tuesday maps back to Monday', () {
      final tue = DateTime.utc(2026, 10, 27); // Tuesday
      expect(IstDates.startOfWeek(tue), DateTime.utc(2026, 10, 26));
      expect(IstDates.endOfWeek(tue), DateTime.utc(2026, 11, 1, 23, 59, 59, 999));
    });

    test('Sunday maps back to the previous Monday', () {
      final sun = DateTime.utc(2026, 11, 1); // Sunday
      expect(IstDates.startOfWeek(sun), DateTime.utc(2026, 10, 26));
    });

    test('Monday maps to itself', () {
      final mon = DateTime.utc(2026, 10, 26);
      expect(IstDates.startOfWeek(mon), DateTime.utc(2026, 10, 26));
    });

    test('week spans a year rollover', () {
      final wed = DateTime.utc(2025, 12, 31); // Wednesday
      expect(IstDates.startOfWeek(wed), DateTime.utc(2025, 12, 29));
      expect(IstDates.endOfWeek(wed), DateTime.utc(2026, 1, 4, 23, 59, 59, 999));
    });
  });

  group('month boundaries (salary windows)', () {
    test('start/end of month', () {
      final mid = DateTime.utc(2026, 10, 15);
      expect(IstDates.startOfMonth(mid), DateTime.utc(2026, 10, 1));
      expect(IstDates.endOfMonth(mid), DateTime.utc(2026, 10, 31, 23, 59, 59, 999));
    });

    test('February, non-leap', () {
      expect(
        IstDates.endOfMonth(DateTime.utc(2026, 2, 10)),
        DateTime.utc(2026, 2, 28, 23, 59, 59, 999),
      );
    });

    test('February, leap year', () {
      expect(
        IstDates.endOfMonth(DateTime.utc(2024, 2, 10)),
        DateTime.utc(2024, 2, 29, 23, 59, 59, 999),
      );
    });

    test('next/previous month across the year edge', () {
      final dec = DateTime.utc(2025, 12, 15);
      expect(IstDates.nextMonthStart(dec), DateTime.utc(2026, 1, 1));
      expect(
        IstDates.previousMonthStart(DateTime.utc(2026, 1, 15)),
        DateTime.utc(2025, 12, 1),
      );
    });
  });

  group('isSameDay / daysBetween', () {
    test('same calendar day regardless of time', () {
      expect(
        IstDates.isSameDay(
          DateTime.utc(2026, 10, 27, 0, 1),
          DateTime.utc(2026, 10, 27, 23, 59),
        ),
        isTrue,
      );
      expect(
        IstDates.isSameDay(
          DateTime.utc(2026, 10, 27, 23, 59),
          DateTime.utc(2026, 10, 28, 0, 1),
        ),
        isFalse,
      );
    });

    test('whole days, positive and negative', () {
      expect(
        IstDates.daysBetween(
          DateTime.utc(2026, 10, 27, 22, 0),
          DateTime.utc(2026, 10, 28, 2, 0),
        ),
        1,
      );
      expect(
        IstDates.daysBetween(
          DateTime.utc(2026, 10, 28),
          DateTime.utc(2026, 10, 27),
        ),
        -1,
      );
      expect(
        IstDates.daysBetween(
          DateTime.utc(2026, 10, 31),
          DateTime.utc(2026, 11, 2),
        ),
        2,
      );
    });
  });

  group('ISO formatting', () {
    test('isoDate pads', () {
      expect(IstDates.isoDate(DateTime.utc(2026, 3, 7)), '2026-03-07');
    });

    test('isoDateTime carries the IST designator', () {
      expect(
        IstDates.isoDateTime(DateTime.utc(2026, 10, 27, 18, 45, 3)),
        '2026-10-27T18:45:03+05:30',
      );
    });
  });
}
