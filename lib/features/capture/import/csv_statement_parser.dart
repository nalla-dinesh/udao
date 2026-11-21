// phase-04
// CSV import for the review screen's CSV tab. Scope is deliberate:
// UDAO's OWN export format (Phase-02 CsvService) — that is the
// guaranteed, byte-stable contract (it round-trips exports back into
// the ledger and is what the duplicate-import acceptance test uses).
// Arbitrary bank CSVs are NOT guessed at: their column dialects are
// unbounded, and the 5 supported banks are covered by the PDF tab.
// Honest failure: `Err(ParseFailure('unknown_csv_format'))`.
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/txn.dart' show TxnDirection;

import 'statement_row.dart';

abstract final class CsvStatementParser {
  /// The exact export header (CsvService.header) — order-stable.
  static const List<String> _udaoHeader = <String>[
    'date', 'time_ist', 'amount_inr', 'direction', 'merchant',
    'category_id', 'bank_or_app', 'ref_no', 'vpa', 'note', 'source',
    'confidence',
  ];

  static Result<StatementParse> parse(String csv) {
    final List<List<String>> records = _records(csv);
    if (records.length < 2) {
      return const Err(ParseFailure('unknown_csv_format'));
    }
    final List<String> header =
        records.first.map((String h) => h.trim().toLowerCase()).toList();
    if (!_sameHeader(header)) {
      return const Err(ParseFailure('unknown_csv_format'));
    }

    final List<StatementRow> rows = <StatementRow>[];
    final List<SkippedLine> skipped = <SkippedLine>[];
    for (int i = 1; i < records.length; i++) {
      final List<String> cells = records[i];
      if (cells.length < _udaoHeader.length) {
        continue; // blank line tail
      }
      final DateTime? date = _parseDate(cells[header.indexOf('date')]);
      final Money? amount =
          Money.tryParse(cells[header.indexOf('amount_inr')]);
      final String directionWord = cells[header.indexOf('direction')].trim();
      final TxnDirection? direction = directionWord == 'debit'
          ? TxnDirection.debit
          : directionWord == 'credit'
              ? TxnDirection.credit
              : null;
      if (date == null || amount == null || amount.paise <= 0 ||
          direction == null) {
        skipped.add(
          SkippedLine(
            i + 1,
            StatementSkipReason.directionUnknown,
            cells.join(','),
          ),
        );
        continue;
      }
      final String merchant = cells[header.indexOf('merchant')].trim();
      final String ref = cells[header.indexOf('ref_no')].trim();
      rows.add(
        StatementRow(
          date: date,
          narration: merchant,
          amountPaise: amount.paise,
          direction: direction,
          refNo: ref.isEmpty ? null : ref,
        ),
      );
    }
    return Ok(
      StatementParse(bankId: 'udao-csv', rows: rows, skipped: skipped),
    );
  }

  static bool _sameHeader(List<String> header) {
    if (header.length != _udaoHeader.length) {
      return false;
    }
    for (int i = 0; i < header.length; i++) {
      if (header[i] != _udaoHeader[i]) {
        return false;
      }
    }
    return true;
  }

  /// RFC-4180 record parse (quotes, embedded commas/newlines).
  static List<List<String>> _records(String csv) {
    final List<List<String>> out = <List<String>>[];
    List<String>? current;
    final StringBuffer cell = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < csv.length; i++) {
      final String ch = csv[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < csv.length && csv[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        (current ??= <String>[]).add(cell.toString());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < csv.length && csv[i + 1] == '\n') {
          i++;
        }
        if (cell.isNotEmpty || current != null) {
          (current ??= <String>[]).add(cell.toString());
          out.add(current);
          current = null;
          cell.clear();
        }
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || current != null) {
      (current ??= <String>[]).add(cell.toString());
      out.add(current);
    }
    return out;
  }

  /// `YYYY-MM-DD` (export format) → IST date at noon (same ±12h
  /// day-window convention as the PDF parser).
  static DateTime? _parseDate(String raw) {
    final RegExpMatch? m =
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
    if (m == null) {
      return null;
    }
    return DateTime.utc(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      6,
      30,
    );
  }
}
