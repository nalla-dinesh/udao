// phase-04
// Import service: parse → preview (nothing written) → confirm (all
// or nothing), plus the dedup legs — the spec's overlapping-range
// double-count guarantee, exercised against a real (FFI) database.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/csv/csv_service.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/features/capture/import/csv_statement_parser.dart';
import 'package:udao/features/capture/import/statement_import_service.dart';
import 'package:udao/features/capture/import/statement_row.dart';
import 'package:udao/features/capture/ports/pdf_text_extractor.dart';

import '../../../data/db/test_db.dart';

const String hdfcText = '''
HDFC BANK LIMITED
Statement of account

01/06/26    UPI/401234567890/SWIGGY/YESB0PTX        401234567890    01/06/26    349.00    45,678.90
02/06/26    NEFT CR-HDFC0000123-ACME CORP-SALARY    123456789012    02/06/26    65,000.00    1,10,678.90
''';

/// Fake extractor — the pdfrx seam in test mode.
class _FakeExtractor implements PdfTextExtractor {
  _FakeExtractor(this.text, {this.passwordExpected});
  final String text;
  final String? passwordExpected;
  String? lastPassword;

  @override
  Future<Result<PdfExtract>> extract(String path, {String? password}) async {
    lastPassword = password;
    if (passwordExpected != null && password != passwordExpected) {
      return const Err<PdfExtract>(ParseFailure('pdf_password'));
    }
    return Ok(PdfExtract(pages: <String>[text]));
  }
}

Txn _liveSwiggyCapture() => Txn(
      id: 'live001',
      amount: const Money(34900),
      direction: TxnDirection.debit,
      source: TxnSource.notification,
      rawText: '₹349 paid to Swiggy',
      merchantRaw: 'Swiggy',
      merchantClean: 'Swiggy',
      bankOrApp: 'gpay',
      categoryId: 'cat_khaana',
      refNo: '401234567890',
      occurredAt: DateTime(2026, 6, 1, 12),
      capturedAt: DateTime(2026, 6, 1, 12),
      confidence: 0.9,
      dedupKey: 'live-key-1',
    );

