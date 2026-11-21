// phase-06
// The 10 agent tools, fully implemented against the Phase-02 repos
// and DAOs. Every tool returns a compact map the loop can inline as
// a TOOL_RESULT observation; errors are {'ok': false, 'error': …}
// so the model can be honest about them.
//
// Money discipline: rupees in (numbers from the model), paise out
// (Money) — never doubles in the ledger.
import '../../../core/result/result.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/csv/csv_service.dart';
import '../../../data/db/dao/txn_dao.dart';
import '../../../data/models/budget.dart';
import '../../../data/models/category.dart';
import '../../../data/models/streak_state.dart';
import '../../../data/models/subscription.dart';
import '../../../data/models/txn.dart';
import '../../../data/repos/query_repos.dart';
import 'agent_tool.dart';

/// Everything the tools need, bundled once by the provider.
class ToolContext {
  const ToolContext({
    required this.txns,
    required this.categories,
    required this.budgets,
    required this.subscriptions,
    required this.streaks,
    required this.csv,
  });

  final TxnDao txns;
  final CategoryRepo categories;
  final BudgetRepo budgets;
  final SubscriptionRepo subscriptions;
  final StreakRepo streaks;
  final CsvService csv;
}

DateTime _rangeStart(String range, DateTime now) {
  final DateTime ist = IstDates.toIst(now);
  switch (range) {
    case '7d':
      return IstDates.startOfDay(ist.subtract(const Duration(days: 7)));
    case '30d':
      return IstDates.startOfDay(ist.subtract(const Duration(days: 30)));
    case 'last_month':
      return IstDates.previousMonthStart(ist);
    case 'month':
    default:
      return IstDates.startOfMonth(ist);
  }
}

DateTime _rangeEnd(String range, DateTime now) {
  final DateTime ist = IstDates.toIst(now);
  switch (range) {
    case '7d':
      return IstDates.endOfDay(ist);
    case '30d':
      return IstDates.endOfDay(ist);
    case 'last_month':
      return IstDates.endOfMonth(IstDates.previousMonthStart(ist));
    case 'month':
    default:
      return IstDates.endOfMonth(ist);
  }
}

Map<String, Object?> _err(String message) => <String, Object?>{
      'ok': false,
      'error': message,
    };

// ── 1. query_spends ──────────────────────────────────────────────

class QuerySpendsTool implements AgentTool {
  QuerySpendsTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'query_spends';

  @override
  String get description =>
      'Query spend totals. Returns the total, count and per-category '
      'breakdown for a range. Default range: this month.';

  @override
  Map<String, Map<String, Object?>> get schema => <String, Map<String, Object?>>{
        'category': <String, Object?>{'type': 'string', 'required': false},
        'range': <String, Object?>{
          'type': 'string',
          'required': false,
          'enum': <String>['7d', '30d', 'month', 'last_month'],
        },
        'direction': <String, Object?>{
          'type': 'string',
          'required': false,
          'enum': <String>['debit', 'credit'],
        },
      };

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final String range = args['range'] as String? ??
        (args['category'] != null ? '30d' : 'month');
    final DateTime now = DateTime.now();
    final DateTime from = _rangeStart(range, now);
    final DateTime to = _rangeEnd(range, now);
    final TxnDirection direction =
        (args['direction'] as String?) == 'credit'
            ? TxnDirection.credit
            : TxnDirection.debit;
    final String? category = args['category'] as String?;

    final Result<List<CategorySpend>> byCategory =
        await _c.txns.sumByCategory(from, to);
    if (byCategory.isErr) {
      return _err(byCategory.failureOrNull!.message);
    }
    // Resolve category names (model thinks in names, ledger in ids).
    final Map<String, String> idToName = <String, String>{};
    final Result<List<Category>> cats = await _c.categories.all();
    if (cats.valueOrNull != null) {
      for (final Category c in cats.valueOrNull!) {
        idToName[c.id] = c.name;
      }
    }
    final List<Map<String, Object>> rows = <Map<String, Object>>[];
    Money total = const Money.zero();
    for (final CategorySpend cs in byCategory.valueOrNull!) {
      final String catName = idToName[cs.categoryId] ?? cs.categoryId ?? 'other';
      if (category != null &&
          !catName.toLowerCase().contains(category.toLowerCase()) &&
          !(cs.categoryId ?? '').contains(category.toLowerCase())) {
        continue;
      }
      rows.add(<String, Object>{
        'category': catName,
        'amount': cs.total.wholeRupees,
      });
      total += cs.total;
    }
    final Result<int> count =
        await _c.txns.count(from: from, to: to, direction: direction);
    return <String, Object?>{
      'ok': true,
      'range': range,
      'direction': direction.name,
      'total': total.wholeRupees,
      'count': count.valueOrNull ?? rows.length,
      'byCategory': rows.take(8).toList(growable: false),
    };
  }
}

