// phase-04
// The bank-agnostic outcome of parsing one statement (PDF text or
// CSV): rows plus an honest unparsed bucket. Rows that fail a
// profile's shape are NOT guessed into the ledger — they surface in
// the review screen so the user knows exactly what was skipped.
import 'package:udao/data/models/txn.dart' show TxnDirection;

/// One parsed statement line, pre-ledger.
class StatementRow {
  const StatementRow({
    required this.date,
    required this.narration,
    required this.amountPaise,
    required this.direction,
    this.refNo,
    this.balancePaise,
    this.lineNumber = 0,
  });

  /// Value date, IST. Statements are date-granular — no time.
  final DateTime date;

  /// Raw narration / description column.
  final String narration;

  /// Txn amount in paise (always > 0).
  final int amountPaise;

  final TxnDirection direction;

  /// Bank reference (UTR/chq) if present.
  final String? refNo;

  /// Closing balance after the row, if present.
  final int? balancePaise;

  /// 1-based line in the source text (review screen jumps).
  final int lineNumber;
}

/// Why one line landed in the unparsed bucket (shown verbatim in the
/// summary — never silently swallowed).
enum StatementSkipReason {
  directionUnknown('direction_unknown'),
  shapeUnknown('shape_unknown'),
  zeroAmount('zero_amount'),
  badDate('bad_date');

  const StatementSkipReason(this.code);
  final String code;
}

/// A line that looked like a txn but could not be parsed safely.
class SkippedLine {
  const SkippedLine(this.lineNumber, this.reason, this.text);

  final int lineNumber;
  final StatementSkipReason reason;
  final String text;
}

/// Full parse outcome for one statement document.
class StatementParse {
  const StatementParse({
    required this.bankId,
    required this.rows,
    required this.skipped,
  });

  /// Profile id (`hdfc`, `sbi`, …) or `udao-csv` / `bank-csv`.
  final String bankId;
  final List<StatementRow> rows;
  final List<SkippedLine> skipped;

  /// Oldest..newest row dates (null when no rows).
  (DateTime?, DateTime)? get dateRange {
    if (rows.isEmpty) {
      return null;
    }
    final List<DateTime> dates = rows.map((StatementRow r) => r.date).toList()
      ..sort();
    return (dates.first, dates.last);
  }
}
