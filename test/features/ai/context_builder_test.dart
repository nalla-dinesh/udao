// phase-06
// ContextBuilder: deterministic ~2k-char snapshot with an injected
// clock, against a real DB.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/budget.dart';
import 'package:udao/data/models/roast_entry.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/query_repos.dart';
import 'package:udao/features/ai/agent/context_builder.dart';
import 'package:udao/features/ai/persona/persona.dart';

import '../../data/db/test_db.dart' as helper;

void main() {
  late UdaoDatabase db;
  final DateTime now = DateTime(2026, 10, 30, 11);

  setUp(() async {
    db = await helper.createTestDb();
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  ContextBuilder builder() => ContextBuilder(
        txns: TxnDao(db.db),
        budgets: BudgetRepo(db),
        subscriptions: SubscriptionRepo(db),
        streaks: StreakRepo(db),
        roasts: RoastRepo(db),
        categories: CategoryRepo(db),
        clock: () => now,
      );

  test('empty wallet: honest empty context, within budget', () async {
    final String out = await builder().build(persona: Personas.savage);
    expect(out, contains('MONTH CONTEXT (IST):'));
    expect(out, contains('- no spends recorded this month'));
    expect(out, contains('STREAK:'));
    expect(out, contains('SUBSCRIPTIONS: 0 detected'));
    expect(out, contains('PERSONA: savage'));
    expect(out, contains('TODAY: 2026-10-30'));
    expect(out.length, lessThanOrEqualTo(ContextBuilder.budgetChars));
  });

  test('spends with month-over-month deltas', () async {
    final TxnDao txns = TxnDao(db.db);
    await txns.insertAllAtomic(<Txn>[
      // This month.
      _txn(now, 1000, 'cat_khaana'),
      _txn(now, 500, 'cat_shopping'),
      // Last month: food was 700 → delta +300.
      _txn(DateTime(2026, 9, 12), 700, 'cat_khaana'),
    ]);
    final String out = await builder().build(persona: Personas.sensei);
    expect(out, contains('Khaana: Rs.1000 (+300 vs last month)'));
    expect(out, contains('Shopping: Rs.500 (new)'));
  });

  test('wallet budget line appears when a wallet budget exists',
      () async {
    final BudgetRepo budgets = BudgetRepo(db);
    await budgets.upsert(
      Budget(
        id: 'wallet',
        limit: Money.fromRupees(8000),
        period: BudgetPeriod.monthly,
        rollover: false,
        active: true,
      ),
    );
    final TxnDao txns = TxnDao(db.db);
    await txns.insertAllAtomic(<Txn>[_txn(now, 2000, 'cat_khaana')]);

    final String out = await builder().build(persona: Personas.savage);
    expect(out, contains('WALLET BUDGET'));
    expect(out, contains('Rs.2000'));
    expect(out, contains('Rs.8000'));
  });

  test('recent roast ids are surfaced for anti-repeat', () async {
    final RoastRepo roasts = RoastRepo(db);
    await roasts.insert(
      RoastEntry(
        id: 'r1',
        templateId: 'food-03',
        createdAt: now,
        surface: RoastSurface.card,
        text: 'kharcha zyada',
      ),
    );
    final String out = await builder().build(persona: Personas.savage);
    expect(out, contains('RECENT ROAST TEMPLATES'));
    expect(out, contains('food-03'));
  });

  test('persona line reflects the resolved persona', () async {
    final String out = await builder().build(persona: Personas.hype);
    expect(out, contains('PERSONA: hype'));
  });

  test('output is deterministic (same input → same string)', () async {
    final TxnDao txns = TxnDao(db.db);
    await txns.insertAllAtomic(<Txn>[_txn(now, 300, 'cat_khaana')]);
    final String a = await builder().build(persona: Personas.savage);
    final String b = await builder().build(persona: Personas.savage);
    expect(a, b);
  });

  test('hard cap: the trim seam cuts to exactly budgetChars', () {
    final String capped = ContextBuilder.applyCap('x' * 5000);
    expect(capped.length, ContextBuilder.budgetChars);
    expect(capped.endsWith('…'), isTrue);
    expect(ContextBuilder.applyCap('short'), 'short');
  });

  test('a pathological wallet stays inside the prompt budget', () async {
    final TxnDao txns = TxnDao(db.db);
    final List<Txn> many = <Txn>[];
    for (int i = 0; i < 400; i++) {
      many.add(_txn(now, 100 + i, 'cat_shopping'));
    }
    await txns.insertAllAtomic(many);
    final String out = await builder().build(persona: Personas.savage);
    expect(out.length, lessThanOrEqualTo(ContextBuilder.budgetChars));
    // The spend line renders the human name, not the id.
    expect(out, contains('Shopping: Rs.119800'));
  });
}

Txn _txn(DateTime at, int rupees, String categoryId) => Txn(
      id: 't-${at.millisecondsSinceEpoch}-$rupees-${at.microsecond}',
      amount: Money.fromRupees(rupees),
      direction: TxnDirection.debit,
      source: TxnSource.sms,
      rawText: 'Rs.$rupees.00 debited',
      merchantRaw: 'TESTPAY',
      merchantClean: 'testpay',
      bankOrApp: 'hdfc',
      categoryId: categoryId,
      occurredAt: at,
      capturedAt: at,
      confidence: 0.95,
      dedupKey: 'dk-${at.millisecondsSinceEpoch}-$rupees-${at.microsecond}',
    );
