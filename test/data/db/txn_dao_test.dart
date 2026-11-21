// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/txn.dart';

import 'test_db.dart' as helper;

Txn _txn(
  String id,
  int paise, {
  String direction = 'debit',
  String merchant = 'Swiggy',
  int occurredAtDaysAgo = 0,
  String dedupKey = '',
  String? categoryId,
}) {
  final DateTime at = DateTime(2026, 10, 27, 18, 45).subtract(
    Duration(days: occurredAtDaysAgo),
  );
  return Txn(
    id: id,
    amount: Money(paise),
    direction: direction == 'debit'
        ? TxnDirection.debit
        : TxnDirection.credit,
    source: TxnSource.sms,
    rawText: 'raw $id',
    merchantRaw: merchant,
    merchantClean: merchant,
    bankOrApp: 'hdfc',
    categoryId: categoryId,
    occurredAt: at,
    capturedAt: at,
    confidence: 0.9,
    dedupKey: dedupKey.isEmpty ? 'dk-$id' : dedupKey,
  );
}

void main() {
  late UdaoDatabase db;
  late TxnDao dao;

  setUp(() async {
    db = await helper.createTestDb();
    dao = TxnDao(db.db);
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  group('upsertByDedupKey', () {
    test('inserts a fresh txn and reports true', () async {
      final Result<bool> r = await dao.upsertByDedupKey(_txn('t1', 100));
      expect(r.valueOrNull, isTrue);
      expect((await dao.count()).valueOrNull, 1);
    });

    test('ignores a second row with the same dedup key', () async {
      await dao.upsertByDedupKey(_txn('t1', 100, dedupKey: 'same'));
      final Result<bool> r =
          await dao.upsertByDedupKey(_txn('t2', 100, dedupKey: 'same'));
      expect(r.valueOrNull, isFalse);
      expect((await dao.count()).valueOrNull, 1);
    });
  });

  group('findById / findByDedupKey', () {
    test('round-trips every field through the row mapping', () async {
      final Txn t = _txn('t1', 12345)
          .copyWith(
            refNo: '512345678901',
            vpa: 'x@ybl',
            note: 'dinner',
            categoryId: 'cat_khaana',
          );
      await dao.upsertByDedupKey(t);
      final Txn? loaded = (await dao.findById('t1')).valueOrNull;
      expect(loaded, isNotNull);
      expect(loaded!.amount.paise, 12345);
      expect(loaded.direction, TxnDirection.debit);
      expect(loaded.source, TxnSource.sms);
      expect(loaded.refNo, '512345678901');
      expect(loaded.vpa, 'x@ybl');
      expect(loaded.note, 'dinner');
      expect(loaded.categoryId, 'cat_khaana');
      expect(loaded.dedupKey, 'dk-t1');
      final Txn? byKey =
          (await dao.findByDedupKey('dk-t1')).valueOrNull;
      expect(byKey?.id, 't1');
    });

    test('misses return null, not errors', () async {
      expect((await dao.findById('nope')).valueOrNull, isNull);
      expect((await dao.findByDedupKey('nope')).valueOrNull, isNull);
    });
  });

  group('page', () {
    test('orders newest-first and pages', () async {
      for (int i = 0; i < 7; i++) {
        await dao.upsertByDedupKey(
          _txn('t$i', 100, occurredAtDaysAgo: 6 - i),
        );
      }
      final List<Txn> page1 =
          (await dao.page(limit: 3, offset: 0)).valueOrNull!;
      final List<Txn> page2 =
          (await dao.page(limit: 3, offset: 3)).valueOrNull!;
      expect(page1.first.id, 't6');
      expect(page1.length, 3);
      expect(page2.first.id, 't3');
      expect((await dao.page(limit: 3, offset: 6)).valueOrNull!.length, 1);
    });

    test('filters by window, direction, category and search', () async {
      final DateTime from = DateTime(2026, 10, 20);
      final DateTime to = DateTime(2026, 10, 28);
      await dao.upsertByDedupKey(_txn('in', 100, categoryId: 'cat_khaana'));
      await dao.upsertByDedupKey(
        _txn('out-window', 100, occurredAtDaysAgo: 30),
      );
      await dao.upsertByDedupKey(
        _txn('credit', 100, direction: 'credit'),
      );
      await dao.upsertByDedupKey(
        _txn('other-cat', 100, categoryId: 'cat_shopping'),
      );
      expect(
        (await dao.page(from: from, to: to)).valueOrNull!.length,
        3,
      );
      expect(
        (await dao.page(direction: TxnDirection.credit)).valueOrNull!
            .single
            .id,
        'credit',
      );
      expect(
        (await dao.page(categoryId: 'cat_khaana')).valueOrNull!.single.id,
        'in',
      );
      expect(
        (await dao.page(search: 'wig')).valueOrNull!.length,
        4,
      );
      expect(
        (await dao.page(search: 'zomato')).valueOrNull!.length,
        0,
      );
    });
  });

  group('sums', () {
    test('sumBetween honours window, category and direction', () async {
      final DateTime from = DateTime(2026, 10, 20);
      final DateTime to = DateTime(2026, 10, 28);
      await dao.upsertByDedupKey(
        _txn('a', 10000, categoryId: 'cat_khaana'),
      );
      await dao.upsertByDedupKey(
        _txn('b', 5000, categoryId: 'cat_khaana'),
      );
      await dao.upsertByDedupKey(
        _txn('c', 99999, direction: 'credit'),
      );
      await dao.upsertByDedupKey(
        _txn('d', 1, occurredAtDaysAgo: 30),
      );
      expect(
        (await dao.sumBetween(from, to)).valueOrNull!.paise,
        114999,
      );
      expect(
        (await dao.sumBetween(from, to, direction: TxnDirection.debit))
            .valueOrNull!
            .paise,
        15000,
      );
      expect(
        (await dao.sumBetween(
          from,
          to,
          categoryId: 'cat_khaana',
          direction: TxnDirection.debit,
        ))
            .valueOrNull!
            .paise,
        15000,
      );
    });

    test('sumByCategory groups debits only, NULL bucket preserved',
        () async {
      await dao.upsertByDedupKey(
        _txn('a', 100, categoryId: 'cat_khaana'),
      );
      await dao.upsertByDedupKey(
        _txn('b', 200, categoryId: 'cat_khaana'),
      );
      await dao.upsertByDedupKey(_txn('c', 50));
      await dao.upsertByDedupKey(
        _txn('d', 9999, direction: 'credit'),
      );
      final List<CategorySpend> rows =
          (await dao.sumByCategory(DateTime(2026, 1, 1), DateTime(2027, 1, 1)))
              .valueOrNull!;
      expect(rows.length, 2);
      expect(rows.first.categoryId, 'cat_khaana');
      expect(rows.first.total.paise, 300);
      expect(rows.last.categoryId, isNull);
      expect(rows.last.total.paise, 50);
    });

    test('totalsByDay buckets per UTC day, debits only', () async {
      await dao.upsertByDedupKey(_txn('a', 100));
      await dao.upsertByDedupKey(
        _txn('b', 200, occurredAtDaysAgo: 1),
      );
      await dao.upsertByDedupKey(
        _txn('c', 9999, direction: 'credit'),
      );
      final List<DayTotal> days =
          (await dao.totalsByDay(DateTime(2026, 10, 1), DateTime(2026, 11, 1)))
              .valueOrNull!;
      expect(days.length, 2);
      expect(days.last.debit.paise, 100);
      expect(days.first.debit.paise, 200);
    });
  });

  group('findNear', () {
    test('matches same amount within the 10-minute window', () async {
      final DateTime at = DateTime(2026, 10, 27, 18, 45);
      await dao.upsertByDedupKey(_txn('a', 100).copyWith(occurredAt: at));
      final List<Txn> near = (await dao.findNear(
        around: at.add(const Duration(minutes: 9)),
        amountPaise: 100,
        merchantClean: 'Swiggy',
      ))
          .valueOrNull!;
      expect(near.length, 1);

      final List<Txn> far = (await dao.findNear(
        around: at.add(const Duration(minutes: 11)),
        amountPaise: 100,
        merchantClean: 'Swiggy',
      ))
          .valueOrNull!;
      expect(far, isEmpty);
    });

    test('amount mismatch never matches', () async {
      final DateTime at = DateTime(2026, 10, 27, 18, 45);
      await dao.upsertByDedupKey(_txn('a', 100).copyWith(occurredAt: at));
      expect(
        (await dao.findNear(
          around: at,
          amountPaise: 101,
        ))
            .valueOrNull,
        isEmpty,
      );
    });
  });

  group('updates and deletes', () {
    test('updateCategory and updateNote persist', () async {
      await dao.upsertByDedupKey(_txn('t1', 100));
      await dao.updateCategory('t1', 'cat_udan_jhari');
      await dao.updateNote('t1', 'bakwaas kharcha');
      final Txn loaded = (await dao.findById('t1')).valueOrNull!;
      expect(loaded.categoryId, 'cat_udan_jhari');
      expect(loaded.note, 'bakwaas kharcha');
    });

    test('deleteById removes the row', () async {
      await dao.upsertByDedupKey(_txn('t1', 100));
      await dao.deleteById('t1');
      expect((await dao.count()).valueOrNull, 0);
    });

    test('firstTxnDate returns the oldest occurred_at', () async {
      expect((await dao.firstTxnDate()).valueOrNull, isNull);
      await dao.upsertByDedupKey(_txn('new', 100));
      await dao.upsertByDedupKey(
        _txn('old', 100, occurredAtDaysAgo: 5),
      );
      final DateTime? first = (await dao.firstTxnDate()).valueOrNull;
      expect(
        first,
        DateTime(2026, 10, 27, 18, 45).subtract(const Duration(days: 5)),
      );
    });
  });
}
