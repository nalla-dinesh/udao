// phase-06
// The 10 agent tools against a real (ffi in-memory) DB. Clock-bound
// tools (predict_month_end, add_transaction) assert relationships,
// not fixed dates.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/csv/csv_service.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/query_repos.dart';
import 'package:udao/features/ai/agent/agent_tool.dart';
import 'package:udao/features/ai/agent/agent_tools.dart';

import '../../data/db/test_db.dart' as helper;

void main() {
  late UdaoDatabase db;
  late ToolContext c;

  setUp(() async {
    db = await helper.createTestDb();
    c = ToolContext(
      txns: TxnDao(db.db),
      categories: CategoryRepo(db),
      budgets: BudgetRepo(db),
      subscriptions: SubscriptionRepo(db),
      streaks: StreakRepo(db),
      csv: CsvService(db),
    );
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  test('registration order is the documented contract (10 tools)',
      () {
    final List<AgentTool> tools = buildAgentTools(c);
    expect(tools.map((AgentTool t) => t.name), <String>[
      'query_spends',
      'get_budgets',
      'set_budget',
      'get_subscriptions',
      'predict_month_end',
      'add_transaction',
      'recategorize',
      'get_streak',
      'list_categories',
      'export_report',
    ]);
    for (final AgentTool t in tools) {
      expect(t.description.length, greaterThan(10), reason: t.name);
      // Description leaks = prompt content leaks.
      expect(t.description, isNot(contains('kv')));
      expect(t.description, isNot(contains('dao')));
    }
  });

  test('query_spends: month totals with category breakdown', () async {
    final DateTime now = DateTime.now();
    await c.txns.insertAllAtomic(<Txn>[
      _debit(now, 400, categoryId: 'cat_khaana'),
      _debit(now, 600, categoryId: 'cat_shopping'),
      // Last month — outside the default month range.
      _debit(
        DateTime(now.year, now.month - 1, 5),
        9999,
        categoryId: 'cat_khaana',
      ),
    ]);
    final Map<String, Object?> r =
        await QuerySpendsTool(c).invoke(const <String, Object?>{});
    expect(r['ok'], isTrue);
    expect(r['total'], 1000);
    expect(r['direction'], 'debit');
    final List<Object?> rows = r['byCategory']! as List<Object?>;
    expect(rows, hasLength(2));
  });

  test('query_spends: category filter narrows to matching rows',
      () async {
    final DateTime now = DateTime.now();
    await c.txns.insertAllAtomic(<Txn>[
      _debit(now, 400, categoryId: 'cat_khaana'),
      _debit(now, 600, categoryId: 'cat_shopping'),
    ]);
    final Map<String, Object?> r = await QuerySpendsTool(c)
        .invoke(const <String, Object?>{'category': 'shopping'});
    expect(r['total'], 600);
  });

  test('set_budget + get_budgets round-trip (wallet)', () async {
    final Map<String, Object?> set = await SetBudgetTool(c).invoke(
      const <String, Object?>{'category': 'wallet', 'limit': 5000},
    );
    expect(set['ok'], isTrue);

    final Map<String, Object?> got =
        await GetBudgetsTool(c).invoke(const <String, Object?>{});
    expect(got['ok'], isTrue);
    final List<Object?> budgets = got['budgets']! as List<Object?>;
    final Map<String, Object?> wallet =
        budgets.cast<Map<String, Object?>>().firstWhere(
              (Map<String, Object?> b) => b['category'] == 'wallet',
            );
    expect(wallet['limit'], 5000);
  });

  test('set_budget: positive limit enforced, unknown category honest',
      () async {
    expect(
      (await SetBudgetTool(c).invoke(const <String, Object?>{
        'category': 'wallet',
        'limit': -5,
      }))['ok'],
      isFalse,
    );
    expect(
      (await SetBudgetTool(c).invoke(const <String, Object?>{
        'category': 'intergalactic travel',
        'limit': 100,
      }))['ok'],
      isFalse,
    );
  });

  test('get_subscriptions: empty-but-ok on a fresh DB', () async {
    final Map<String, Object?> r =
        await GetSubscriptionsTool(c).invoke(const <String, Object?>{});
    expect(r['ok'], isTrue);
    expect(r['subscriptions'], isA<List<Object?>>());
  });

  test('predict_month_end: math is daily-avg × full month', () async {
    final DateTime now = DateTime.now();
    await c.txns.insertAllAtomic(<Txn>[
      _debit(now, 300),
      _debit(now, 200),
    ]);
    final Map<String, Object?> r =
        await PredictMonthEndTool(c).invoke(const <String, Object?>{});
    expect(r['ok'], isTrue);
    final int spent = r['spentSoFar']! as int;
    final int day = r['dayOfMonth']! as int;
    final int days = r['daysInMonth']! as int;
    final int avg = r['dailyAverage']! as int;
    final int predicted = r['predictedMonthEnd']! as int;
    expect(spent, greaterThanOrEqualTo(500));
    expect(avg, (spent / day.clamp(1, days)).round());
    expect(predicted, avg * days);
    expect(r['remainingDays'], days - day);
  });

  test('add_transaction writes a manual txn and reports the id',
      () async {
    final Map<String, Object?> r = await AddTransactionTool(c).invoke(
      const <String, Object?>{
        'amount': 250,
        'merchant': 'Chai Point',
        'category': 'food',
      },
    );
    expect(r['ok'], isTrue);
    expect(r['id'], isA<String>());
    final List<Txn> page =
        (await c.txns.page(limit: 10)).valueOrNull ?? <Txn>[];
    expect(page, isNotEmpty);
    final Txn added = page.firstWhere((Txn t) => t.id == r['id']);
    expect(added.amount, Money.fromRupees(250));
    expect(added.source, TxnSource.manual);
    expect(added.merchantClean, 'Chai Point');
    expect(
      added.categoryId,
      isNotNull,
      reason: '"food" must resolve to the seeded category id',
    );
  });

  test('add_transaction: bad input is an honest error, not a crash',
      () async {
    expect(
      (await AddTransactionTool(c).invoke(const <String, Object?>{
        'amount': 0,
        'merchant': '',
        'category': 'x',
      }))['ok'],
      isFalse,
    );
  });

  test('recategorize moves a txn by id', () async {
    await c.txns.insertAllAtomic(<Txn>[_debit(DateTime.now(), 100)]);
    final List<Txn> page =
        (await c.txns.page(limit: 5)).valueOrNull ?? <Txn>[];
    final String id = page.first.id;

    final Map<String, Object?> r = await RecategorizeTool(c).invoke(
      <String, Object?>{'txnId': id, 'category': 'shopping'},
    );
    expect(r['ok'], isTrue);
    final List<Txn> after =
        (await c.txns.page(limit: 5)).valueOrNull ?? <Txn>[];
    expect(
      after.firstWhere((Txn t) => t.id == id).categoryId,
      isNot('food_delivery'),
    );
  });

  test('get_streak reads the streak state', () async {
    final Map<String, Object?> r =
        await GetStreakTool(c).invoke(const <String, Object?>{});
    expect(r['ok'], isTrue);
    expect(r['currentDays'], isA<int>());
    expect(r['longestDays'], isA<int>());
    expect(r['freezesLeft'], isA<int>());
  });

  test('list_categories: 16 seeded, essentials flagged', () async {
    final Map<String, Object?> r =
        await ListCategoriesTool(c).invoke(const <String, Object?>{});
    final List<Object?> cats = r['categories']! as List<Object?>;
    expect(cats, hasLength(16));
    final bool hasEssential = cats
        .cast<Map<String, Object?>>()
        .any((Map<String, Object?> e) => e['essential'] == true);
    expect(hasEssential, isTrue);
  });

  test('export_report returns a path (month default)', () async {
    final Map<String, Object?> r =
        await ExportReportTool(c).invoke(const <String, Object?>{});
    expect(r['ok'], isTrue);
    expect(r['path'], isA<String>());
    expect(r['range'], 'month');
  });
}

Txn _debit(DateTime at, int rupees, {String? categoryId}) => Txn(
      id: 't-${at.millisecondsSinceEpoch}-$rupees-${at.microsecond}-$categoryId',
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
      dedupKey:
          'dk-${at.millisecondsSinceEpoch}-$rupees-${at.microsecond}-$categoryId',
    );
