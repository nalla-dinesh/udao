// phase-02
// Read-model repos: category, budget(+status), subscription, streak,
// roast, jar, capture-health. Thin by design — DAOs guard the SQL,
// repos add cross-DAO semantics only where they earn it.
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/badge_dao.dart';
import 'package:udao/data/db/dao/budget_dao.dart';
import 'package:udao/data/db/dao/capture_health_dao.dart';
import 'package:udao/data/db/dao/category_dao.dart';
import 'package:udao/data/db/dao/jar_dao.dart';
import 'package:udao/data/db/dao/roast_dao.dart';
import 'package:udao/data/db/dao/streak_dao.dart';
import 'package:udao/data/db/dao/subscription_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/badge.dart';
import 'package:udao/data/models/budget.dart';
import 'package:udao/data/models/category.dart';
import 'package:udao/data/models/jar.dart';
import 'package:udao/data/models/roast_entry.dart';
import 'package:udao/data/models/streak_state.dart';
import 'package:udao/data/models/subscription.dart';
import 'package:udao/data/models/txn.dart';

class CategoryRepo {
  CategoryRepo(this._database);
  final UdaoDatabase _database;
  CategoryDao? _dao;

  Future<CategoryDao> _d() async =>
      _dao ??= CategoryDao(_database.db);

  Future<Result<List<Category>>> all() async =>
      (await _d()).getAll();
  Future<Result<Category?>> byId(String id) async =>
      (await _d()).findById(id);
}

class BudgetRepo {
  BudgetRepo(this._database);
  final UdaoDatabase _database;
  BudgetDao? _budgetDao;
  TxnDao? _txnDao;

  Future<(BudgetDao, TxnDao)> _d() async {
    final Future<Database> db = _database.db;
    return (_budgetDao ??= BudgetDao(db), _txnDao ??= TxnDao(db));
  }

  Future<Result<List<Budget>>> all({bool includeInactive = false}) async =>
      (await _d()).$1.getAll(includeInactive: includeInactive);

  Future<Result<void>> upsert(Budget budget) async =>
      (await _d()).$1.upsert(budget);

  Future<Result<void>> delete(String id) async =>
      (await _d()).$1.deleteById(id);

  /// Budget health: limit vs spend for the current period window.
  ///
  /// Rollover budgets carry the PREVIOUS period's unspent amount into
  /// the current limit (`effectiveLimit`); a blown previous period
  /// carries nothing — debt does not travel.
  Future<Result<BudgetStatus>> statusOf(Budget budget,
      {DateTime? now}) async {
    final (BudgetDao _, TxnDao txns) = await _d();
    final DateTime at = now ?? IstDates.nowIst();
    final bool weekly = budget.period == BudgetPeriod.weekly;
    final DateTime from =
        weekly ? IstDates.startOfWeek(at) : IstDates.startOfMonth(at);
    final Result<Money> spent = await txns.sumBetween(
      from,
      at,
      categoryId: budget.categoryId,
      direction: TxnDirection.debit,
    );
    if (spent is Err<Money>) {
      return Err(spent.failure);
    }
    final Money spentTotal = spent.valueOrNull!;

    Money carry = const Money.zero();
    if (budget.rollover) {
      final DateTime prevFrom = weekly
          ? from.subtract(const Duration(days: 7))
          : IstDates.previousMonthStart(at);
      final Result<Money> prevSpent = await txns.sumBetween(
        prevFrom,
        from.subtract(const Duration(milliseconds: 1)),
        categoryId: budget.categoryId,
        direction: TxnDirection.debit,
      );
      if (prevSpent is Err<Money>) {
        return Err(prevSpent.failure);
      }
      final Money prev = prevSpent.valueOrNull!;
      carry =
          prev < budget.limit ? budget.limit - prev : const Money.zero();
    }

    return Ok(
      BudgetStatus(
        budget: budget,
        spent: spentTotal,
        carry: carry,
        windowStart: from,
        windowEnd:
            weekly ? IstDates.endOfWeek(at) : IstDates.endOfMonth(at),
        remaining:
            Money(budget.limit.paise + carry.paise - spentTotal.paise),
      ),
    );
  }
}

