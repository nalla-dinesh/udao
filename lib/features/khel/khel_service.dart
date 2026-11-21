// phase-07
// KhelService — the IO half: loads facts for the pure engine, judges
// completed IST days, persists streak/badges/challenges, and manages
// the user's pre-committed freeze token (kv).
//
// Evaluation is IDEMPOTENT by construction: the window always starts
// AFTER the last counted no-spend day (live streak) or re-judges a
// bounded lookback (no streak) where spend-days and already-counted
// days are no-ops. Safe to call on every app open, resume, and Khel
// screen visit.
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/models/badge.dart';
import 'package:udao/data/models/streak_state.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/query_repos.dart';

import 'khel_config.dart';
import 'khel_engine.dart';

/// What one evaluation pass changed — consumed by the UI (and,
/// later, roast triggers).
class KhelEvaluation {
  const KhelEvaluation({
    required this.state,
    required this.outcomes,
    required this.badgesUnlocked,
    required this.challengesCompleted,
    required this.freezesEarned,
  });

  final StreakState state;
  final List<KhelDayOutcome> outcomes;
  final List<String> badgesUnlocked;
  final List<String> challengesCompleted;
  final int freezesEarned;
}

class KhelService {
  KhelService({
    required StreakRepo streaks,
    required KhelRepo khel,
    required TxnDao txns,
    required KvDao kv,
  })  : _streaks = streaks,
        _khel = khel,
        _txns = txns,
        _kv = kv;

  final StreakRepo _streaks;
  final KhelRepo _khel;
  final TxnDao _txns;
  final KvDao _kv;

  /// Judges every completed-but-unjudged day and persists the
  /// results. Non-fatal per piece: a failed day-sum skips the day
  /// (it will be re-judged next pass — at-least-once, like the WAL).
  Future<Result<KhelEvaluation>> evaluate({DateTime? now}) async {
    try {
      final DateTime today = IstDates.startOfDay(now ?? IstDates.nowIst());

      final Result<StreakState> read = await _streaks.read();
      final StreakState state =
          read.valueOrNull ?? const StreakState.initial();

      final List<DateTime> days = KhelEngine.daysToEvaluate(state, today);
      final List<KhelFacts> facts = <KhelFacts>[];

      // The user's pre-committed freeze (one day, ms-precision key).
      final Result<String?> pending = await _kv.get(KhelConfig.kvFreezePending);
      final int? freezeDayMs =
          pending.valueOrNull == null ? null : int.tryParse(pending.valueOrNull!);

      for (final DateTime day in days) {
        final Result<int> spent = await _daySpend(day);
        if (spent is Err<int>) {
          return Err(spent.failure);
        }
        facts.add(
          KhelFacts(
            day: day,
            spentPaise: spent.valueOrNull ?? 0,
            freezeCommitted: freezeDayMs == day.millisecondsSinceEpoch,
          ),
        );
      }

      final KhelTransition t = KhelEngine.apply(state, facts);

      // Persist: streak (+earned freezes), badges, challenges.
      final int earned = KhelEngine.freezesEarned(t.challengesCompleted);
      StreakState finalState = t.state;
      if (earned > 0) {
        finalState = finalState.copyWith(
          freezesLeft: finalState.freezesLeft + earned,
        );
      }
      final Result<void> written = await _streaks.write(finalState);
      if (written is Err<void>) {
        return Err(written.failure);
      }

      final DateTime nowIst = IstDates.nowIst();
      for (final String badgeId in t.badgesUnlocked) {
        final Result<void> b = await _khel.upsertBadge(
          Badge(id: badgeId, unlockedAt: nowIst, seen: false),
        );
        if (b is Err<void>) {
          return Err(b.failure);
        }
      }
      for (final String challengeId in t.challengesCompleted) {
        final ChallengeDef def = KhelConfig.challenges.firstWhere(
          (ChallengeDef c) => c.id == challengeId,
        );
        final Result<void> c = await _khel.upsertChallenge(
          ChallengeProgress(
            id: def.id,
            metric: def.metric,
            current: def.target,
            target: def.target,
            completedAt: nowIst,
          ),
        );
        if (c is Err<void>) {
          return Err(c.failure);
        }
      }

      // A freeze committed to a judged day is spent (or moot) —
      // clear the token either way so it cannot leak to another day.
      if (freezeDayMs != null) {
        final bool dayWasJudged = days.any(
          (DateTime d) => d.millisecondsSinceEpoch == freezeDayMs,
        );
        if (dayWasJudged) {
          await _kv.set(KhelConfig.kvFreezePending, '');
        }
      }

      return Ok(
        KhelEvaluation(
          state: finalState,
          outcomes: t.outcomes,
          badgesUnlocked: t.badgesUnlocked,
          challengesCompleted: t.challengesCompleted,
          freezesEarned: earned,
        ),
      );
    } on Object catch (e, s) {
      // Failure is sealed — the typed subclasses live in its library;
      // UnexpectedFailure carries cause + stack for the UI message.
      return Err(UnexpectedFailure('khel.evaluate', cause: e, stackTrace: s));
    }
  }

