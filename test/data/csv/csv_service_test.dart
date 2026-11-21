// phase-02
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/csv/csv_service.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/txn.dart';

import '../db/test_db.dart' as helper;

Txn _t(String id, int paise, {String merchant = 'Swiggy', DateTime? at}) {
  final DateTime t = at ?? DateTime(2026, 10, 27, 18, 45);
  return Txn(
    id: id,
    amount: Money(paise),
    direction: TxnDirection.debit,
    source: TxnSource.sms,
    rawText: 'raw',
    merchantRaw: merchant,
    merchantClean: merchant,
    bankOrApp: 'hdfc',
    refNo: '512345678901',
    occurredAt: t,
    capturedAt: t,
    confidence: 0.9,
    dedupKey: 'dk-$id',
  );
}

void main() {
  late UdaoDatabase db;
  late CsvService csv;

  setUp(() async {
    db = await helper.createTestDb();
    csv = CsvService(db);
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  test('escape quotes RFC-4180 style', () {
    expect(CsvService.escape('plain'), 'plain');
    expect(CsvService.escape('has,comma'), '"has,comma"');
    expect(CsvService.escape('say "hi"'), '"say ""hi"""');
    expect(CsvService.escape('line\nbreak'), '"line\nbreak"');
  });

  test('parseCsv round-trips escaped cells', () {
    final List<List<String>> rows = CsvService.parseCsv(
      CsvService.toCsv(<Txn>[]),
    );
    expect(rows.single, CsvService.header);
    final List<List<String>> parsed = CsvService.parseCsv(
      'a,"b,1","c""d"\r\n"e,f",g,h\r\n',
    );
    expect(parsed, <List<String>>[
      <String>['a', 'b,1', 'c"d'],
      <String>['e,f', 'g', 'h'],
    ]);
  });

  test('exportCsv writes a parseable file with all rows', () async {
    final TxnDao dao = TxnDao(db.db);
    for (int i = 0; i < 5; i++) {
      await dao.upsertByDedupKey(
        _t('t$i', 1000 + i, at: DateTime(2026, 10, 27, 18, 40 + i)),
      );
    }
    final String? path = (await csv.exportCsv()).valueOrNull;
    expect(path, isNotNull);
    final File f = File(path!);
    expect(await f.exists(), isTrue);
    final List<List<String>> rows = CsvService.parseCsv(f.readAsStringSync());
    expect(rows.length, 6); // header + 5
    expect(rows.first, CsvService.header);
    expect(rows[1][0], '2026-10-27');
    // page() is newest-first (occurred_at DESC, id DESC): t4 (18:44)
    // leads, t0 (18:40) closes.
    expect(rows[1][1], '18:44');
    expect(rows[1][2], '10.04');
    expect(rows[5][2], '10.00');
    expect(rows[1][4], 'Swiggy');
    addTearDown(f.delete);
  });

  test('exportCsv honours the window filter', () async {
    final TxnDao dao = TxnDao(db.db);
    await dao.upsertByDedupKey(_t('in', 100));
    await dao.upsertByDedupKey(
      _t('out', 100).copyWith(
        occurredAt: DateTime(2025, 1, 1),
        capturedAt: DateTime(2025, 1, 1),
      ),
    );
    final String? path = (await csv.exportCsv(
      from: DateTime(2026, 1, 1),
      to: DateTime(2027, 1, 1),
    ))
        .valueOrNull;
    final List<List<String>> rows =
        CsvService.parseCsv(File(path!).readAsStringSync());
    expect(rows.length, 2); // header + 1
    addTearDown(() => File(path).delete());
  });

  test('merchant with comma survives the round-trip', () async {
    final TxnDao dao = TxnDao(db.db);
    await dao.upsertByDedupKey(_t('t1', 100, merchant: 'Kirana, General'));
    final String? path = (await csv.exportCsv()).valueOrNull;
    final List<List<String>> rows =
        CsvService.parseCsv(File(path!).readAsStringSync());
    expect(rows[1][4], 'Kirana, General');
    addTearDown(() => File(path).delete());
  });

  test('rupees formatting: paise to decimal string', () async {
    final TxnDao dao = TxnDao(db.db);
    await dao.upsertByDedupKey(_t('t1', 14850));
    final String? path = (await csv.exportCsv()).valueOrNull;
    final List<List<String>> rows =
        CsvService.parseCsv(File(path!).readAsStringSync());
    expect(rows[1][2], '148.50');
    addTearDown(() => File(path).delete());
  });
}
