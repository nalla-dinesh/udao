// phase-08 — BudgetService: the ID convention shared with the agent
// tool, save validation, snapshot shape (wallet hoisted, categories
// sorted), removal.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/budget.dart';
import 'package:udao/data/repos/query_repos.dart';
import 'package:udao/features/budget/budget_service.dart';

import '../../data/db/test_db.dart' as helper;

void main() {
  late UdaoDatabase db;
  late BudgetService service;
  late BudgetRepo budgets;

  setUp(() async {
    db = await helper.createTestDb();
    budgets = BudgetRepo(db);
    service = BudgetService(
      budgets: budgets,
      categories: CategoryRepo(db),
    );
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  test('idFor: budget rows are keyed by their target', () {
    expect(BudgetService.idFor(null), 'wallet');
    expect(BudgetService.idFor('cat_khaana'), 'cat_khaana');
  });

  test('save rejects a zero/empty line', () async {
    final Result<Budget> zero =
        await service.save(limit: const Money.zero(), period: BudgetPeriod.monthly, rollover: false);
    expect(zero.isErr, isTrue);
    expect(zero.failureOrNull!.message, 'budget.save');

    final Result<Budget> negative = await service.save(
        limit: const Money(-100), period: BudgetPeriod.monthly, rollover: false);
    expect(negative.isErr, isTrue);
  });

  test('save wallet then category; a second save REPLACES the row',
      () async {
    final Result<Budget> w = await service.save(
      limit: const Money(500000),
      period: BudgetPeriod.monthly,
      rollover: true,
    );
    expect(w.valueOrNull!.id, 'wallet');
    expect(w.valueOrNull!.categoryId, isNull);

    final Result<Budget> c = await service.save(
      categoryId: 'cat_khaana',
      limit: const Money(200000),
      period: BudgetPeriod.weekly,
      rollover: false,
    );
    expect(c.valueOrNull!.id, 'cat_khaana');
    expect(c.valueOrNull!.period, BudgetPeriod.weekly);

    // Same category again — replace, not duplicate.
    await service.save(
      categoryId: 'cat_khaana',
      limit: const Money(300000),
      period: BudgetPeriod.monthly,
      rollover: false,
    );

    final List<Budget> all = (await budgets.all()).valueOrNull!;
    expect(all.length, 2);
    final Budget khaana = all.firstWhere(
        (Budget b) => b.id == 'cat_khaana');
    expect(khaana.limit, const Money(300000));
    expect(khaana.period, BudgetPeriod.monthly);
  });

  test('snapshot: wallet hoisted first, categories follow seed sort',
      () async {
    await service.save(
        limit: const Money(500000),
        period: BudgetPeriod.monthly,
        rollover: false);
    await service.save(
        categoryId: 'cat_shopping',
        limit: const Money(100000),
        period: BudgetPeriod.monthly,
        rollover: false);
    await service.save(
        categoryId: 'cat_khaana',
        limit: const Money(200000),
        period: BudgetPeriod.monthly,
        rollover: false);

    final BudgetSnapshot snap =
        (await service.snapshot()).valueOrNull!;
    expect(snap.statuses.length, 3);
    // Wallet first (khaana sort 0 < shopping 7 among the two cats).
    expect(snap.wallet, isNotNull);
    expect(snap.statuses.first.budget.id, 'wallet');
    expect(
      snap.byCategory.map((BudgetStatus s) => s.budget.id).toList(),
      <String>['cat_khaana', 'cat_shopping'],
    );
    expect(snap.exceededCount, 0);
    // Monthly window: some day 1..31 is left.
    expect(snap.walletDaysLeft, allOf(greaterThanOrEqualTo(1), lessThanOrEqualTo(31)));
    // Category names resolve through the seed list.
    expect(snap.categories.length, greaterThanOrEqualTo(16));
  });

  test('snapshot on an empty ledger: no wallet, no lines', () async {
    final BudgetSnapshot snap =
        (await service.snapshot()).valueOrNull!;
    expect(snap.statuses, isEmpty);
    expect(snap.wallet, isNull);
    expect(snap.walletDaysLeft, isNull);
  });

  test('remove deletes the row', () async {
    await service.save(
        limit: const Money(500000),
        period: BudgetPeriod.monthly,
        rollover: false);
    final Result<void> removed = await service.remove('wallet');
    expect(removed.isOk, isTrue);
    expect((await budgets.all()).valueOrNull, isEmpty);
  });
}
