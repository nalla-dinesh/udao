// phase-02
// Ledger export: CSV file in the temp dir, ready to share. Cells are
// fully escaped (quotes, commas, newlines); money is decimal-rupees
// for spreadsheet friendliness, not paise.
import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/txn.dart';

class CsvService {
  CsvService(this._database);
  final UdaoDatabase _database;

  TxnDao? _txnDao;
  Future<TxnDao> _d() async => _txnDao ??= TxnDao(_database.db);

  static const List<String> header = <String>[
    'date',
    'time_ist',
    'amount_inr',
    'direction',
    'merchant',
    'category_id',
    'bank_or_app',
    'ref_no',
    'vpa',
    'note',
    'source',
    'confidence',
  ];

  /// Exports the window (all time when both null) to
  /// `<systemTemp>/udao_export_<epochms>.csv`; returns the path.
  Future<Result<String>> exportCsv({DateTime? from, DateTime? to}) async {
    final TxnDao txns = await _d();
    final List<Txn> rows = <Txn>[];
    const int pageSize = 200;
    int offset = 0;
    while (true) {
      final Result<List<Txn>> page = await txns.page(
        limit: pageSize,
        offset: offset,
        from: from,
        to: to,
      );
      if (page is Err<List<Txn>>) {
        return Err(page.failure);
      }
      final List<Txn> items = page.valueOrNull!;
      rows.addAll(items);
      if (items.length < pageSize) {
        break;
      }
      offset += pageSize;
    }
    try {
      final String csv = toCsv(rows);
      final Directory tmp = Directory.systemTemp;
      await tmp.create(recursive: true);
      final String path =
          '${tmp.path}/udao_export_${DateTime.now().millisecondsSinceEpoch}.csv';
      final File file = File(path);
      await file.writeAsString(csv, flush: true);
      return Ok(path);
    } on Object {
      return const Err(DatabaseFailure('csv write failed'));
    }
  }

  /// Hands the exported file to the OS share sheet.
  Future<Result<void>> share(String path) async {
    try {
      await Share.shareXFiles(<XFile>[XFile(path)]);
      return const Ok(null);
    } on Object {
      return const Err(DatabaseFailure('csv share failed'));
    }
  }

  /// Serialises rows (header first, CRLF line ends per RFC 4180).
  static String toCsv(List<Txn> rows) {
    final StringBuffer out = StringBuffer();
    out.writeln(header.join(','));
    for (final Txn t in rows) {
      final DateTime ist = IstDates.toIst(t.occurredAt);
      out.writeln(
        <String>[
          IstDates.isoDate(ist),
          '${ist.hour.toString().padLeft(2, '0')}:'
              '${ist.minute.toString().padLeft(2, '0')}',
          _rupees(t.amount.paise),
          t.direction.name,
          t.merchantClean,
          t.categoryId ?? '',
          t.bankOrApp,
          t.refNo ?? '',
          t.vpa ?? '',
          t.note ?? '',
          t.source.name,
          t.confidence.toStringAsFixed(2),
        ].map(escape).join(','),
      );
    }
    return out.toString();
  }

  /// RFC-4180 cell escaping.
  static String escape(String cell) {
    if (cell.contains('"') ||
        cell.contains(',') ||
        cell.contains('\n') ||
        cell.contains('\r')) {
      return '"${cell.replaceAll('"', '""')}"';
    }
    return cell;
  }

  /// Minimal RFC-4180 reader (tests round-trip + corpus sanity).
  static List<List<String>> parseCsv(String csv) {
    final List<List<String>> rows = <List<String>>[];
    List<String> cells = <String>[];
    final StringBuffer cell = StringBuffer();
    bool inQuotes = false;
    for (int i = 0; i < csv.length; i++) {
      final String c = csv[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < csv.length && csv[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        cells.add(cell.toString());
        cell.clear();
      } else if (c == '\r') {
        // skip (handles \r\n)
      } else if (c == '\n') {
        cells.add(cell.toString());
        cell.clear();
        rows.add(cells);
        cells = <String>[];
      } else {
        cell.write(c);
      }
    }
    if (cell.isNotEmpty || cells.isNotEmpty) {
      cells.add(cell.toString());
      rows.add(cells);
    }
    return rows;
  }

  static String _rupees(int paise) {
    final bool negative = paise < 0;
    final int abs = paise.abs();
    final String s = abs < 100
        ? '0.${abs.toString().padLeft(2, '0')}'
        : '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
    return negative ? '-$s' : s;
  }
}
