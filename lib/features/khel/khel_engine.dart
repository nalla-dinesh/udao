// phase-07
// The Khel heart — PURE streak transitions. No IO, no clocks, no
// Flutter: everything here is a function of (state, day, facts) so
// the whole rulebook is unit-testable to exhaustion.
//
// Day semantics (IST, day-precision — see IstDates):
//   * A COMPLETED day with zero accepted debits is a no-spend day.
//   * Today is never judged — the day must end first. The UI shows
//     risk ("aaj ₹X ho gaya"), the engine only rules on yesterday
//     and older, once they complete.
//   * A freeze token, pre-committed by the user for a specific day,
//     converts a spend-day into a protected day: the streak survives
//     but does not grow.
import 'package:flutter/foundation.dart';

import '../../data/models/streak_state.dart';
import 'khel_config.dart';

/// One applied day-transition, for the UI/badges to react to.
@immutable
class KhelDayOutcome {
  const KhelDayOutcome({
    required this.day,
    required this.spentPaise,
    required this.kind,
  });

  /// The IST day that was judged.
  final DateTime day;

  /// Accepted debits on that day (paise).
  final int spentPaise;

  final KhelDayKind kind;
}

enum KhelDayKind { noSpend, protectedByFreeze, brokeStreak }

@immutable
class KhelTransition {
  const KhelTransition({
    required this.state,
    required this.outcomes,
    required this.badgesUnlocked,
    required this.challengesCompleted,
  });

  /// State after all applied days.
  final StreakState state;

  /// Every judged day, in order.
  final List<KhelDayOutcome> outcomes;

  /// Badge ids that became unlocked during this transition.
  final List<String> badgesUnlocked;

  /// Challenge ids that completed during this transition.
  final List<String> challengesCompleted;
}

@immutable
class KhelFacts {
  const KhelFacts({
    required this.day,
    required this.spentPaise,
    required this.freezeCommitted,
  });

  /// The IST day being judged (day-precision, from startOfDay).
  final DateTime day;

  /// Accepted debits on that day (paise).
  final int spentPaise;

  /// The user pre-committed a freeze token for exactly this day.
  final bool freezeCommitted;
}

abstract final class KhelEngine {
  /// Applies a sequence of COMPLETED days, oldest first. Pure: the
  /// same state + facts always yield the same transition.
  static KhelTransition apply(
    StreakState initial,
    List<KhelFacts> facts,
  ) {
    StreakState s = initial;
    final List<KhelDayOutcome> outcomes = <KhelDayOutcome>[];
    final List<String> badges = <String>[];
    final List<String> challengesDone = <String>[];
    final Set<String> alreadyBadges = <String>{};

    for (final KhelFacts f in facts) {
      final StreakState before = s;
      final StreakState after;
      KhelDayKind kind;

      if (f.spentPaise <= 0) {
        // No-spend: extend (or start) the streak.
        final int length = s.length + 1;
        after = s.copyWith(
          currentStart: s.currentStart ?? f.day,
          length: length,
          longest: length > s.longest ? length : s.longest,
          lastNoSpendDate: f.day,
        );
        kind = KhelDayKind.noSpend;
      } else if (f.freezeCommitted && s.freezesLeft > 0 && s.currentStart != null) {
        // Protected: a live streak survives a spend-day, unchanged.
        after = s.copyWith(freezesLeft: s.freezesLeft - 1);
        kind = KhelDayKind.protectedByFreeze;
      } else {
        // Broken: the streak dies; history and freezes survive.
        // (Built directly — StreakState.copyWith cannot clear a null
        // field, the `?? this.x` pattern would keep the old start.)
        after = StreakState(
          currentStart: null,
          length: 0,
          freezesLeft: s.freezesLeft,
          longest: s.longest,
          lastNoSpendDate: s.lastNoSpendDate,
        );
        kind = KhelDayKind.brokeStreak;
      }
      s = after;

      outcomes.add(
        KhelDayOutcome(day: f.day, spentPaise: f.spentPaise, kind: kind),
      );

      _unlockBadges(before, after, kind, badges, alreadyBadges);
      _completeChallenges(before, after, challengesDone);
    }

    return KhelTransition(
      state: s,
      outcomes: outcomes,
      badgesUnlocked: badges,
      challengesCompleted: challengesDone,
    );
  }

