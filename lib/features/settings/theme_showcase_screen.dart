// phase-01
// Theme showcase — debug/QA screen (SHOWCASE=true dart-define or
// debug builds). Every token + component on one scroll, with a live
// dark/light flip. The paired goldens (375×812 / 412×915) screenshot
// this screen in both modes.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/udao_theme.dart';
import '../../core/theme/udao_spacing.dart';
import '../../core/theme/udao_typography.dart';
import '../../core/theme/udao_theme_extension.dart';
import '../../core/ui/app_icons.dart';
import '../../core/ui/chindi_badge.dart';
import '../../core/ui/level_bar.dart';
import '../../core/ui/money_display.dart';
import '../../core/ui/permission_priming_card.dart';
import '../../core/ui/roast_card.dart';
import '../../core/ui/section_header.dart';
import '../../core/ui/skeleton.dart';
import '../../core/ui/spend_bar.dart';
import '../../core/ui/stat_chip.dart';
import '../../core/ui/streak_flame.dart';
import '../../core/ui/udao_bottom_nav.dart';
import '../../core/ui/udao_button.dart';
import '../../core/ui/udao_card.dart';
import '../../core/ui/udao_dialog.dart';
import '../../core/ui/udao_snack_bar.dart';
import '../../core/ui/verdict_bell.dart';
import '../../core/utils/money.dart';
import '../../l10n/app_localizations.dart';

class ThemeShowcaseScreen extends StatefulWidget {
  const ThemeShowcaseScreen({super.key});

  @override
  State<ThemeShowcaseScreen> createState() => _ThemeShowcaseScreenState();
}

class _ThemeShowcaseScreenState extends State<ThemeShowcaseScreen> {
  bool _dark = true;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = _dark ? UdaoTheme.dark() : UdaoTheme.light();

    return Theme(
      data: theme,
      child: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          final TextTheme text = Theme.of(context).textTheme;
          final ColorScheme scheme = Theme.of(context).colorScheme;
          final UdaoSemantic sem = context.semantic;

          return Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(UdaoSpacing.lg),
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          l10n.showcaseTitle.toUpperCase(),
                          style: text.displaySmall?.copyWith(
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      UdaoButton(
                        label: l10n.showcaseToggleTheme,
                        variant: UdaoButtonVariant.glass,
                        size: UdaoButtonSize.sm,
                        onTap: () => setState(() => _dark = !_dark),
                      ),
                    ],
                  ),
                  const SizedBox(height: UdaoSpacing.xl),

                  // ── 01 COLORS ─────────────────────────────────────
                  SectionHeader(number: '01', label: l10n.showcaseSectionColors),
                  _SwatchGrid(
                    swatches: <(String, Color)>[
                      ('primary', scheme.primary),
                      ('onPrimary', scheme.onPrimary),
                      ('surface', scheme.surface),
                      ('surfaceHighest', scheme.surfaceContainerHighest),
                      ('onSurface', scheme.onSurface),
                      ('onVariant', scheme.onSurfaceVariant),
                      ('error', scheme.error),
                      ('flame', sem.flame),
                      ('flameVivid', sem.flameVivid),
                      ('lime', sem.lime),
                      ('gold', sem.gold),
                      ('sky', sem.sky),
                      ('violet', sem.violet),
                      ('success', sem.success),
                      ('cardBorder', sem.cardBorder),
                      ('skeleton', sem.skeleton),
                    ],
                  ),
                  const SizedBox(height: UdaoSpacing.xxl),

                  // ── 02 TYPOGRAPHY ─────────────────────────────────
                  SectionHeader(
                    number: '02',
                    label: l10n.showcaseSectionTypography,
                  ),
                  _TypeRow(
                    label: 'Display L 48',
                    style: text.displayLarge,
                    color: scheme.onSurface,
                  ),
                  _TypeRow(
                    label: 'Display M 40',
                    style: text.displayMedium,
                    color: scheme.onSurface,
                  ),
                  _TypeRow(
                    label: 'Display S 28',
                    style: text.displaySmall,
                    color: scheme.onSurface,
                  ),
                  _TypeRow(
                    label: 'Headline M 24',
                    style: text.headlineMedium,
                    color: scheme.onSurface,
                  ),
                  _TypeRow(
                    label: 'Headline S 18',
                    style: text.headlineSmall,
                    color: scheme.onSurface,
                  ),
                  _TypeRow(
                    label: 'Title L 18',
                    style: text.titleLarge,
                    color: scheme.onSurface,
                  ),
                  _TypeRow(
                    label: 'Body M',
                    style: text.bodyMedium,
                    color: scheme.onSurfaceVariant,
                  ),
                  _TypeRow(
                    label: 'Label L caps',
                    style: text.labelLarge,
                    color: sem.flame,
                  ),
                  _TypeRow(
                    label: 'Label S caps',
                    style: text.labelSmall,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: UdaoSpacing.xxl),

