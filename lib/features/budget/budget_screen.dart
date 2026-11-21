// phase-08
// Budget screen — the Lakshman Rekha. Wallet hero (remaining money
// in huge Syne numerals + SpendBar + days left), category lines
// below, exceeded lines go flame. Live refresh on every captured
// txn. No animated loading states (the Aaj fake-async law); while
// the snapshot is in flight the empty state renders optimistically.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/errors/failure.dart';
import '../../core/result/result.dart' show Result;
import '../../core/theme/udao_colors.dart';
import '../../core/theme/udao_spacing.dart';
import '../../core/theme/udao_theme_extension.dart';
import '../../core/ui/app_icons.dart';
import '../../core/ui/app_svg.dart';
import '../../core/ui/money_display.dart';
import '../../core/ui/section_header.dart';
import '../../core/ui/spend_bar.dart';
import '../../core/ui/udao_card.dart';
import '../../core/ui/udao_empty_state.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/money.dart';
import '../../data/models/category.dart';
import '../../data/repos/query_repos.dart';
import '../../l10n/app_localizations.dart';
import '../capture/capture_providers.dart' show ledgerEventsProvider;
import '../capture/pipeline/ledger_events.dart';
import 'budget_edit_sheet.dart';
import 'budget_providers.dart';
import 'budget_service.dart';

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  BudgetSnapshot? _snap;
  Failure? _error;
  StreamSubscription<TxnCaptured>? _events;

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
    final Result<BudgetSnapshot> snap =
        await ref.read(budgetServiceProvider).snapshot();
    if (!mounted) {
      return;
    }
    snap.when(
      ok: (BudgetSnapshot s) => setState(() {
        _snap = s;
        _error = null;
      }),
      err: (Failure f) => setState(() {
        _snap = const BudgetSnapshot(
          statuses: <BudgetStatus>[],
          categories: <Category>[],
        );
        _error = f;
      }),
    );
  }

  Future<void> _openSheet({BudgetStatus? status}) async {
    await showBudgetSheet(context, existing: status?.budget);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UdaoSemantic sem = context.semantic;

    final BudgetSnapshot? snap = _snap;
    // Same rule as Aaj: optimistic empty state while in flight —
    // never an animated loading state (pumpAndSettle law).
    final bool empty = snap == null || snap.statuses.isEmpty;

    return Scaffold(
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_openSheet()),
        backgroundColor: sem.flame,
        foregroundColor: UdaoColors.ink,
        elevation: 0,
        highlightElevation: 0,
        shape: const StadiumBorder(),
        icon: const Icon(PhosphorIconsBold.plus),
        label: Text(l10n.budgetNewCta),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: empty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: <Widget>[
                    const SizedBox(height: 96),
                    UdaoEmptyState(
                      illustration: AppIcons.jar,
                      title: l10n.budgetEmptyTitle,
                      body: _error == null
                          ? l10n.budgetEmptyBody
                          : '${l10n.budgetEmptyBody}\n($_error)',
                    ),
                  ],
                )
              : _BudgetList(
                  snap: snap!,
                  error: _error,
                  onEdit: _openSheet,
                ),
        ),
      ),
    );
  }
}

class _BudgetList extends StatelessWidget {
  const _BudgetList({
    required this.snap,
    required this.error,
    required this.onEdit,
  });