  static void _unlockBadges(
    StreakState before,
    StreakState after,
    KhelDayKind kind,
    List<String> out,
    Set<String> already,
  ) {
    void unlock(String id) {
      if (already.add(id)) {
        out.add(id);
      }
    }

    // First no-spend day ever.
    if (kind == KhelDayKind.noSpend &&
        before.length == 0 &&
        before.longest == 0 &&
        after.length == 1) {
      unlock('first_day');
    }
    // Ladder rungs crossed TODAY (before < threshold <= after).
    for (final LadderLevel l in KhelConfig.ladder) {
      if (before.length < l.days && after.length >= l.days) {
        unlock('ladder_${l.index}');
      }
    }
    // Comeback: a fresh 3-day streak when a 3+ streak already lives
    // in history (i.e. this is not the first climb).
    if (before.length == 2 && after.length == 3 && before.longest >= 3) {
      unlock('comeback');
    }
    if (kind == KhelDayKind.protectedByFreeze) {
      unlock('freeze_first');
    }
    if (before.length < 30 && after.length >= 30) {
      unlock('challenge_30');
    }
  }

  static void _completeChallenges(
    StreakState before,
    StreakState after,
    List<String> out,
  ) {
    for (final ChallengeDef c in KhelConfig.challenges) {
      if (before.length < c.target && after.length >= c.target) {
        out.add(c.id);
      }
    }
  }

  /// Freeze tokens earned from challenges completed in a transition
  /// (reward math lives with the rules, not the persistence layer).
  static int freezesEarned(List<String> challengesCompleted) {
    int earned = 0;
    for (final ChallengeDef c in KhelConfig.challenges) {
      if (challengesCompleted.contains(c.id)) {
        earned += c.rewardFreezes;
      }
    }
    return earned;
  }

  /// The day-window the service must judge, oldest first: completed
  /// days only, starting after the last known no-spend day when a
  /// streak is live, else a bounded lookback.
  static List<DateTime> daysToEvaluate(
    StreakState state,
    DateTime today, {
    int lookback = KhelConfig.lookbackDaysNoStreak,
  }) {
    final DateTime todayStart = DateTime.utc(today.year, today.month, today.day);
    final DateTime firstCompletedDay;
    if (state.currentStart != null) {
      final DateTime anchor =
          state.lastNoSpendDate ?? state.currentStart ?? todayStart;
      firstCompletedDay = DateTime.utc(
        anchor.year,
        anchor.month,
        anchor.day,
      ).add(const Duration(days: 1));
    } else if (_hasHistory(state)) {
      // A streak existed once and broke: catch-up lookback.
      firstCompletedDay = todayStart.subtract(Duration(days: lookback));
    } else {
      // FRESH install — no streak ever, no history. Judge only
      // yesterday: a 7-day backfill would hand out a fake "streak 7"
      // on day one, and the ledger genuinely says yesterday had no
      // captured debits. Idempotent: a clean yesterday sets
      // lastNoSpendDate (state stops being fresh); a spend yesterday
      // re-judges harmlessly until the day rolls over.
      firstCompletedDay = todayStart.subtract(const Duration(days: 1));
    }
    final List<DateTime> days = <DateTime>[];
    for (DateTime d = firstCompletedDay;
        d.isBefore(todayStart);
        d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    return days;
  }

  /// True when the state proves the game has been played before (a
  /// completed streak or any counted day). A fresh install judges
  /// only yesterday; a broken history earns the catch-up lookback.
  static bool _hasHistory(StreakState state) =>
      state.longest > 0 || state.lastNoSpendDate != null;
}