// ── 2. get_budgets ────────────────────────────────────────────────

class GetBudgetsTool implements AgentTool {
  GetBudgetsTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'get_budgets';

  @override
  String get description =>
      'List active budgets with spent and remaining amounts.';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final Result<List<Budget>> budgets = await _c.budgets.all();
    if (budgets.isErr) {
      return _err(budgets.failureOrNull!.message);
    }
    final Result<List<Category>> cats = await _c.categories.all();
    final Map<String, String> idToName = <String, String>{};
    for (final Category c in cats.valueOrNull ?? const <Category>[]) {
      idToName[c.id] = c.name;
    }
    final List<Map<String, Object>> rows = <Map<String, Object>>[];
    for (final Budget b in budgets.valueOrNull!) {
      final Result<BudgetStatus> status = await _c.budgets.statusOf(b);
      rows.add(<String, Object>{
        'category': b.categoryId == null
            ? 'wallet'
            : (idToName[b.categoryId] ?? b.categoryId!),
        'limit': b.limit.wholeRupees,
        'spent': status.valueOrNull?.spent.wholeRupees ?? 0,
        'remaining': status.valueOrNull?.remaining.wholeRupees ?? 0,
        'exceeded': status.valueOrNull?.exceeded ?? false,
      });
    }
    return <String, Object?>{'ok': true, 'budgets': rows};
  }
}

// ── 3. set_budget ─────────────────────────────────────────────────

class SetBudgetTool implements AgentTool {
  SetBudgetTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'set_budget';

  @override
  String get description =>
      'Create or update a budget. limit is whole rupees per month. '
      'Use category "wallet" for the overall budget.';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{
        'category': <String, Object?>{'type': 'string', 'required': true},
        'limit': <String, Object?>{'type': 'number', 'required': true},
      };

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final String category = args['category'] as String? ?? '';
    final num? limit = args['limit'] as num?;
    if (limit == null || limit <= 0) {
      return _err('limit must be positive rupees');
    }
    String? categoryId;
    if (category.toLowerCase() != 'wallet') {
      final Result<List<Category>> cats = await _c.categories.all();
      final List<Category>? list = cats.valueOrNull;
      if (list == null) {
        return _err(cats.failureOrNull!.message);
      }
      Category? match;
      for (final Category c in list) {
        if (c.name.toLowerCase().contains(category.toLowerCase())) {
          match = c;
          break;
        }
      }
      if (match == null) {
        return _err('unknown category $category');
      }
      categoryId = match.id;
    }
    final Budget budget = Budget(
      id: categoryId ?? 'wallet',
      categoryId: categoryId,
      limit: Money((limit * 100).round()),
      period: BudgetPeriod.monthly,
      rollover: false,
      active: true,
    );
    final Result<void> saved = await _c.budgets.upsert(budget);
    if (saved.isErr) {
      return _err(saved.failureOrNull!.message);
    }
    return <String, Object?>{
      'ok': true,
      'category': category,
      'limit': limit.round(),
    };
  }
}

// ── 4. get_subscriptions ──────────────────────────────────────────

class GetSubscriptionsTool implements AgentTool {
  GetSubscriptionsTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'get_subscriptions';

  @override
  String get description =>
      'List detected recurring charges (merchant, amount, cadence, status).';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final Result<List<Subscription>> subs = await _c.subscriptions.all();
    if (subs.isErr) {
      return _err(subs.failureOrNull!.message);
    }
    final List<Map<String, Object>> rows = <Map<String, Object>>[];
    for (final Subscription s in subs.valueOrNull!) {
      rows.add(<String, Object>{
        'merchant': s.merchantClean,
        'amount': s.amount.wholeRupees,
        'everyDays': s.cadenceDays,
        'status': s.status.name,
      });
    }
    return <String, Object?>{'ok': true, 'subscriptions': rows};
  }
}

