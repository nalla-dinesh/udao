// phase-07
// Khel definitions — the Chindi Ladder, badge catalog, challenges.
// Pure data, no IO: the engine and the UI both read from here so the
// rules can never drift between logic and display.
//
// Ladder semantics: a level unlocks while the CURRENT streak length
// has reached its threshold (the ladder is the climb, not the
// trophy case — badges are the trophies).
import 'package:flutter/foundation.dart';

@immutable
class LadderLevel {
  const LadderLevel({
    required this.index,
    required this.days,
    required this.nameKey,
  });

  /// 1-based level number (also the ChindiBadge label).
  final int index;

  /// Streak days needed to stand on this level.
  final int days;

  /// l10n key suffix for the level name.
  final String nameKey;
}

@immutable
class BadgeDef {
  const BadgeDef({
    required this.id,
    required this.nameKey,
    required this.descKey,
  });

  /// Stable persistence id (badge table primary key).
  final String id;

  /// l10n key suffixes.
  final String nameKey;
  final String descKey;
}

@immutable
class ChallengeDef {
  const ChallengeDef({
    required this.id,
    required this.metric,
    required this.target,
    required this.rewardFreezes,
  });

  /// challenge_progress row id.
  final String id;

  /// Machine metric key (currently only `no_spend_days`).
  final String metric;

  /// Target value for completion.
  final int target;

  /// Freeze tokens earned ONCE on completion.
  final int rewardFreezes;
}

abstract final class KhelConfig {
  /// The Chindi Ladder — 6 rungs, mirroring LevelBar's 6 segments.
  static const List<LadderLevel> ladder = <LadderLevel>[
    LadderLevel(index: 1, days: 3, nameKey: 'khelLevel1'),
    LadderLevel(index: 2, days: 7, nameKey: 'khelLevel2'),
    LadderLevel(index: 3, days: 14, nameKey: 'khelLevel3'),
    LadderLevel(index: 4, days: 21, nameKey: 'khelLevel4'),
    LadderLevel(index: 5, days: 30, nameKey: 'khelLevel5'),
    LadderLevel(index: 6, days: 50, nameKey: 'khelLevel6'),
  ];

  /// Minimum live-streak length before the UI offers a freeze.
  /// Protecting a 1-day streak is noise, not strategy.
  static const int freezeMinStreak = 3;

  /// Days looked back for a first/no streak evaluation window.
  static const int lookbackDaysNoStreak = 7;

  /// kv key holding the ISO-day ms the user pre-committed a freeze to.
  static const String kvFreezePending = 'khel.freeze.pending';

  /// Challenge catalog.
  static const List<ChallengeDef> challenges = <ChallengeDef>[
    ChallengeDef(
      id: 'no_spend_7',
      metric: 'no_spend_days',
      target: 7,
      rewardFreezes: 1,
    ),
    ChallengeDef(
      id: 'no_spend_30',
      metric: 'no_spend_days',
      target: 30,
      rewardFreezes: 2,
    ),
  ];

  /// Badge catalog (order = display order).
  static const List<BadgeDef> badges = <BadgeDef>[
    BadgeDef(
      id: 'first_day',
      nameKey: 'khelBadgeFirstDay',
      descKey: 'khelBadgeFirstDayDesc',
    ),
    BadgeDef(id: 'ladder_1', nameKey: 'khelBadgeL1', descKey: 'khelBadgeL1Desc'),
    BadgeDef(id: 'ladder_2', nameKey: 'khelBadgeL2', descKey: 'khelBadgeL2Desc'),
    BadgeDef(id: 'ladder_3', nameKey: 'khelBadgeL3', descKey: 'khelBadgeL3Desc'),
    BadgeDef(id: 'ladder_4', nameKey: 'khelBadgeL4', descKey: 'khelBadgeL4Desc'),
    BadgeDef(id: 'ladder_5', nameKey: 'khelBadgeL5', descKey: 'khelBadgeL5Desc'),
    BadgeDef(id: 'ladder_6', nameKey: 'khelBadgeL6', descKey: 'khelBadgeL6Desc'),
    BadgeDef(
      id: 'comeback',
      nameKey: 'khelBadgeComeback',
      descKey: 'khelBadgeComebackDesc',
    ),
    BadgeDef(
      id: 'freeze_first',
      nameKey: 'khelBadgeFreeze',
      descKey: 'khelBadgeFreezeDesc',
    ),
    BadgeDef(
      id: 'challenge_30',
      nameKey: 'khelBadgeChallenge30',
      descKey: 'khelBadgeChallenge30Desc',
    ),
  ];

  /// Ladder level for a given live streak length (0 = not on the
  /// ladder yet). Highest threshold reached wins.
  static int levelFor(int streakLength) {
    int level = 0;
    for (final LadderLevel l in ladder) {
      if (streakLength >= l.days) {
        level = l.index;
      }
    }
    return level;
  }

  /// 0-based LevelBar segment index for a live streak length.
  static int segmentFor(int streakLength) =>
      (levelFor(streakLength) - 1).clamp(0, ladder.length - 1);
}