  final BudgetSnapshot snap;
  final Failure? error;
  final Future<void> Function({BudgetStatus? status}) onEdit;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BudgetStatus? wallet = snap.wallet;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(UdaoSpacing.xl),
      children: <Widget>[
        if (wallet != null) ...<Widget>[
          SectionHeader(label: l10n.budgetTitle, number: '01'),
          _WalletHero(
            status: wallet,
            walletLabel: l10n.budgetWalletLabel,
            daysLeftLabel: l10n.budgetDaysLeft(snap.walletDaysLeft ?? 0),
            carryLabel: _carryLabel(l10n, wallet),
          ),
          const SizedBox(height: UdaoSpacing.lg),
        ],
        if (snap.byCategory.isNotEmpty) ...<Widget>[
          SectionHeader(
            label: l10n.budgetSectionCategories,
            number: wallet == null ? '01' : '02',
          ),
          for (final BudgetStatus s in snap.byCategory)
            Padding(
              padding: const EdgeInsets.only(bottom: UdaoSpacing.md),
              child: _CategoryCard(
                status: s,
                name: _categoryName(snap, s),
                daysLeftLabel: l10n.budgetDaysLeft(_daysLeftOf(s) ?? 0),
                carryLabel: _carryLabel(l10n, s),
                onTap: () => unawaited(onEdit(status: s)),
              ),
            ),
        ],
        if (error != null)
          Text(
            '($error)',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: UdaoSpacing.xxl),
      ],
    );
  }

  static String _categoryName(BudgetSnapshot snap, BudgetStatus s) {
    for (final Category c in snap.categories) {
      if (c.id == s.budget.categoryId) {
        return c.name;
      }
    }
    return s.budget.categoryId ?? '';
  }

  /// Calendar days left in this budget's own window (inclusive).
  static int? _daysLeftOf(BudgetStatus s) {
    final DateTime? end = s.windowEnd;
    if (end == null) {
      return null;
    }
    final DateTime today = IstDates.startOfDay(IstDates.nowIst());
    final int left =
        IstDates.startOfDay(end).difference(today).inDays + 1;
    return left < 0 ? 0 : left;
  }

  static String _carryLabel(AppLocalizations l10n, BudgetStatus s) {
    if (s.carry.paise <= 0) {
      return '';
    }
    return l10n.budgetCarryChip('+${_rupees(s.carry)}');
  }

  static String _rupees(Money m) {
    final int r = m.paise ~/ 100;
    final int p = m.paise % 100;
    return p == 0 ? '₹$r' : '₹$r.${p.toString().padLeft(2, '0')}';
  }
}

/// The wallet hero: how much is LEFT this period, in huge numerals,
/// under the spend bar. Crossed lines flip to flame with a stamp.
class _WalletHero extends StatelessWidget {
  const _WalletHero({
    required this.status,
    required this.walletLabel,
    required this.daysLeftLabel,
    required this.carryLabel,
  });

  final BudgetStatus status;
  final String walletLabel;
  final String daysLeftLabel;
  final String carryLabel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    final bool exceeded = status.exceeded;

    return Container(
      padding: const EdgeInsets.all(UdaoSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(UdaoRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            (exceeded ? sem.flame : sem.lime).withValues(alpha: 0.16),
            scheme.surfaceContainerLow,
          ],
        ),
        border: Border.all(
          color: (exceeded ? sem.flame : sem.lime).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppSvg(
                AppIcons.jar,
                width: 28,
                height: 28,
                color: exceeded ? sem.flame : sem.lime,
              ),
              const SizedBox(width: UdaoSpacing.md),
              Expanded(
                child: Text(
                  walletLabel.toUpperCase(),
                  style: text.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 2,
                  ),
                ),
              ),
              if (exceeded)
                _Stamp(
                  label: l10n.budgetExceededStamp,
                  color: sem.flame,
                ),
            ],
          ),
          const SizedBox(height: UdaoSpacing.md),
          MoneyDisplay(money: status.remaining, hero: true),
          const SizedBox(height: UdaoSpacing.md),
          SpendBar(
            label: '${l10n.budgetLeftLabel} · $daysLeftLabel',
            spent: status.spent,
            budget: status.effectiveLimit,
          ),
          if (carryLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: UdaoSpacing.xs),
            Text(
              carryLabel,
              style: text.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// One category line: name + spend bar + remaining, edit on tap.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.status,
    required this.name,
    required this.daysLeftLabel,
    required this.carryLabel,
    required this.onTap,
  });

  final BudgetStatus status;
  final String name;
  final String daysLeftLabel;
  final String carryLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;
    final bool exceeded = status.exceeded;

    return UdaoCard(
      accent: exceeded ? UdaoCardAccent.flame : UdaoCardAccent.none,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (exceeded)
                _Stamp(
                  label: AppLocalizations.of(context).budgetExceededStamp,
                  color: sem.flame,
                )
              else
                Icon(
                  PhosphorIconsBold.pencilSimple,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: UdaoSpacing.md),
          SpendBar(
            label: '${status.remaining.formatPlain()} · $daysLeftLabel',
            spent: status.spent,
            budget: status.effectiveLimit,
          ),
          if (carryLabel.isNotEmpty) ...<Widget>[
            const SizedBox(height: UdaoSpacing.xs),
            Text(
              carryLabel,
              style: text.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small rotated severity stamp (the roast-card look).
class _Stamp extends StatelessWidget {
  const _Stamp({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UdaoSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        label,
        style: text.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