// ── 5. predict_month_end ──────────────────────────────────────────

class PredictMonthEndTool implements AgentTool {
  PredictMonthEndTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'predict_month_end';

  @override
  String get description =>
      'Predict this month\'s total spend: daily average so far × '
      'remaining days. (Phase 07 upgrades the predictor; today this '
      'is the honest simple version.)';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final DateTime now = IstDates.nowIst();
    final DateTime from = IstDates.startOfMonth(now);
    final DateTime to = IstDates.endOfMonth(now);
    final Result<Money> spent = await _c.txns.sumBetween(
      from,
      to,
      direction: TxnDirection.debit,
    );
    if (spent.isErr) {
      return _err(spent.failureOrNull!.message);
    }
    final int daysInMonth = to.day;
    final int elapsed = now.day.clamp(1, daysInMonth);
    final int remaining = (daysInMonth - now.day).clamp(0, 31);
    final Money monthTotal = spent.valueOrNull ?? const Money.zero();
    final int dailyAvgRupees =
        (monthTotal.wholeRupees / elapsed).round();
    return <String, Object?>{
      'ok': true,
      'spentSoFar': monthTotal.wholeRupees,
      'dayOfMonth': now.day,
      'daysInMonth': daysInMonth,
      'remainingDays': remaining,
      'dailyAverage': dailyAvgRupees,
      'predictedMonthEnd': dailyAvgRupees * daysInMonth,
    };
  }
}

// ── 6. add_transaction ────────────────────────────────────────────

class AddTransactionTool implements AgentTool {
  AddTransactionTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'add_transaction';

  @override
  String get description =>
      'Add a manual transaction to the ledger. amount is whole '
      'rupees. Returns the txn id.';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{
        'amount': <String, Object?>{'type': 'number', 'required': true},
        'merchant': <String, Object?>{'type': 'string', 'required': true},
        'category': <String, Object?>{'type': 'string', 'required': true},
      };

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final num? amount = args['amount'] as num?;
    final String merchant = args['merchant'] as String? ?? '';
    if (amount == null || amount <= 0 || merchant.isEmpty) {
      return _err('amount and merchant are required');
    }
    // The model thinks in loose names ('food', 'Shopping',
    // 'khaana'); the ledger keys on ids. Resolve in tiers: exact id,
    // exact name, exact icon key, then substring on name/id/icon.
    // Unresolvable → honest null (recategorize can fix it later).
    String? categoryId;
    final String query =
        (args['category'] as String? ?? '').trim().toLowerCase();
    if (query.isNotEmpty) {
      final Result<List<Category>> cats = await _c.categories.all();
      final List<Category> list =
          cats.valueOrNull ?? const <Category>[];
      for (final Category c in list) {
        if (c.id.toLowerCase() == query) {
          categoryId = c.id;
          break;
        }
      }
      if (categoryId == null) {
        for (final Category c in list) {
          if (c.name.toLowerCase() == query) {
            categoryId = c.id;
            break;
          }
        }
      }
      if (categoryId == null) {
        for (final Category c in list) {
          if (c.icon.toLowerCase() == query) {
            categoryId = c.id;
            break;
          }
        }
      }
      if (categoryId == null) {
        for (final Category c in list) {
          if (c.name.toLowerCase().contains(query) ||
              c.id.toLowerCase().contains(query) ||
              c.icon.toLowerCase().contains(query)) {
            categoryId = c.id;
            break;
          }
        }
      }
    }
    final DateTime now = IstDates.nowIst();
    final Txn txn = Txn(
      id: TxnId.newId(),
      amount: Money((amount * 100).round()),
      direction: TxnDirection.debit,
      source: TxnSource.manual,
      rawText: 'agent: $merchant',
      merchantRaw: merchant,
      merchantClean: merchant,
      bankOrApp: 'manual',
      occurredAt: now,
      capturedAt: now,
      confidence: 1.0,
      dedupKey: 'agent:${TxnId.newId()}',
      categoryId: categoryId,
    );
    final Result<bool> saved = await _c.txns.upsertByDedupKey(txn);
    if (saved.isErr) {
      return _err(saved.failureOrNull!.message);
    }
    return <String, Object?>{
      'ok': true,
      'id': txn.id,
      'amount': amount.round(),
      'merchant': merchant,
    };
  }
}