                  // ── 03 BUTTONS ────────────────────────────────────
                  SectionHeader(
                    number: '03',
                    label: l10n.showcaseSectionButtons,
                  ),
                  Wrap(
                    spacing: UdaoSpacing.md,
                    runSpacing: UdaoSpacing.md,
                    children: <Widget>[
                      UdaoButton(label: 'FLAME', onTap: () {}),
                      UdaoButton(
                        label: 'LIME',
                        variant: UdaoButtonVariant.limeFilled,
                        onTap: () {},
                      ),
                      UdaoButton(
                        label: 'GLASS',
                        variant: UdaoButtonVariant.glass,
                        onTap: () {},
                      ),
                      UdaoButton(
                        label: 'DANGER',
                        variant: UdaoButtonVariant.danger,
                        onTap: () {},
                      ),
                      const UdaoButton(label: 'LOADING', loading: true),
                      const UdaoButton(label: 'OFF', onTap: null),
                    ],
                  ),
                  const SizedBox(height: UdaoSpacing.xxl),

                  // ── 04 CARDS ──────────────────────────────────────
                  SectionHeader(
                    number: '04',
                    label: l10n.showcaseSectionCards,
                  ),
                  UdaoCard(
                    child: Text(
                      'PLAIN CARD',
                      style: text.titleMedium
                          ?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: UdaoSpacing.md),
                  UdaoCard(
                    accent: UdaoCardAccent.flame,
                    child: Text(
                      'FLAME ACCENT',
                      style: text.titleMedium
                          ?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: UdaoSpacing.md),
                  UdaoCard(
                    accent: UdaoCardAccent.lime,
                    child: Text(
                      'LIME ACCENT',
                      style: text.titleMedium
                          ?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: UdaoSpacing.xxl),

                  // ── 05 MONEY ──────────────────────────────────────
                  SectionHeader(
                    number: '05',
                    label: l10n.showcaseSectionMoney,
                  ),
                  MoneyDisplay(
                    money: Money.fromRupees(420, paise: 69),
                    delta: Money.fromRupees(-55),
                    hero: true,
                  ),
                  const SizedBox(height: UdaoSpacing.md),
                  MoneyDisplay(
                    money: Money.fromRupees(1234, paise: 50),
                    delta: Money.fromRupees(80),
                  ),
                  const SizedBox(height: UdaoSpacing.md),
                  MoneyDisplay(money: Money.fromRupees(99), compact: true),
                  const SizedBox(height: UdaoSpacing.xxl),

                  // ── 06 ROAST ──────────────────────────────────────
                  SectionHeader(
                    number: '06',
                    label: l10n.showcaseSectionRoast,
                  ),
                  RoastCard(
                    roastLine:
                        'Aaj 420 rupaye chai mein udaye. Zinda rehna hai toh samjha kar.',
                    meta: 'AAJ · 8:30 PM',
                    severityLabel: 'TAPAK SEVERE',
                    shareLabel: l10n.shareAction,
                    amount: Money.fromRupees(420),
                    onTap: () {},
                    onShare: () {},
                  ),
                  const SizedBox(height: UdaoSpacing.xxl),

                  // ── 07 STATS ──────────────────────────────────────
                  SectionHeader(
                    number: '07',
                    label: l10n.showcaseSectionStats,
                  ),
                  const Wrap(
                    spacing: UdaoSpacing.md,
                    runSpacing: UdaoSpacing.md,
                    children: <Widget>[
                      StatChip(
                        label: 'AAJ UDA',
                        value: '₹420',
                        trendUp: false,
                      ),
                      StatChip(
                        label: 'BACHAYA',
                        value: '₹1.2k',
                        trendUp: true,
                      ),
                      StatChip(label: 'ENTRIES', value: '12'),
                    ],
                  ),
                  const SizedBox(height: UdaoSpacing.lg),
                  SpendBar(
                    label: 'CHAI',
                    spent: Money.fromRupees(180),
                    budget: Money.fromRupees(500),
                  ),
                  const SizedBox(height: UdaoSpacing.md),
                  SpendBar(
                    label: 'SWIGGY',
                    spent: Money.fromRupees(860),
                    budget: Money.fromRupees(600),
                  ),
                  const SizedBox(height: UdaoSpacing.xxl),

                  // ── 08 GAME ───────────────────────────────────────
                  SectionHeader(
                    number: '08',
                    label: l10n.showcaseSectionGame,
                  ),
                  const Row(
                    children: <Widget>[
                      ChindiBadge(level: 4),
                      SizedBox(width: UdaoSpacing.md),
                      ChindiBadge(level: 5, justUnlocked: true),
                      SizedBox(width: UdaoSpacing.md),
                      ChindiBadge(level: 6, unlocked: false),
                    ],
                  ),
                  const SizedBox(height: UdaoSpacing.lg),
                  const LevelBar(
                    currentIndex: 3,
                    label: 'CHINDI LADDER · LEVEL 4/6',
                  ),
                  const SizedBox(height: UdaoSpacing.lg),
                  StreakFlame(
                    days: 12,
                    freezeAvailable: true,
                    unitLabel: l10n.streakUnit,
                  ),
                  const SizedBox(height: UdaoSpacing.xxl),

                  // ── 09 FEEDBACK ───────────────────────────────────
                  SectionHeader(
                    number: '09',
                    label: l10n.showcaseSectionFeedback,
                  ),
                  const SkeletonLine(lines: 3),
                  const SizedBox(height: UdaoSpacing.md),
                  const SkeletonBlock(height: 64),
                  const SizedBox(height: UdaoSpacing.lg),
                  Wrap(
                    spacing: UdaoSpacing.md,
                    runSpacing: UdaoSpacing.md,
                    children: <Widget>[
                      UdaoButton(
                        label: 'SNACK ROAST',
                        size: UdaoButtonSize.sm,
                        onTap: () => UdaoSnackBar.show(
                          context,
                          message: 'Bhai, Budget<int> se bahar ho gaya tu.',
                          intent: UdaoSnackBarIntent.roast,
                        ),
                      ),
                      UdaoButton(
                        label: 'SNACK WARN',
                        variant: UdaoButtonVariant.limeFilled,
                        size: UdaoButtonSize.sm,
                        onTap: () => UdaoSnackBar.show(
                          context,
                          message: 'Kal tak bill bhar de, warna pitega.',
                          intent: UdaoSnackBarIntent.warn,
                        ),
                      ),
                      UdaoButton(
                        label: 'DIALOG',
                        variant: UdaoButtonVariant.glass,
                        size: UdaoButtonSize.sm,
                        onTap: () {
                          unawaited(
                            UdaoDialog.show(
                              context: context,
                              title: 'Pakka?',
                              child: Text(
                                'Ye final jawab hai tera?',
                                style: text.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              ctaLabel: 'HN PAKKA',
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: UdaoSpacing.xxl),

                  // ── 10 NAV + NOTIF ────────────────────────────────
                  SectionHeader(
                    number: '10',
                    label: l10n.showcaseSectionNav,
                  ),
                  VerdictBell(
                    appName: l10n.appName,
                    title: l10n.obNotifDemoTitle,
                    body: l10n.obNotifDemoBody,
                    timeLabel: '8:30 PM',
                  ),
                  const SizedBox(height: UdaoSpacing.lg),
                  PermissionPrimingCard(
                    title: l10n.obNotifTitle,
                    body: l10n.obNotifBody,
                    ctaLabel: l10n.obNotifCta,
                    secondaryLabel: l10n.obNotifLater,
                    iconAsset: AppIcons.verdictBell,
                  ),
                  const SizedBox(height: UdaoSpacing.lg),
                  UdaoBottomNav(
                    currentIndex: 2,
                    onTap: (int i) {},
                    items: <UdaoNavItem>[
                      UdaoNavItem(
                        label: l10n.navAaj,
                        svgAsset: AppIcons.roastFlame,
                      ),
                      UdaoNavItem(
                        label: l10n.navChat,
                        svgAsset: AppIcons.logoMark,
                      ),
                      UdaoNavItem(
                        label: l10n.navKhel,
                        svgAsset: AppIcons.ladder,
                      ),
                      UdaoNavItem(
                        label: l10n.navLedger,
                        svgAsset: AppIcons.verdictBell,
                      ),
                      UdaoNavItem(
                        label: l10n.navSettings,
                        svgAsset: AppIcons.streakFlame,
                      ),
                    ],
                  ),
                  const SizedBox(height: UdaoSpacing.xxl),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SwatchGrid extends StatelessWidget {
  const _SwatchGrid({required this.swatches});

  final List<(String, Color)> swatches;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final UdaoSemantic sem = context.semantic;

    return Wrap(
      spacing: UdaoSpacing.md,
      runSpacing: UdaoSpacing.md,
      children: <Widget>[
        for (final (String label, Color color) in swatches)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(UdaoRadius.md),
                  border: Border.all(color: sem.cardBorder),
                ),
              ),
              const SizedBox(height: UdaoSpacing.xs),
              Text(
                label.toUpperCase(),
                style: text.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.label, required this.style, this.color});

  final String label;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UdaoSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFamily: UdaoTypography.inter,
            ),
          ),
          Text(
            'Paisa udta hai ₹1,23,456',
            style: style?.copyWith(color: color ?? scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
