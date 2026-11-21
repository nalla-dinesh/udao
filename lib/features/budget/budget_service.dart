// phase-08
// BudgetService — the Lakshman Rekha brain. One place owns the budget
// ID convention (`id = categoryId ?? 'wallet'` — the SAME convention
// the agent's set_budget tool uses, so chat and UI write the same
// rows), validates mutations, and builds the screen snapshot.
//
// Pure rules, thin repo calls — testable without any UI.
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/budget.dart';
import 'package:udao/data/models/category.dart';
import 'package:udao/data/repos/query_repos.dart';

/// The screen-shaped read: every active budget with its live status,
/// the wallet budget hoisted out, and days left in the period.
class BudgetSnapshot {
  const BudgetSnapshot({
    required this.statuses,
    required this.categories,
  });

  /// Active budgets, wallet FIRST, then categories by sort order.
  final List<BudgetStatus> statuses;
  final List<Category> categories;

  /// The whole-wallet budget, when one exists.
  BudgetStatus? get wallet {
    for (final BudgetStatus s in statuses) {
      if (s.budget.categoryId == null) {
        return s;
      }
    }
    return null;
  }

  List<BudgetStatus> get byCategory => statuses
      .where((BudgetStatus s) => s.budget.categoryId != null)
      .toList(growable: false);

  int get exceededCount =>
      statuses.where((BudgetStatus s) => s.exceeded).length;

  /// Calendar days (inclusive) left in the wallet window — the number
  /// the hero shows. Null without a wallet budget or window.
  int? get walletDaysLeft {
    final BudgetStatus? w = wallet;
    if (w == null || w.windowEnd == null) {
      return null;
    }
    final DateTime today = IstDates.startOfDay(IstDates.nowIst());
    final int left =
        IstDates.startOfDay(w.windowEnd!).difference(today).inDays + 1;
    return left < 0 ? 0 : left;
  }
}

class BudgetService {
  BudgetService({required BudgetRepo budgets, required CategoryRepo categories})
      : _budgets = budgets,
        _categories = categories;

  final BudgetRepo _budgets;
  final CategoryRepo _categories;

  /// Budget rows are keyed by target: one per category, one wallet.
  static String idFor(String? categoryId) => categoryId ?? 'wallet';

  /// The whole list, statuses attached. Never throws.
  Future<Result<BudgetSnapshot>> snapshot() async {
    final Result<List<Budget>> budgets = await _budgets.all();
    if (budgets.isErr) {
      return Err(budgets.failureOrNull!);
    }
    final Result<List<Category>> cats = await _categories.all();
    if (cats.isErr) {
      return Err(cats.failureOrNull!);
    }
    final Map<String, int> sortOf = <String, int>{};
    for (final Category c in cats.valueOrNull ?? const <Category>[]) {
      sortOf[c.id] = c.sort;
    }

    final List<BudgetStatus> statuses = <BudgetStatus>[];
    BudgetStatus? wallet;
    for (final Budget b in budgets.valueOrNull ?? const <Budget>[]) {
      final Result<BudgetStatus> status = await _budgets.statusOf(b);
      final BudgetStatus? s = status.valueOrNull;
      if (s == null) {
        return Err(status.failureOrNull!);
      }
      if (b.categoryId == null) {
        wallet = s;
      } else {
        statuses.add(s);
      }
    }
    statuses.sort((BudgetStatus a, BudgetStatus b) {
      final int sa = sortOf[a.budget.categoryId] ?? 99;
      final int sb = sortOf[b.budget.categoryId] ?? 99;
      return sa.compareTo(sb);
    });
    if (wallet != null) {
      statuses.insert(0, wallet);
    }
    return Ok(BudgetSnapshot(
      statuses: statuses,
      categories: cats.valueOrNull ?? const <Category>[],
    ));
  }

  /// Validated create-or-update. Rules:
  ///  * limit must be a positive amount;
  ///  * weekly budgets need ≥ ₹1 (a ₹1 weekly line is legal, if brave);
  ///  * the row id IS the target (`categoryId ?? 'wallet'`), so a
  ///    second budget for the same category REPLACES the first — by
  ///    design, matching the agent tool.
  Future<Result<Budget>> save({
    String? categoryId,
    required Money limit,
    required BudgetPeriod period,
    required bool rollover,
  }) async {
    if (limit.paise <= 0) {
      return const Err(
        UnexpectedFailure('budget.save', cause: 'limit must be positive'),
      );
    }
    final Budget budget = Budget(
      id: idFor(categoryId),
      categoryId: categoryId,
      limit: limit,
      period: period,
      rollover: rollover,
      active: true,
    );
    final Result<void> saved = await _budgets.upsert(budget);
    if (saved.isErr) {
      return Err(saved.failureOrNull!);
    }
    return Ok(budget);
  }

  Future<Result<void>> remove(String id) => _budgets.delete(id);
}
