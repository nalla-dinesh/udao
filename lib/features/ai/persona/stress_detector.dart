// phase-06
// Stress detection (spec): balance-proxy is unavailable, so three
// behavioural proxies — any 2/3 flags → StressDetected → the persona
// router forces Sensei for 72h with a gentle, opt-out copy. The
// DECISION is a pure function (unit-tested to death); the input
// gathering lives in [StressInputGatherer] so the logic never
// touches a DAO.
import '../../../core/result/result.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/db/dao/kv_dao.dart';
import '../../../data/db/dao/txn_dao.dart';
import '../../../data/models/budget.dart';
import '../../../data/models/txn.dart';
import '../../../data/repos/query_repos.dart';

class StressSignals {
  const StressSignals({
    this.spendRateDrop = false,
    this.openFrequencyDrop = false,
    this.consecutiveBreachDays = 0,
  });

  /// (a) Recent 7-day spend-rate fell >50% below the 30-day baseline.
  final bool spendRateDrop;

  /// (b) App opens in the last 14 days fell >50% vs the previous 14.
  final bool openFrequencyDrop;

  /// (c) 3+ consecutive budget-pace breach days.
  final int consecutiveBreachDays;

  bool get breachStreak => consecutiveBreachDays >= 3;
}

class StressVerdict {
  const StressVerdict({
    required this.detected,
    required this.flags,
  });

  final bool detected;

  /// Which of the three fired ('spend-rate', 'open-frequency',
  /// 'budget-breach') — never shown raw, only counted/logged.
  final List<String> flags;
}

class StressDetector {
  const StressDetector();

  /// Any 2-of-3 → detected.
  StressVerdict evaluate(StressSignals signals) {
    final List<String> flags = <String>[];
    if (signals.spendRateDrop) {
      flags.add('spend-rate');
    }
    if (signals.openFrequencyDrop) {
      flags.add('open-frequency');
    }
    if (signals.breachStreak) {
      flags.add('budget-breach');
    }
    return StressVerdict(detected: flags.length >= 2, flags: flags);
  }
}

/// Gathers the DAO/kv side of the signals. Pure logic above stays
/// test-friendly; this class only reads and computes rates.
class StressInputGatherer {
  StressInputGatherer({
    required TxnDao txns,
    required BudgetRepo budgets,
    required KvDao kv,
    DateTime Function() clock = DateTime.now,
  })  : _txns = txns,
        _budgets = budgets,
        _kv = kv,
        _clock = clock;

  final TxnDao _txns;
  final BudgetRepo _budgets;
  final KvDao _kv;
  final DateTime Function() _clock;

  static const String kvOpenDays = 'ai.appOpenDays';

  Future<StressSignals> gather() async {
    final DateTime now = IstDates.toIst(_clock());
    return StressSignals(
      spendRateDrop: await _spendRateDrop(now),
      openFrequencyDrop: await _openFrequencyDrop(now),
      consecutiveBreachDays: await _breachStreak(now),
    );
  }

  /// (a) avg daily debit, last 7 days vs the 30-day baseline.
  Future<bool> _spendRateDrop(DateTime now) async {
    final Result<Money> last7 = await _txns.sumBetween(
      IstDates.startOfDay(now.subtract(const Duration(days: 7))),
      IstDates.endOfDay(now),
      direction: TxnDirection.debit,
    );
    final Result<Money> last30 = await _txns.sumBetween(
      IstDates.startOfDay(now.subtract(const Duration(days: 30))),
      IstDates.endOfDay(now),
      direction: TxnDirection.debit,
    );
    final int recent = last7.valueOrNull?.wholeRupees ?? -1;
    final int baseline = (last30.valueOrNull?.wholeRupees ?? -1);
    if (recent < 0 || baseline <= 0) {
      return false;
    }
    final double recentDaily = recent / 7;
    final double baselineDaily = baseline / 30;
    if (baselineDaily <= 0) {
      return false;
    }
    return recentDaily < baselineDaily * 0.5;
  }

  /// (b) App-open days: last 14 vs previous 14 (kv stamp list).
  Future<bool> _openFrequencyDrop(DateTime now) async {
    final Result<String?> raw = await _kv.get(kvOpenDays);
    final String? json = raw.valueOrNull;
    if (json == null || json.isEmpty) {
      return false;
    }
    final List<String> days = json.split(',')
      ..retainWhere((String d) => d.isNotEmpty);
    int recent = 0;
    int previous = 0;
    for (final String day in days) {
      final DateTime? date = DateTime.tryParse(day);
      if (date == null) {
        continue;
      }
      final int diff = now.difference(date).inDays;
      if (diff >= 0 && diff < 14) {
        recent++;
      } else if (diff >= 14 && diff < 28) {
        previous++;
      }
    }
    if (previous == 0) {
      // Nothing to compare against — an honest "no signal", not a
      // false positive on a brand-new install.
      return false;
    }
    return recent < previous * 0.5;
  }

  /// (c) Consecutive days where debit crossed the wallet budget's
  /// daily share (pace breach). No wallet budget → 0 (no signal).
  Future<int> _breachStreak(DateTime now) async {
    final Result<List<Budget>> budgets = await _budgets.all();
    Budget? wallet;
    for (final Budget b in budgets.valueOrNull ?? const <Budget>[]) {
      if (b.categoryId == null && b.active) {
        wallet = b;
        break;
      }
    }
    if (wallet == null) {
      return 0;
    }
    final int dailyShareRupees =
        (wallet.limit.wholeRupees / 30).ceil();
    if (dailyShareRupees <= 0) {
      return 0;
    }
    int streak = 0;
    for (int back = 0; back < 7; back++) {
      final DateTime day = now.subtract(Duration(days: back));
      final Result<Money> spent = await _txns.sumBetween(
        IstDates.startOfDay(day),
        IstDates.endOfDay(day),
        direction: TxnDirection.debit,
      );
      if ((spent.valueOrNull?.wholeRupees ?? 0) > dailyShareRupees) {
        streak++;
      } else if (back == 0) {
        // Today not (yet) over pace — a partial day is not a breach.
        continue;
      } else {
        break;
      }
    }
    return streak;
  }
}

/// App-open stamping (called once per app start from main.dart).
Future<void> stampAppOpenDay(KvDao kv, {DateTime? at}) async {
  final DateTime now = IstDates.toIst(at ?? DateTime.now());
  final String today = IstDates.isoDate(now);
  final Result<String?> raw = await kv.get(StressInputGatherer.kvOpenDays);
  final List<String> days = (raw.valueOrNull ?? '')
      .split(',')
      .where((String d) => d.isNotEmpty)
      .toList();
  if (days.contains(today)) {
    return;
  }
  days.add(today);
  // ISO yyyy-MM-dd strings sort chronologically. Newest FIRST, then
  // cap the HEAD: stamps arrive in arbitrary order, so an unsorted
  // tail-cap once shipped the 28 OLDEST days and dropped today.
  days.sort((String a, String b) => b.compareTo(a));
  final List<String> capped = days.length > 28
      ? days.sublist(0, 28)
      : days;
  await kv.set(StressInputGatherer.kvOpenDays, capped.join(','));
}
