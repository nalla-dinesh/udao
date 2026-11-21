// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/migrations.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/embedding_row.dart';
import 'package:udao/data/models/txn.dart';

import 'test_db.dart' as helper;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UdaoDatabase db;

  setUp(() async {
    db = await helper.createTestDb();
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  test('opens, migrates to dbVersion, and seeds 16 categories', () async {
    final Database handle = await db.db;
    final List<Map<String, Object?>> pragma =
        await handle.rawQuery('PRAGMA user_version');
    expect(pragma.first.values.first, UdaoMigrations.dbVersion);
    final List<Map<String, Object?>> rows =
        await handle.rawQuery('SELECT COUNT(*) AS n FROM category');
    expect(rows.first['n'], 16);
  });

  test('foreign_keys pragma is ON', () async {
    final Database handle = await db.db;
    final List<Map<String, Object?>> rows =
        await handle.rawQuery('PRAGMA foreign_keys');
    expect(rows.first.values.first, 1);
  });

  test('instance is a singleton until reset', () async {
    final UdaoDatabase a = UdaoDatabase.instance;
    final UdaoDatabase b = UdaoDatabase.instance;
    expect(identical(a, b), isTrue);
    UdaoDatabase.resetInstance();
    expect(identical(UdaoDatabase.instance, db), isFalse);
    UdaoDatabase.injectForTesting(db);
  });

  test('wipeAll empties txn and reseeds categories', () async {
    final TxnDao dao = TxnDao(db.db);
    await dao.upsertByDedupKey(
      Txn(
        id: 't1',
        amount: const Money(100),
        direction: TxnDirection.debit,
        source: TxnSource.sms,
        rawText: 'raw',
        merchantRaw: 'SWIGGY',
        merchantClean: 'Swiggy',
        bankOrApp: 'hdfc',
        occurredAt: DateTime.now(),
        capturedAt: DateTime.now(),
        confidence: 0.9,
        dedupKey: 'k1',
      ),
    );
    await db.wipeAll();
    final Result<int> count = await dao.count();
    expect(count.valueOrNull, 0);
    final Database handle = await db.db;
    final List<Map<String, Object?>> rows =
        await handle.rawQuery('SELECT COUNT(*) AS n FROM category');
    expect(rows.first['n'], 16);
  });

  test('embedding cascade-deletes with its txn (FK proof)', () async {
    final Database handle = await db.db;
    await handle.insert('txn', <String, Object?>{
      'id': 't1',
      'amount': 100,
      'direction': 'debit',
      'source': 'sms',
      'raw_text': 'r',
      'merchant_raw': 'm',
      'merchant_clean': 'm',
      'bank_or_app': 'hdfc',
      'occurred_at': 0,
      'captured_at': 0,
      'confidence': 0.9,
      'dedup_key': 'k1',
    });
    // The model serialises the vector as a float64 BLOB — raw
    // List<int> is not a supported sqflite argument type.
    await handle.insert(
      'embedding',
      const EmbeddingRow(
        txnId: 't1',
        vector: <double>[1, 2, 3, 4],
        modelTag: 'minilm-v1',
      ).toRow(),
    );
    expect(await handle.delete('txn', where: "id = 't1'"), 1);
    final List<Map<String, Object?>> left =
        await handle.rawQuery('SELECT COUNT(*) AS n FROM embedding');
    expect(left.first['n'], 0);
  });

  test('downgrades are refused loudly', () async {
    final Database handle = await db.db;
    await expectLater(
      UdaoMigrations.refuseDowngrade(handle, 3, 2),
      throwsA(isA<DatabaseFailure>()),
    );
  });

  test('migration runner refuses unknown steps and downgrade walks', () async {
    final Database handle = await db.db;
    await expectLater(
      UdaoMigrations.run(handle, from: 2, to: 1),
      throwsA(isA<DatabaseFailure>()),
    );
    // (from == to) is a no-op walk over zero steps.
    await UdaoMigrations.run(handle, from: 1, to: 1);
  });

  test('a second fresh database is independent (singleInstance: false)',
      () async {
    final Database a = await db.db;
    final UdaoDatabase other = await helper.createTestDb();
    final Database b = await other.db;
    await a.insert('kv', <String, Object?>{
      'key': 'k',
      'value': 'v',
      'updated_at': 0,
    });
    final List<Map<String, Object?>> rows =
        await b.rawQuery('SELECT COUNT(*) AS n FROM kv');
    expect(rows.first['n'], 0);
    await helper.disposeTestDb(other);
    UdaoDatabase.injectForTesting(db);
  });
}
