// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/pending_review_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/pending_review_entry.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/pending_review_repo.dart';

import '../db/test_db.dart' as helper;

void main() {
  late UdaoDatabase db;
  late PendingReviewRepo repo;
  late TxnDao txns;

  setUp(() async {
    db = await helper.createTestDb();
    repo = PendingReviewRepo(db);
    txns = TxnDao(db.db);
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  Future<void> seedPending(String id, {int paise = 25000}) async {
    final PendingReviewEntry entry = PendingReviewEntry(
      id: id,
      source: 'sms',
      receivedAt: DateTime(2026, 10, 27, 18, 45),
      rawText: 'Payment of ₹250 pending approval',
      amount: Money(paise),
      direction: TxnDirection.debit,
      merchantClean: 'Unknown',
      confidence: 0.7,
      parserId: 'gpay',
    );
    final Result<void> r = await PendingReviewDao(db.db).insert(entry);
    expect(r.failureOrNull, isNull);
  }

  test('queue lists pending entries', () async {
    await seedPending('p1');
    await seedPending('p2');
    expect((await repo.pendingCount()).valueOrNull, 2);
    final List<PendingReviewEntry> q =
        (await repo.pending()).valueOrNull!;
    expect(q.length, 2);
  });

  test('approve converts the entry into a ledger txn', () async {
    await seedPending('p1');
    final Result<String> approved = await repo.approve('p1');
    expect(approved.valueOrNull, isNotNull);
    final Txn t =
        (await txns.findById(approved.valueOrNull!)).valueOrNull!;
    expect(t.amount.paise, 25000);
    expect(t.direction, TxnDirection.debit);
    expect(t.source, TxnSource.sms);
    expect(t.merchantClean, 'Unknown');
    expect((await repo.pendingCount()).valueOrNull, 0);
  });

  test('approve on an unknown id is a failure', () async {
    final Result<String> r = await repo.approve('ghost');
    expect(r.failureOrNull, isNotNull);
  });

  test('dismiss resolves without creating a txn', () async {
    await seedPending('p1');
    await repo.dismiss('p1');
    expect((await repo.pendingCount()).valueOrNull, 0);
    expect((await txns.count()).valueOrNull, 0);
  });

  test('cleanupResolved prunes old resolved entries', () async {
    await seedPending('p1');
    await seedPending('p2');
    await repo.dismiss('p1');
    // days: -1 -> cutoff one day in the FUTURE, so p1's resolve
    // stamp is always strictly before it (days: 0 can tie to the
    // same millisecond on a fast machine and flake).
    final int n = (await repo.cleanupResolved(days: -1)).valueOrNull!;
    expect(n, 1);
    expect((await repo.pendingCount()).valueOrNull, 1);
  });
}