/// Limit vs spend snapshot for one budget.
class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.spent,
    required this.remaining,
    this.carry = const Money.zero(),
    this.windowStart,
    this.windowEnd,
  });
  final Budget budget;
  final Money spent;

  /// Unspent amount carried from the previous period (rollover on).
  final Money carry;

  /// Inclusive period window (IST). Null only for hand-built
  /// statuses in tests.
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final Money remaining;

  /// The line the wallet is actually judged against this period.
  Money get effectiveLimit => budget.limit + carry;
  bool get exceeded => remaining.paise < 0;

  /// Overspend vs the effective limit, whole percent (0 when the line
  /// holds; 100+ when crossed; clamped at 300 for display math).
  int get overspendPercent {
    final int limit = effectiveLimit.paise;
    if (limit <= 0) {
      return spent.paise > 0 ? 200 : 0;
    }
    return ((spent.paise - limit) * 100 / limit).ceil().clamp(0, 300);
  }
}

class SubscriptionRepo {
  SubscriptionRepo(this._database);
  final UdaoDatabase _database;
  SubscriptionDao? _dao;

  Future<SubscriptionDao> _d() async =>
      _dao ??= SubscriptionDao(_database.db);

  Future<Result<List<Subscription>>> all() async => (await _d()).getAll();
  Future<Result<void>> upsert(Subscription s) async => (await _d()).upsert(s);
  Future<Result<void>> markStatus(String id, SubscriptionStatus status) async =>
      (await _d()).markStatus(id, status);
}

class StreakRepo {
  StreakRepo(this._database);
  final UdaoDatabase _database;
  StreakDao? _dao;

  Future<StreakDao> _d() async => _dao ??= StreakDao(_database.db);

  Future<Result<StreakState>> read() async => (await _d()).read();
  Future<Result<void>> write(StreakState state) async =>
      (await _d()).write(state);
  Future<Result<void>> reset() async => (await _d()).reset();
}

class RoastRepo {
  RoastRepo(this._database);
  final UdaoDatabase _database;
  RoastDao? _dao;

  Future<RoastDao> _d() async => _dao ??= RoastDao(_database.db);

  Future<Result<void>> insert(RoastEntry entry) async =>
      (await _d()).insert(entry);
  Future<Result<List<RoastEntry>>> recent({int limit = 50}) async =>
      (await _d()).recent(limit: limit);
  Future<Result<bool>> usedTemplateToday(String templateId) async =>
      (await _d()).usedTemplateOnDay(
        templateId,
        IstDates.startOfDay(IstDates.nowIst()),
      );
}

class JarRepo {
  JarRepo(this._database);
  final UdaoDatabase _database;
  JarDao? _dao;

  Future<JarDao> _d() async => _dao ??= JarDao(_database.db);

  Future<Result<List<Jar>>> all() async => (await _d()).getAll();
  Future<Result<void>> insert(Jar jar) async => (await _d()).insert(jar);
  Future<Result<void>> update(Jar jar) async => (await _d()).update(jar);
  Future<Result<void>> delete(String id) async =>
      (await _d()).deleteById(id);
}

class CaptureHealthRepo {
  CaptureHealthRepo(this._database);
  final UdaoDatabase _database;
  CaptureHealthDao? _dao;

  Future<CaptureHealthDao> _d() async =>
      _dao ??= CaptureHealthDao(_database.db);

  Future<Result<List<CaptureDayStats>>> statsByDay({int days = 14}) async =>
      (await _d()).statsByDay(days: days);
  Future<Result<int>> purgeRawTextOlderThan(Duration age) async =>
      (await _d()).purgeRawTextOlderThan(
        DateTime.now().subtract(age),
      );
}

class KhelRepo {
  KhelRepo(this._database);
  final UdaoDatabase _database;
  BadgeDao? _dao;

  Future<BadgeDao> _d() async => _dao ??= BadgeDao(_database.db);

  Future<Result<void>> upsertBadge(Badge badge) async =>
      (await _d()).upsert(badge);
  Future<Result<List<Badge>>> allBadges() async => (await _d()).getAll();
  Future<Result<void>> markBadgeSeen(String id) async =>
      (await _d()).markSeen(id);
  Future<Result<void>> upsertChallenge(ChallengeProgress p) async =>
      (await _d()).upsertChallenge(p);
  Future<Result<List<ChallengeProgress>>> allChallenges() async =>
      (await _d()).allChallenges();
}
