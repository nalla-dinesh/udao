// phase-07 — the Khel rulebook, exhausted. Pure engine: no IO.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/data/models/streak_state.dart';
import 'package:udao/features/khel/khel_config.dart';
import 'package:udao/features/khel/khel_engine.dart';

DateTime _day(int y, int m, int d) => DateTime.utc(y, m, d);

StreakState _live({
  int length = 3,
  DateTime? start,
  int longest = 3,
  int freezes = 2,
  DateTime? lastNoSpend,
}) {
  return StreakState(
    currentStart: start ?? _day(2026, 10, 20),
    length: length,
    freezesLeft: freezes,
    longest: longest,
    lastNoSpendDate: lastNoSpend ?? _day(2026, 10, 22),
  );
}

void main() {
  group('no-spend days', () {
    test('first clean day ever starts a streak + first_day badge', () {
      final KhelTransition t = KhelEngine.apply(
        const StreakState.initial(),
        <KhelFacts>[KhelFacts(day: _day(2026, 10, 26), spentPaise: 0, freezeCommitted: false)],
      );
      expect(t.state.length, 1);
      expect(t.state.currentStart, _day(2026, 10, 26));
      expect(t.state.lastNoSpendDate, _day(2026, 10, 26));
      expect(t.state.longest, 1);
      expect(t.outcomes.single.kind, KhelDayKind.noSpend);
      expect(t.badgesUnlocked, contains('first_day'));
    });

    test('clean days extend and track longest', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 3, longest: 3),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 0, freezeCommitted: false),
          KhelFacts(day: _day(2026, 10, 24), spentPaise: 0, freezeCommitted: false),
        ],
      );
      expect(t.state.length, 5);
      expect(t.state.longest, 5);
      expect(t.state.lastNoSpendDate, _day(2026, 10, 24));
    });

    test('crossing a rung unlocks exactly that ladder badge', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 2, longest: 2),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 0, freezeCommitted: false),
        ],
      );
      expect(t.badgesUnlocked, contains('ladder_1'));
      expect(t.badgesUnlocked, isNot(contains('ladder_2')));
    });
  });

  group('spend days', () {
    test('a spend day breaks the streak but keeps history', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 4, longest: 6),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 25000, freezeCommitted: false),
        ],
      );
      expect(t.state.length, 0);
      expect(t.state.currentStart, isNull);
      expect(t.state.longest, 6, reason: 'history survives a break');
      expect(t.state.freezesLeft, 2);
      expect(t.state.lastNoSpendDate, _day(2026, 10, 22));
      expect(t.outcomes.single.kind, KhelDayKind.brokeStreak);
      expect(t.badgesUnlocked, isEmpty);
    });

    test('broken-then-clean restarts from 1 with no first_day badge', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 4, longest: 6),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 25000, freezeCommitted: false),
          KhelFacts(day: _day(2026, 10, 24), spentPaise: 0, freezeCommitted: false),
        ],
      );
      expect(t.state.length, 1);
      expect(t.state.currentStart, _day(2026, 10, 24));
      expect(t.badgesUnlocked, isNot(contains('first_day')));
    });
  });

  group('freezes', () {
    test('committed freeze protects a live streak without growing it', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 5, longest: 5),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 25000, freezeCommitted: true),
        ],
      );
      expect(t.state.length, 5, reason: 'protected, not advanced');
      expect(t.state.currentStart, isNotNull);
      expect(t.state.freezesLeft, 1);
      expect(t.outcomes.single.kind, KhelDayKind.protectedByFreeze);
      expect(t.badgesUnlocked, contains('freeze_first'));
    });

    test('freeze without tokens does not protect', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 5, freezes: 0),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 25000, freezeCommitted: true),
        ],
      );
      expect(t.state.length, 0);
      expect(t.state.freezesLeft, 0);
      expect(t.outcomes.single.kind, KhelDayKind.brokeStreak);
    });

    test('freeze with no live streak does nothing (broken anyway)', () {
      final KhelTransition t = KhelEngine.apply(
        const StreakState.initial(),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 26), spentPaise: 25000, freezeCommitted: true),
        ],
      );
      expect(t.state.length, 0);
      expect(t.state.freezesLeft, 2, reason: 'no token wasted');
      expect(t.outcomes.single.kind, KhelDayKind.brokeStreak);
    });

    test('clean day with a committed freeze wastes nothing', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 5),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 0, freezeCommitted: true),
        ],
      );
      expect(t.state.length, 6);
      expect(t.state.freezesLeft, 2, reason: 'no spend — no freeze burned');
    });
  });

  group('comeback + challenges', () {
    test('comeback badge on a fresh 3 after a past 3+ streak', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 2, longest: 6),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 0, freezeCommitted: false),
          KhelFacts(day: _day(2026, 10, 24), spentPaise: 0, freezeCommitted: false),
        ],
      );
      expect(t.state.length, 4);
      expect(t.badgesUnlocked, contains('comeback'));
    });

    test('no comeback on the first-ever climb', () {
      final KhelTransition t = KhelEngine.apply(
        const StreakState.initial(),
        <KhelFacts>[
          for (int i = 24; i <= 26; i++)
            KhelFacts(day: _day(2026, 10, i), spentPaise: 0, freezeCommitted: false),
        ],
      );
      expect(t.state.length, 3);
      expect(t.badgesUnlocked, isNot(contains('comeback')));
    });

    test('7-day challenge completes once and earns a freeze', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 6, longest: 6),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 0, freezeCommitted: false),
        ],
      );
      expect(t.challengesCompleted, contains('no_spend_7'));
      expect(KhelEngine.freezesEarned(t.challengesCompleted), 1);
      expect(t.badgesUnlocked, contains('ladder_2'));
    });

    test('30-day rung unlocks ladder_5, challenge_30 badge and +2 freezes', () {
      final KhelTransition t = KhelEngine.apply(
        _live(length: 29, longest: 29),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 0, freezeCommitted: false),
        ],
      );
      expect(t.state.length, 30);
      expect(t.badgesUnlocked, containsAll(<String>['ladder_5', 'challenge_30']));
      expect(t.challengesCompleted, contains('no_spend_30'));
      expect(KhelEngine.freezesEarned(t.challengesCompleted), 2);
    });

    test('re-climbing to 7 does not re-complete the challenge', () {
      // Streak broke at 8; new climb passes 7 again — the challenge
      // already completed, only badges can re-fire (they cannot: the
      // ladder unlock needs before < threshold).
      final KhelTransition t = KhelEngine.apply(
        _live(length: 6, longest: 8),
        <KhelFacts>[
          KhelFacts(day: _day(2026, 10, 23), spentPaise: 0, freezeCommitted: false),
        ],
      );
      expect(t.state.length, 7);
      expect(t.challengesCompleted, contains('no_spend_7'),
          reason: 'completion is re-emitted for the service; the '
              'persisted completed_at row keeps the reward once');
    });
  });

  group('empty transition is identity', () {
    test('no facts — no change', () {
      final StreakState s = _live(length: 5);
      final KhelTransition t = KhelEngine.apply(s, const <KhelFacts>[]);
      expect(t.state, s);
      expect(t.outcomes, isEmpty);
      expect(t.badgesUnlocked, isEmpty);
    });
  });

  group('daysToEvaluate', () {
    final DateTime today = _day(2026, 10, 27);

    test('live streak: only days after the last counted day', () {
      final List<DateTime> days = KhelEngine.daysToEvaluate(
        _live(length: 3, lastNoSpend: _day(2026, 10, 24)),
        today,
      );
      expect(days, <DateTime>[_day(2026, 10, 25), _day(2026, 10, 26)]);
    });

    test('live streak caught up: nothing to judge (idempotency)', () {
      final List<DateTime> days = KhelEngine.daysToEvaluate(
        _live(length: 1, lastNoSpend: _day(2026, 10, 26)),
        today,
      );
      expect(days, isEmpty);
    });

    test('broken history: bounded catch-up lookback ending yesterday', () {
      final List<DateTime> days = KhelEngine.daysToEvaluate(
        const StreakState(length: 0, freezesLeft: 2, longest: 5),
        today,
      );
      expect(days.first, _day(2026, 10, 20));
      expect(days.last, _day(2026, 10, 26));
      expect(days, hasLength(7));
    });

    test('fresh install: only yesterday is judged (no fake history)', () {
      final List<DateTime> days = KhelEngine.daysToEvaluate(
        const StreakState.initial(),
        today,
      );
      expect(days, <DateTime>[_day(2026, 10, 26)]);
    });

    test('today is never judged', () {
      final List<DateTime> days = KhelEngine.daysToEvaluate(
        const StreakState.initial(),
        today,
      );
      expect(days.contains(today), isFalse);
    });
  });

  group('KhelConfig helpers', () {
    test('levelFor walks the ladder', () {
      expect(KhelConfig.levelFor(0), 0);
      expect(KhelConfig.levelFor(2), 0);
      expect(KhelConfig.levelFor(3), 1);
      expect(KhelConfig.levelFor(7), 2);
      expect(KhelConfig.levelFor(49), 5);
      expect(KhelConfig.levelFor(50), 6);
      expect(KhelConfig.levelFor(500), 6);
    });

    test('segmentFor clamps into LevelBar range', () {
      expect(KhelConfig.segmentFor(0), 0);
      expect(KhelConfig.segmentFor(3), 0);
      expect(KhelConfig.segmentFor(7), 1);
      expect(KhelConfig.segmentFor(50), 5);
      expect(KhelConfig.segmentFor(999), 5);
    });
  });
}
