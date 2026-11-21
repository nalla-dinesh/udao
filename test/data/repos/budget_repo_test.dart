// phase-02 (phase-08 usage) — Budget status windows: current-period spend, rollover
// carry (unspent travels, debt does not), category scoping, credit
// exclusion. Deterministic via the injected `now` clock.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/budget.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/query_repos.dart';

import '../db/test_db.dart' as helper;

void main() {
  late UdaoDatabase db;
  late BudgetRepo budgets;
  late TxnDao txns;

  // A fixed mid-month Wednesday, 12:00 IST wall-clock.
  final DateTime now = DateTime.utc(2026, 11, 4, 12);

  setUp(() async {
    db = await helper.createTestDb();
    budgets = BudgetRepo(db);
    txns = TxnDao(db.db);
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  Future<void> seedTxn(
    String id,
    DateTime at, {
    int paise = 100000,
    TxnDirection direction = TxnDirection.debit,
    String? categoryId,
  }) async {
    await txns.upsertByDedupKey(Txn(
      id: id,
      amount: Money(paise),
      direction: direction,
      source: TxnSource.manual,
      rawText: '',
      merchantRaw: 'Test',
      merchantClean: 'Test',
      bankOrApp: 'manual',
      occurredAt: at,
      capturedAt: at,
      confidence: 0.98,
      dedupKey: 'dk-budget-$id',
      categoryId: categoryId,
    ));
  }

  test('monthly wallet: spent vs limit, inclusive window bounds',
      () async {
    final Budget b = Budget(
      id: 'wallet',
      categoryId: null,
      limit: Money(500000),
      period: BudgetPeriod.monthly,
      rollover: false,
      active: true,
    );
    // The spend window is [month start .. NOW] — Nov 1 just-after
    // midnight and Nov 4 just-before noon both count…
    await seedTxn('t1', DateTime.utc(2026, 11, 1, 0, 0, 0, 1),
        paise: 100000);
    await seedTxn('t2', DateTime.utc(2026, 11, 4, 11, 59), paise: 50000);
    // …but a txn AFTER now (Nov 4 12:00:01) and one before the month
    // (Oct 31) do NOT count.
    await seedTxn('t3', DateTime.utc(2026, 11, 4, 12, 0, 1),
        paise: 990000);
    await seedTxn('t4', DateTime.utc(2026, 10, 31, 23), paise: 990000);
    // A credit never counts.
    await seedTxn('t5', DateTime.utc(2026, 11, 2),
        paise: 200000, direction: TxnDirection.credit);

    final Result<BudgetStatus> status = await budgets.statusOf(b, now: now);
    final BudgetStatus s = status.valueOrNull!;
    expect(s.spent, const Money(150000));
    expect(s.remaining, const Money(350000));
    expect(s.carry, const Money.zero());
    expect(s.effectiveLimit, const Money(500000));
    expect(s.exceeded, isFalse);
    expect(s.overspendPercent, 0);
    expect(s.windowStart, DateTime.utc(2026, 11, 1));
    expect(s.windowEnd, DateTime.utc(2026, 12, 1).subtract(
      const Duration(milliseconds: 1),
    ));
  });

  test('rollover: unspent previous month lifts the current line',
      () async {
    final Budget b = Budget(
      id: 'wallet',
      categoryId: null,
      limit: Money(500000),
      period: BudgetPeriod.monthly,
      rollover: true,
      active: true,
    );
    await seedTxn('p1', DateTime.utc(2026, 10, 5), paise: 100000);
    await seedTxn('c1', DateTime.utc(2026, 11, 2), paise: 600000);

    final BudgetStatus s =
        (await budgets.statusOf(b, now: now)).valueOrNull!;
    expect(s.carry, const Money(400000));
    expect(s.effectiveLimit, const Money(900000));
    expect(s.spent, const Money(600000));
    expect(s.remaining, const Money(300000));
    expect(s.exceeded, isFalse);
    expect(s.overspendPercent, 0);
  });

  test('rollover: a blown previous month carries NOTHING (no debt)',
      () async {
    final Budget b = Budget(
      id: 'wallet',
      categoryId: null,
      limit: Money(500000),
      period: BudgetPeriod.monthly,
      rollover: true,
      active: true,
    );
    await seedTxn('p1', DateTime.utc(2026, 10, 5), paise: 800000);
    await seedTxn('c1', DateTime.utc(2026, 11, 2), paise: 600000);

    final BudgetStatus s =
        (await budgets.statusOf(b, now: now)).valueOrNull!;
    expect(s.carry, const Money.zero());
    expect(s.effectiveLimit, const Money(500000));
    expect(s.remaining, const Money(-100000));
    expect(s.exceeded, isTrue);
    expect(s.overspendPercent, 20);
  });

  test('weekly windows roll on startOfWeek, not calendar months',
      () async {
    final Budget b = Budget(
      id: 'wallet',
      categoryId: null,
      limit: Money(100000),
      period: BudgetPeriod.weekly,
      rollover: true,
      active: true,
    );
    // Nov 4 2026 is a Wednesday; the IST week started Mon Nov 2.
    await seedTxn('w1', DateTime.utc(2026, 11, 2), paise: 60000);
    await seedTxn('w0', DateTime.utc(2026, 10, 31), paise: 50000);

    final BudgetStatus s =
        (await budgets.statusOf(b, now: now)).valueOrNull!;
    expect(s.windowStart, DateTime.utc(2026, 11, 2));
    expect(s.spent, const Money(60000));
    // Prev week spend 500 < limit 1000 → carry 500.
    expect(s.carry, const Money(50000));
    expect(s.remaining, const Money(90000));
  });

  test('category budget counts only that category', () async {
    final Budget b = Budget(
      id: 'cat_khaana',
      categoryId: 'cat_khaana',
      limit: Money(200000),
      period: BudgetPeriod.monthly,
      rollover: false,
      active: true,
    );
    await seedTxn('k1', DateTime.utc(2026, 11, 3),
        paise: 120000, categoryId: 'cat_khaana');
    await seedTxn('k2', DateTime.utc(2026, 11, 3),
        paise: 300000, categoryId: 'cat_shopping');

    final BudgetStatus s =
        (await budgets.statusOf(b, now: now)).valueOrNull!;
    expect(s.spent, const Money(120000));
    expect(s.remaining, const Money(80000));
  });
}