  /// Pre-commits a freeze token for a day in progress. The token is
  /// only consumed when the day completes and actually had a spend —
  /// committing for a clean day wastes nothing. [day] is normally
  /// today; the parameter exists for tests.
  Future<Result<bool>> commitFreezeForDay(DateTime day) async {
    try {
      final Result<StreakState> read = await _streaks.read();
      final StreakState state =
          read.valueOrNull ?? const StreakState.initial();
      if (state.freezesLeft <= 0) {
        return const Ok(false);
      }
      await _kv.set(
        KhelConfig.kvFreezePending,
        '${IstDates.startOfDay(day).millisecondsSinceEpoch}',
      );
      return const Ok(true);
    } on Object catch (e, s) {
      return Err(
        UnexpectedFailure('khel.commitFreeze', cause: e, stackTrace: s),
      );
    }
  }

  /// Convenience: commit for the current IST day.
  Future<Result<bool>> commitFreezeForToday() =>
      commitFreezeForDay(IstDates.nowIst());

  /// Whether a freeze is already committed for the given day.
  Future<bool> freezeCommittedFor(DateTime day) async {
    final Result<String?> pending = await _kv.get(KhelConfig.kvFreezePending);
    return pending.valueOrNull == '${day.millisecondsSinceEpoch}';
  }

  /// Accepted debits on one IST day (paise). Credits never count.
  Future<Result<int>> _daySpend(DateTime day) async {
    final Result<Money> spent = await _txns.sumBetween(
      IstDates.startOfDay(day),
      IstDates.endOfDay(day),
      direction: TxnDirection.debit,
    );
    if (spent is Err<Money>) {
      return Err(spent.failure);
    }
    return Ok(spent.valueOrNull?.paise ?? 0);
  }

  /// Everything the Khel screen renders, in one call. Evaluation
  /// errors degrade to the current persisted state (the screen never
  /// dies for a game hiccup).
  Future<KhelSnapshot> snapshot() async {
    final Result<KhelEvaluation> eval = await evaluate();
    final Result<StreakState> persisted = await _streaks.read();
    final StreakState state = eval.valueOrNull?.state ??
        persisted.valueOrNull ??
        const StreakState.initial();

    final DateTime now = IstDates.nowIst();
    final Result<Money> todaySpend = await _txns.sumBetween(
      IstDates.startOfDay(now),
      now,
      direction: TxnDirection.debit,
    );
    final bool freeze = await freezeCommittedFor(
      IstDates.startOfDay(now),
    );
    final Result<List<Badge>> badges = await _khel.allBadges();
    final Result<List<ChallengeProgress>> challenges =
        await _khel.allChallenges();

    return KhelSnapshot(
      state: state,
      todaySpendPaise: todaySpend.valueOrNull?.paise ?? 0,
      freezeCommittedToday: freeze,
      badges: badges.valueOrNull ?? const <Badge>[],
      challenges: challenges.valueOrNull ?? const <ChallengeProgress>[],
    );
  }

  /// Marks a badge as seen (kills the glow after the user viewed it).
  Future<Result<void>> markBadgeSeen(String id) => _khel.markBadgeSeen(id);

}

/// One screen-load snapshot: evaluation + today's spend so far +
/// freeze state + badges + challenges. Everything the Khel UI shows.
class KhelSnapshot {
  const KhelSnapshot({
    required this.state,
    required this.todaySpendPaise,
    required this.freezeCommittedToday,
    required this.badges,
    required this.challenges,
  });

  final StreakState state;
  final int todaySpendPaise;
  final bool freezeCommittedToday;
  final List<Badge> badges;
  final List<ChallengeProgress> challenges;
}
