// phase-01 (phase-04: freeze; phase-05: evaluation; phase-07 UI
// pass: StreakFlame hero + accent-coded section cards).
//
// Khel — the game screen: no-spend streak, the Chindi Ladder,
// freezes, challenges, badges. Reads one KhelSnapshot per visit and
// refreshes live on every captured txn (same event-driven pattern
// as Aaj/Ledger). No animated loading states — see the Aaj note
// about pumpAndSettle and the fake-async zone.
import 'dart:async';

import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../data/models/badge.dart';
import '../../../core/theme/udao_spacing.dart';
import '../../../core/theme/udao_theme_extension.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/app_svg.dart';
import '../../../core/ui/chindi_badge.dart';
import '../../../core/ui/level_bar.dart';
import '../../../core/ui/streak_flame.dart';
import '../../../core/ui/udao_button.dart';
import '../../../core/ui/udao_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../capture/capture_providers.dart'
    show ledgerEventsProvider, txnDaoProvider;
import '../../khel/khel_config.dart';
import '../../khel/khel_providers.dart';
import '../../khel/khel_service.dart';

class KhelScreen extends ConsumerStatefulWidget {
  const KhelScreen({super.key});

  @override
  ConsumerState<KhelScreen> createState() => _KhelScreenState();
}

class _KhelScreenState extends ConsumerState<KhelScreen> {
  KhelSnapshot? _snap;
  StreamSubscription<dynamic>? _events;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _events = ref
        .read(ledgerEventsProvider)
        .stream
        .listen((_) => unawaited(_load()));
  }

  @override
  void dispose() {
    unawaited(_events?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _load() async {
    final KhelSnapshot snap =
        await ref.read(khelServiceProvider).snapshot();
    if (mounted) {
      setState(() => _snap = snap);
    }
  }

  Future<void> _commitFreeze() async {
    await ref.read(khelServiceProvider).commitFreezeForToday();
    await _load();
  }

  Future<void> _badgeTap(String id) async {
    await ref.read(khelServiceProvider).markBadgeSeen(id);
    await _load();
  }

  String _rupees(int paise) {
    final int r = paise ~/ 100;
    final int p = paise % 100;
    return p == 0 ? '$r' : '$r.${p.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final KhelSnapshot? snap = _snap;
    if (snap == null) {
      // Static placeholder — never an animated one (see file header).
      return const Scaffold(body: SafeArea(child: SizedBox.expand()));
    }

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(UdaoSpacing.xl),
            children: <Widget>[
              _StreakHero(snap: snap, rupees: _rupees),
              const SizedBox(height: UdaoSpacing.md),
              _TodayCard(
                snap: snap,
                rupees: _rupees,
                onFreeze: _commitFreeze,
              ),
              const SizedBox(height: UdaoSpacing.md),
              _LadderCard(snap: snap),
              const SizedBox(height: UdaoSpacing.md),
              _ChallengesCard(snap: snap),
              const SizedBox(height: UdaoSpacing.md),
              _BadgesCard(snap: snap, onTap: _badgeTap),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Streak hero ─────────────────────────────────────────────────────

/// Flame-accent hero: StreakFlame (big animated-size flame + day
/// count) plus longest/freezes stats on the trailing edge.
class _StreakHero extends StatelessWidget {
  const _StreakHero({required this.snap, required this.rupees});

  final KhelSnapshot snap;
  final String Function(int paise) rupees;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return UdaoCard(
      accent: UdaoCardAccent.flame,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.khelTitle.toUpperCase(),
            style: text.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: UdaoSpacing.md),
          StreakFlame(
            days: snap.state.length,
            freezeAvailable: snap.state.freezesLeft > 0,
            unitLabel: l10n.streakUnit,
          ),
          const SizedBox(height: UdaoSpacing.md),
          Text(
            l10n.khelStreakLabel,
            style: text.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: UdaoSpacing.lg),
          Row(
            children: <Widget>[
              _Stat(
                label: l10n.khelLongestLabel,
                value: '${snap.state.longest}',
                icon: PhosphorIconsBold.trophy,
              ),
              const SizedBox(width: UdaoSpacing.xl),
              _Stat(
                label: l10n.khelFreezesLabel,
                value: '${snap.state.freezesLeft}',
                icon: PhosphorIconsBold.snowflake,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final UdaoSemantic sem = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UdaoSpacing.md,
        vertical: UdaoSpacing.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(UdaoRadius.pill),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PhosphorIcon(icon, size: 16, color: sem.flame),
          const SizedBox(width: UdaoSpacing.sm),
          Text(value, style: text.titleMedium),
          const SizedBox(width: UdaoSpacing.xs),
          Text(
            label,
            style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Today card ──────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.snap,
    required this.rupees,
    required this.onFreeze,
  });

  final KhelSnapshot snap;
  final String Function(int paise) rupees;
  final Future<void> Function() onFreeze;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UdaoSemantic sem = context.semantic;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final bool spentToday = snap.todaySpendPaise > 0;
    final bool canFreeze = snap.state.freezesLeft > 0 &&
        snap.state.length >= KhelConfig.freezeMinStreak;

    return UdaoCard(
      accent: UdaoCardAccent.gold,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              PhosphorIcon(
                spentToday
                    ? PhosphorIconsBold.fireSimple
                    : PhosphorIconsBold.sealCheck,
                size: 20,
                color: spentToday ? sem.gold : sem.lime,
              ),
              const SizedBox(width: UdaoSpacing.md),
              Expanded(
                child: Text(
                  spentToday
                      ? (snap.freezeCommittedToday
                          ? l10n.khelTodaySpentFrozen(
                              rupees(snap.todaySpendPaise))
                          : l10n.khelTodaySpent(
                              rupees(snap.todaySpendPaise)))
                      : l10n.khelTodayClean(snap.state.length),
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          if (spentToday && !snap.freezeCommittedToday) ...<Widget>[
            const SizedBox(height: UdaoSpacing.md),
            if (canFreeze)
              UdaoButton(
                label: l10n.khelFreezeButton,
                size: UdaoButtonSize.sm,
                onTap: onFreeze,
              )
            else
              Text(
                l10n.khelNoFreezes,
                style: text.bodySmall?.copyWith(color: sem.flame),
              ),
          ],
          if (spentToday && snap.freezeCommittedToday) ...<Widget>[
            const SizedBox(height: UdaoSpacing.md),
            Row(
              children: <Widget>[
                Icon(PhosphorIconsBold.snowflake,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: UdaoSpacing.xs),
                Text(l10n.khelFreezeApplied,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Ladder ──────────────────────────────────────────────────────────

class _LadderCard extends StatelessWidget {
  const _LadderCard({required this.snap});

  final KhelSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    // Name of the highest level the CURRENT streak has reached.
    final int level = KhelConfig.levelFor(snap.state.length);
    final String levelName = level == 0
        ? l10n.khelLevel1
        : _levelName(l10n, level);

    return UdaoCard(
      accent: UdaoCardAccent.lime,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.khelLadderTitle,
              style: text.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: UdaoSpacing.md),
          LevelBar(
            currentIndex: KhelConfig.segmentFor(snap.state.length),
            segmentCount: KhelConfig.ladder.length,
            label: level == 0
                ? l10n.streakUnit
                : '$levelName · ${snap.state.length} ${l10n.streakUnit}',
          ),
          const SizedBox(height: UdaoSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              for (final LadderLevel l in KhelConfig.ladder)
                Column(
                  children: <Widget>[
                    ChindiBadge(
                      level: l.index,
                      unlocked: snap.state.length >= l.days,
                      size: 48,
                    ),
                    const SizedBox(height: UdaoSpacing.xs),
                    Text(
                      _levelName(l10n, l.index),
                      style: text.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _levelName(AppLocalizations l10n, int index) {
    switch (index) {
      case 1:
        return l10n.khelLevel1;
      case 2:
        return l10n.khelLevel2;
      case 3:
        return l10n.khelLevel3;
      case 4:
        return l10n.khelLevel4;
      case 5:
        return l10n.khelLevel5;
      case 6:
        return l10n.khelLevel6;
    }
    return l10n.khelLevel1;
  }
}

// ── Challenges ──────────────────────────────────────────────────────

class _ChallengesCard extends StatelessWidget {
  const _ChallengesCard({required this.snap});

  final KhelSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final UdaoSemantic sem = context.semantic;

    return UdaoCard(
      accent: UdaoCardAccent.sky,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.khelChallengesTitle,
              style: text.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: UdaoSpacing.md),
          for (final ChallengeDef c in KhelConfig.challenges) ...<Widget>[
            _ChallengeRow(
              label: l10n.khelChallengeLabel(
                _challengeCurrent(c),
                c.target,
                '${c.rewardFreezes}',
              ),
              value: _challengeCurrent(c),
              target: c.target,
              color: sem.sky,
            ),
            const SizedBox(height: UdaoSpacing.sm),
          ],
        ],
      ),
    );
  }

  int _challengeCurrent(ChallengeDef c) {
    ChallengeProgress? row;
    for (final ChallengeProgress p in snap.challenges) {
      if (p.id == c.id) {
        row = p;
        break;
      }
    }
    if (row != null && row.completedAt != null) {
      return c.target;
    }
    // Live streak feeds the meter until the challenge completes.
    return snap.state.length < c.target ? snap.state.length : c.target;
  }
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  final String label;
  final int value;
  final int target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: UdaoSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(UdaoRadius.pill),
          child: LinearProgressIndicator(
            value: target == 0 ? 0 : (value / target).clamp(0.0, 1.0),
            minHeight: 8,
            color: color,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

// ── Badges ──────────────────────────────────────────────────────────

class _BadgesCard extends StatelessWidget {
  const _BadgesCard({required this.snap, required this.onTap});

  final KhelSnapshot snap;
  final Future<void> Function(String id) onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;

    final Set<String> unlocked = snap.badges.map((Badge b) => b.id).toSet();
    final Set<String> seen =
        snap.badges.where((Badge b) => b.seen).map((Badge b) => b.id).toSet();

    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.khelBadgesTitle,
              style: text.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: UdaoSpacing.md),
          Wrap(
            spacing: UdaoSpacing.md,
            runSpacing: UdaoSpacing.md,
            children: <Widget>[
              for (final BadgeDef def in KhelConfig.badges)
                _BadgeTile(
                  name: _badgeName(l10n, def.id),
                  desc: _badgeDesc(l10n, def.id),
                  unlocked: unlocked.contains(def.id),
                  justUnlocked: unlocked.contains(def.id) && !seen.contains(def.id),
                  onTap: () => onTap(def.id),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _badgeName(AppLocalizations l10n, String id) {
    switch (id) {
      case 'first_day':
        return l10n.khelBadgeFirstDay;
      case 'ladder_1':
        return l10n.khelBadgeL1;
      case 'ladder_2':
        return l10n.khelBadgeL2;
      case 'ladder_3':
        return l10n.khelBadgeL3;
      case 'ladder_4':
        return l10n.khelBadgeL4;
      case 'ladder_5':
        return l10n.khelBadgeL5;
      case 'ladder_6':
        return l10n.khelBadgeL6;
      case 'comeback':
        return l10n.khelBadgeComeback;
      case 'freeze_first':
        return l10n.khelBadgeFreeze;
      case 'challenge_30':
        return l10n.khelBadgeChallenge30;
    }
    return id;
  }

  String _badgeDesc(AppLocalizations l10n, String id) {
    switch (id) {
      case 'first_day':
        return l10n.khelBadgeFirstDayDesc;
      case 'ladder_1':
        return l10n.khelBadgeL1Desc;
      case 'ladder_2':
        return l10n.khelBadgeL2Desc;
      case 'ladder_3':
        return l10n.khelBadgeL3Desc;
      case 'ladder_4':
        return l10n.khelBadgeL4Desc;
      case 'ladder_5':
        return l10n.khelBadgeL5Desc;
      case 'ladder_6':
        return l10n.khelBadgeL6Desc;
      case 'comeback':
        return l10n.khelBadgeComebackDesc;
      case 'freeze_first':
        return l10n.khelBadgeFreezeDesc;
      case 'challenge_30':
        return l10n.khelBadgeChallenge30Desc;
    }
    return id;
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.name,
    required this.desc,
    required this.unlocked,
    required this.justUnlocked,
    required this.onTap,
  });

  final String name;
  final String desc;
  final bool unlocked;
  final bool justUnlocked;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Semantics(
      label: '$name — $desc',
      enabled: unlocked,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(UdaoRadius.card),
        child: Container(
          width: 128,
          padding: const EdgeInsets.all(UdaoSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(UdaoRadius.card),
            gradient: unlocked
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      sem.flame.withValues(alpha: 0.10),
                      scheme.surface,
                    ],
                  )
                : null,
            color: unlocked
                ? null
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: Border.all(
              color: justUnlocked ? sem.lime : sem.cardBorder,
              width: justUnlocked ? 2 : 1,
            ),
          ),
          child: Column(
            children: <Widget>[
              AppSvg(
                AppIcons.chindiBadge,
                width: 40,
                height: 40,
                color: unlocked ? sem.flame : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: UdaoSpacing.sm),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelLarge?.copyWith(
                  color: unlocked ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: UdaoSpacing.xs),
              Text(
                desc,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