void main() {
  late UdaoDatabase db;
  late TxnDao txnDao;
  late StatementImportService service;

  setUp(() async {
    db = await createTestDb();
    txnDao = TxnDao(db.db);
    service = StatementImportService(
      txnDao: txnDao,
      now: () => DateTime(2026, 10, 28, 10, 0),
    );
  });

  tearDown(() async {
    await disposeTestDb(db);
  });

  test('preview writes NOTHING to the ledger', () async {
    final Result<ImportPreview> preview = await service.previewPdf(
      '/x/hdfc.pdf',
      'hdfc.pdf',
      extractor: _FakeExtractor(hdfcText),
    );
    expect(preview, isA<Ok<ImportPreview>>());
    final ImportPreview p = preview.valueOrNull!;
    expect(p.bankId, 'hdfc');
    expect(p.rows, hasLength(2));
    expect(p.newCount, 2);
    expect(p.duplicateCount, 0);
    expect(await _count(txnDao), 0);
  });

  test('wrong password propagates; right one parses; never stored',
      () async {
    final _FakeExtractor extractor =
        _FakeExtractor(hdfcText, passwordExpected: 'secret123');
    final Result<ImportPreview> bad = await service.previewPdf(
      '/x/hdfc.pdf',
      'hdfc.pdf',
      extractor: extractor,
    );
    expect(bad, isA<Err<ImportPreview>>());
    expect((bad as Err<ImportPreview>).failure.message, 'pdf_password');

    final Result<ImportPreview> good = await service.previewPdf(
      '/x/hdfc.pdf',
      'hdfc.pdf',
      extractor: extractor,
      password: 'secret123',
    );
    expect(good, isA<Ok<ImportPreview>>());
    // The password crossed as a call argument and died there.
    expect(extractor.lastPassword, 'secret123');
  });

  test('confirm writes exactly the previewed rows', () async {
    final ImportPreview p = (await service.previewPdf(
      '/x/hdfc.pdf',
      'hdfc.pdf',
      extractor: _FakeExtractor(hdfcText),
    )).valueOrNull!;
    final Result<ImportSummary> summary = await service.confirm(p);
    expect(summary.valueOrNull!.inserted, 2);
    expect(await _count(txnDao), 2);

    final Result<List<Txn>> page = await txnDao.page(limit: 10);
    final List<Txn> rows = page.valueOrNull!;
    expect(rows.every((Txn t) => t.source == TxnSource.pdf), isTrue);
    expect(rows.every((Txn t) => t.confidence == 0.98), isTrue);
    expect(
      rows.every((Txn t) => t.occurredAt.hour == 12),
      isTrue,
      reason: 'statement rows land at noon IST',
    );
  });

  test('re-import of the same statement: every row is a duplicate',
      () async {
    final _FakeExtractor extractor = _FakeExtractor(hdfcText);
    final ImportPreview first = (await service.previewPdf(
      '/x/hdfc.pdf', 'hdfc.pdf', extractor: extractor,
    )).valueOrNull!;
    await service.confirm(first);
    expect(await _count(txnDao), 2);

    final ImportPreview second = (await service.previewPdf(
      '/x/hdfc.pdf', 'hdfc.pdf', extractor: extractor,
    )).valueOrNull!;
    expect(second.newCount, 0);
    expect(second.duplicateCount, 2);
    expect(
      second.rows.map((ImportPreviewRow r) => r.dupReason),
      everyElement(DupReason.refNo),
    );
    final Result<ImportSummary> again = await service.confirm(second);
    expect(again.valueOrNull!.inserted, 0);
    expect(await _count(txnDao), 2, reason: 'no double-count');
  });

  test('fuzzy leg: a live-captured txn of the same day dedups the row',
      () async {
    // A notification capture of the same payment: same amount,
    // merchant, day — but no ref (Txn.copyWith cannot null a field,
    // so the row is built without one).
    final Txn live = _liveSwiggyCapture().copyWith(
      id: 'live002',
      refNo: '',
      dedupKey: 'live-key-2',
    );
    await txnDao.upsertByDedupKey(live);

    final ImportPreview p = (await service.previewPdf(
      '/x/hdfc.pdf', 'hdfc.pdf', extractor: _FakeExtractor(hdfcText),
    )).valueOrNull!;
    final ImportPreviewRow swiggyRow = p.rows.firstWhere(
      (ImportPreviewRow r) => r.txn.merchantClean == 'Swiggy',
    );
    expect(swiggyRow.dupReason, DupReason.fuzzy);
    // The NEFT salary row is untouched by the fuzzy window.
    final ImportPreviewRow salaryRow = p.rows
        .firstWhere((ImportPreviewRow r) => r.txn.amount.paise == 6500000);
    expect(salaryRow.dupReason, isNull);
  });

  test('in-set: identical dedup keys inside one file collapse', () async {
    const String twice = '''
HDFC BANK LIMITED
01/06/26    UPI/401234567890/SWIGGY/YESB0PTX        401234567890    01/06/26    349.00    45,678.90
01/06/26    UPI/401234567890/SWIGGY/YESB0PTX        401234567890    01/06/26    349.00    45,678.90
''';
    final ImportPreview p = (await service.previewPdf(
      '/x/hdfc.pdf', 'hdfc.pdf', extractor: _FakeExtractor(twice),
    )).valueOrNull!;
    expect(p.rows, hasLength(2));
    expect(p.newCount, 1);
    expect(p.duplicateCount, 1);
    expect(p.rows.last.dupReason, DupReason.inSet);
  });

  test('UDAO CSV round-trip: export → parse → rows match', () {
    final String csv = CsvService.toCsv(<Txn>[_liveSwiggyCapture()]);
    final Result<StatementParse> parsed = CsvStatementParser.parse(csv);
    final StatementParse p = parsed.valueOrNull!;
    expect(p.bankId, 'udao-csv');
    expect(p.rows, hasLength(1));
    expect(p.rows.first.amountPaise, 34900);
    expect(p.rows.first.direction, TxnDirection.debit);
    expect(p.rows.first.refNo, '401234567890');
    expect(p.rows.first.narration, 'Swiggy');
  });

  test('foreign CSV is an honest error', () {
    final Result<StatementParse> r = CsvStatementParser.parse(
      'date,description,amount\n01/06/2026,coffee,120.00\n',
    );
    expect(r, isA<Err<StatementParse>>());
    expect((r as Err<StatementParse>).failure.message, 'unknown_csv_format');
  });

  test('CSV re-import of an export lands all-duplicate', () async {
    await txnDao.upsertByDedupKey(_liveSwiggyCapture());
    final Directory tmp = await Directory.systemTemp.createTemp('udao_csv');
    final File file = File('${tmp.path}/export.csv');
    await file.writeAsString(
      CsvService.toCsv(<Txn>[_liveSwiggyCapture()]),
    );
    addTearDown(() => tmp.delete(recursive: true));

    final Result<ImportPreview> preview =
        await service.previewCsv(file.path, 'export.csv');
    final ImportPreview p = preview.valueOrNull!;
    expect(p.rows, hasLength(1));
    expect(p.newCount, 0, reason: 're-importing an export must dedup');
    expect(p.duplicateCount, 1);
    final Result<ImportSummary> summary = await service.confirm(p);
    expect(summary.valueOrNull!.inserted, 0);
    expect(await _count(txnDao), 1);
  });
}

Future<int> _count(TxnDao dao) async =>
    (await dao.count()).valueOrNull ?? 0;
