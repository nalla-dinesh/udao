// phase-02
// Extracts the txn timestamp from Indian bank-SMS date hints
// (`on 28-10-26`, `on 28/10/2026`, `at 18:45:03`).
import 'package:udao/core/utils/date_utils.dart';

abstract final class DateHints {
  static final RegExp _dmy = RegExp(
    r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b',
  );
  static final RegExp _hms = RegExp(r'\b(\d{1,2}):(\d{2})(?::(\d{2}))?\b');

  /// Resolves the txn moment: a date hint plus optional time hint,
  /// falling back to [receivedAt] (same-time, same-day) when absent.
  /// A hint on the same date as [receivedAt] keeps the receive clock
  /// (more precise than the SMS's often-missing time).
  static DateTime resolve(String text, DateTime receivedAt) {
    final RegExpMatch? d = _dmy.firstMatch(text);
    if (d == null) {
      return receivedAt;
    }
    final int day = int.parse(d.group(1)!);
    final int month = int.parse(d.group(2)!);
    final String yearStr = d.group(3)!;
    int year = int.parse(yearStr);
    if (yearStr.length <= 2) {
      year += 2000;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31 || year < 2000) {
      return receivedAt;
    }
    final RegExpMatch? t = _hms.firstMatch(text);
    final DateTime hinted = DateTime(
      year,
      month,
      day,
      t == null ? 12 : int.parse(t.group(1)!),
      t == null ? 0 : int.parse(t.group(2)!),
      t == null ? 0 : int.parse(t.group(3) ?? '0'),
    );
    if (IstDates.isoDate(hinted) == IstDates.isoDate(receivedAt)) {
      return receivedAt;
    }
    return hinted;
  }
}
