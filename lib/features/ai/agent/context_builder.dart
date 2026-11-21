// phase-06
// Assembles the compact financial context under a ~2k-char budget:
// month spends by category with deltas vs last month, streak,
// subscriptions count, recent roast template ids (anti-repeat), and
// the active persona. Deterministic output — snapshot-tested, with
// an injectable clock (phase-02 lesson: wall-clock needs seams).
import '../../../core/result/result.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/budget.dart';
import '../../../data/models/category.dart';
import '../../../data/db/dao/txn_dao.dart';
import '../../../data/models/roast_entry.dart';
import '../../../data/models/streak_state.dart';
import '../../../data/models/subscription.dart';
import '../../../data/repos/query_repos.dart';
import '../persona/persona.dart';

class ContextBuilder {
  ContextBuilder({
    required TxnDao txns,
    required BudgetRepo budgets,
    required SubscriptionRepo subscriptions,
    required StreakRepo streaks,
    required RoastRepo roasts,
    required CategoryRepo categories,
    DateTime Function() clock = DateTime.now,
  })  : _txns = txns,
        _budgets = budgets,
        _subscriptions = subscriptions,
        _streaks = streaks,
        _roasts = roasts,
        _categories = categories,
        _clock = clock;

  final TxnDao _txns;
  final BudgetRepo _budgets;
  final SubscriptionRepo _subscriptions;
  final StreakRepo _streaks;
  final RoastRepo _roasts;
  final CategoryRepo _categories;
  final DateTime Function() _clock;

  static const int budgetChars = 2000;

  Future<String> build({required Persona persona}) async {
    final DateTime now = IstDates.toIst(_clock());
    final DateTime monthStart = IstDates.startOfMonth(now);
    final DateTime monthEnd = IstDates.endOfMonth(now);
    final DateTime lastStart = IstDates.previousMonthStart(now);
    final DateTime lastEnd = IstDates.endOfMonth(lastStart);

    final Result<List<CategorySpend>> thisMonth =
        await _txns.sumByCategory(monthStart, monthEnd);
    final Result<List<CategorySpend>> lastMonth =
        await _txns.sumByCategory(lastStart, lastEnd);

    final Map<String?, int> lastTotals = <String?, int>{};
    for (final CategorySpend cs in lastMonth.valueOrNull ?? const <CategorySpend>[]) {
      lastTotals[cs.categoryId] = cs.total.wholeRupees;
    }

    final StringBuffer buffer = StringBuffer();
    buffer.write('MONTH CONTEXT (IST):\n');
    final List<CategorySpend> spends =
        thisMonth.valueOrNull ?? const <CategorySpend>[];
    if (spends.isEmpty) {
      buffer.write('- no spends recorded this month\n');
    }
    // The model thinks in names; the ledger keys on ids. Map ids to
    // their human names (fall back to the raw id when unknown).
    final Map<String, String> idToName = <String, String>{};
    final Result<List<Category>> cats = await _categories.all();
    for (final Category c in cats.valueOrNull ?? const <Category>[]) {
      idToName[c.id] = c.name;
    }
    for (final CategorySpend cs in spends.take(6)) {
      final int current = cs.total.wholeRupees;
      final int? last = lastTotals[cs.categoryId];
      final String delta = last == null
          ? 'new'
          : (current > last
              ? '+${current - last} vs last month'
              : '${current - last} vs last month');
      final String catName =
          (cs.categoryId == null ? null : idToName[cs.categoryId]) ??
              cs.categoryId ??
              'other';
      buffer.write(
        '- $catName: Rs.$current ($delta)\n',
      );
      lastTotals.remove(cs.categoryId);
    }

    final Result<StreakState> streak = await _streaks.read();
    final StreakState s = streak.valueOrNull ?? const StreakState.initial();
    buffer.write('STREAK: ${s.length} days (best ${s.longest})\n');

    final Result<List<Budget>> budgets = await _budgets.all();
    final List<Budget>? budgetList = budgets.valueOrNull;
    Budget? wallet;
    for (final Budget b in budgetList ?? const <Budget>[]) {
      if (b.categoryId == null) {
        wallet = b;
        break;
      }
    }
    if (budgetList != null && budgetList.isNotEmpty && wallet != null) {
      final Result<BudgetStatus> status = await _budgets.statusOf(wallet);
      final BudgetStatus? st = status.valueOrNull;
      if (st != null) {
        final String sign = st.remaining.wholeRupees >= 0 ? '' : '-';
        buffer.write(
          'WALLET BUDGET: Rs.${st.spent.wholeRupees} of '
          'Rs.${wallet.limit.wholeRupees} '
          '($sign Rs.${st.remaining.wholeRupees.abs()} left)\n',
        );
      }
    }

    final Result<List<Subscription>> subs = await _subscriptions.all();
    buffer.write(
      'SUBSCRIPTIONS: ${subs.valueOrNull?.length ?? 0} detected\n',
    );

    final Result<List<RoastEntry>> recent = await _roasts.recent(limit: 3);
    final List<RoastEntry>? roasts = recent.valueOrNull;
    if (roasts != null && roasts.isNotEmpty) {
      final String recentIds =
          roasts.map((RoastEntry r) => r.templateId).join(', ');
      buffer.write(
        'RECENT ROAST TEMPLATES (do NOT repeat these ids): '
        '$recentIds\n',
      );
    }

    buffer.write('PERSONA: ${persona.id} (${persona.voiceNote})\n');
    buffer.write('TODAY: ${IstDates.isoDate(now)}\n');

    return applyCap(buffer.toString());
  }

  /// The hard char-cap. Every section is individually bounded, so in
  /// practice this rarely fires — it is the safety net that keeps the
  /// prompt budget a LAW, not a guideline. Pure on purpose: the trim
  /// is unit-tested directly (the integration path can't overflow
  /// with realistic data).
  static String applyCap(String full) =>
      full.length <= budgetChars
          ? full
          : '${full.substring(0, budgetChars - 1)}…';
}