// ── 7. recategorize ───────────────────────────────────────────────

class RecategorizeTool implements AgentTool {
  RecategorizeTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'recategorize';

  @override
  String get description =>
      'Move a transaction to a different category by txn id.';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{
        'txnId': <String, Object?>{'type': 'string', 'required': true},
        'category': <String, Object?>{'type': 'string', 'required': true},
      };

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final String txnId = args['txnId'] as String? ?? '';
    final String category = args['category'] as String? ?? '';
    if (txnId.isEmpty || category.isEmpty) {
      return _err('txnId and category are required');
    }
    final Result<List<Category>> cats = await _c.categories.all();
    String? categoryId;
    for (final Category c in cats.valueOrNull ?? const <Category>[]) {
      if (c.name.toLowerCase().contains(category.toLowerCase())) {
        categoryId = c.id;
        break;
      }
    }
    if (categoryId == null) {
      return _err('unknown category $category');
    }
    final Result<void> updated =
        await _c.txns.updateCategory(txnId, categoryId);
    if (updated.isErr) {
      return _err(updated.failureOrNull!.message);
    }
    return <String, Object?>{'ok': true, 'txnId': txnId, 'category': category};
  }
}

// ── 8. get_streak ─────────────────────────────────────────────────

class GetStreakTool implements AgentTool {
  GetStreakTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'get_streak';

  @override
  String get description =>
      'Current no-spend streak: length, longest, freezes left.';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final Result<StreakState> state = await _c.streaks.read();
    if (state.isErr) {
      return _err(state.failureOrNull!.message);
    }
    final StreakState s = state.valueOrNull!;
    return <String, Object?>{
      'ok': true,
      'currentDays': s.length,
      'longestDays': s.longest,
      'freezesLeft': s.freezesLeft,
    };
  }
}

// ── 9. list_categories ────────────────────────────────────────────

class ListCategoriesTool implements AgentTool {
  ListCategoriesTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'list_categories';

  @override
  String get description =>
      'List spending categories (name, essential flag).';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final Result<List<Category>> cats = await _c.categories.all();
    if (cats.isErr) {
      return _err(cats.failureOrNull!.message);
    }
    return <String, Object?>{
      'ok': true,
      'categories': cats.valueOrNull!
          .map(
            (Category c) => <String, Object>{
              'name': c.name,
              'essential': c.isEssential,
            },
          )
          .toList(growable: false),
    };
  }
}

// ── 10. export_report ─────────────────────────────────────────────

class ExportReportTool implements AgentTool {
  ExportReportTool(this._c);

  final ToolContext _c;

  @override
  String get name => 'export_report';

  @override
  String get description =>
      'Export a CSV of transactions for a range; returns the file '
      'path. Range defaults to this month.';

  @override
  Map<String, Map<String, Object?>> get schema =>
      <String, Map<String, Object?>>{
        'range': <String, Object?>{
          'type': 'string',
          'required': false,
          'enum': <String>['7d', '30d', 'month', 'last_month'],
        },
      };

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    final String range = args['range'] as String? ?? 'month';
    final DateTime now = DateTime.now();
    final Result<String> path = await _c.csv.exportCsv(
      from: _rangeStart(range, now),
      to: _rangeEnd(range, now),
    );
    if (path.isErr) {
      return _err(path.failureOrNull!.message);
    }
    return <String, Object?>{
      'ok': true,
      'path': path.valueOrNull,
      'range': range,
    };
  }
}

/// All ten, in registration order (the system prompt documents them
/// in this order too — pinned by a contract test).
List<AgentTool> buildAgentTools(ToolContext context) => <AgentTool>[
      QuerySpendsTool(context),
      GetBudgetsTool(context),
      SetBudgetTool(context),
      GetSubscriptionsTool(context),
      PredictMonthEndTool(context),
      AddTransactionTool(context),
      RecategorizeTool(context),
      GetStreakTool(context),
      ListCategoriesTool(context),
      ExportReportTool(context),
    ];
