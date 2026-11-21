// phase-01 (phase-04: QuickAdd FAB; phase-06: live read-back;
// phase-07 UI pass: hero card + TxnRow list)
//
// Aaj — the daily money screen. A gradient hero shows today's total
// with a count-up MoneyDisplay and a vs-yesterday delta; the day's
// movement renders as TxnRows. Reads the encrypted ledger live and
// refreshes on every captured txn. No animated loading states (see
// the fake-async note); skeletons are the app's loading language.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/routes.dart';
import '../../../core/errors/failure.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/money_display.dart';
import '../../../core/ui/section_header.dart';
import '../../../core/ui/spend_bar.dart';
import '../../../core/ui/txn_row.dart';
import '../../../core/ui/udao_card.dart';
import '../../../core/ui/udao_empty_state.dart';
import '../../../core/theme/udao_colors.dart';
import '../../../core/theme/udao_spacing.dart';
import '../../../core/theme/udao_theme_extension.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../core/result/result.dart' show Result;
import '../../../data/models/budget.dart' show Budget;
import '../../../data/models/txn.dart';
import '../../../data/repos/query_repos.dart' show BudgetStatus;
import '../../../l10n/app_localizations.dart';
import '../../capture/capture_providers.dart'
    show ledgerEventsProvider, txnDaoProvider;
import '../../capture/pipeline/ledger_events.dart';
import '../../capture/quick/quick_add_sheet.dart';
import '../../../data/repos/providers.dart' show budgetRepoProvider;

class AajScreen extends ConsumerStatefulWidget {
  const AajScreen({super.key});

  @override
  ConsumerState<AajScreen> createState() => _AajScreenState();
}

class _AajScreenState extends ConsumerState<AajScreen> {
  List<Txn>? _txns;
  Failure? _error;
  Money _yesterdayTotal = const Money.zero();
  StreamSubscription<TxnCaptured>? _events;

  /// Phase-08: the wallet Lakshman Rekha, when one exists.
  BudgetStatus? _walletBudget;

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
    final DateTime now = IstDates.nowIst();
    final today = await ref.read(txnDaoProvider).page(
          from: IstDates.startOfDay(now),
          to: IstDates.endOfDay(now),
          limit: 100,
        );
    final yesterday = await ref.read(txnDaoProvider).page(
          from: IstDates.startOfDay(now).subtract(const Duration(days: 1)),
          to: IstDates.endOfDay(
            IstDates.startOfDay(now).subtract(const Duration(days: 1)),
          ),
          limit: 100,
        );
    // Phase-08: wallet budget status for the rekha strip (best-effort
    // — a missing budget just hides the card).
    BudgetStatus? wallet;
    final budgets = await ref.read(budgetRepoProvider).all();
    for (final b in budgets.valueOrNull ?? const <Budget>[]) {
      if (b.categoryId == null) {
        final Result<BudgetStatus> status =
            await ref.read(budgetRepoProvider).statusOf(b);
        wallet = status.valueOrNull;
        break;
      }
    }
    if (!mounted) {
      return;
    }
    _walletBudget = wallet;
    final List<Txn>? yRows = yesterday.valueOrNull;
    _yesterdayTotal = yRows == null
        ? const Money.zero()
        : yRows
            .where((Txn t) => t.direction == TxnDirection.debit)
            .fold(const Money.zero(), (Money a, Txn t) => a + t.amount);
    today.when(
      ok: (List<Txn> rows) => setState(() {
        _txns = rows;
        _error = null;
      }),
      err: (Failure f) => setState(() {
        _txns = const <Txn>[];
        _error = f;
      }),
    );
  }

  Future<void> _openQuickAdd() async {
    await showQuickAddSheet(context);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final UdaoSemantic sem = context.semantic;

    final List<Txn>? txns = _txns;
    final List<Txn> rows = txns ?? const <Txn>[];
    final Money spentToday = rows
        .where((Txn t) => t.direction == TxnDirection.debit)
        .fold(const Money.zero(), (Money a, Txn t) => a + t.amount);
    final Money delta = spentToday - _yesterdayTotal;

    return Scaffold(
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQuickAdd,
        backgroundColor: sem.flame,
        foregroundColor: UdaoColors.ink,
        elevation: 0,
        highlightElevation: 0,
        shape: const StadiumBorder(),
        icon: const Icon(PhosphorIconsBold.plus),
        label: Text(l10n.quickAddFabLabel),
      ),
      body: SafeArea(
        // Same rule as before: while the query is in flight we render
        // the EMPTY state, not a spinner — an animated loading state
        // hangs `pumpAndSettle` under the fake-async zone.
        child: RefreshIndicator(
          onRefresh: _load,
          child: rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: <Widget>[
                    const SizedBox(height: 96),
                    UdaoEmptyState(
                      illustration: AppIcons.roastFlame,
                      title: l10n.aajEmptyTitle,
                      body: _error == null
                          ? l10n.aajEmptyBody
                          : '${l10n.aajEmptyBody}\n($_error)',
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(UdaoSpacing.xl),
                  children: <Widget>[
                    _HeroCard(
                      spentToday: spentToday,
                      delta: delta,
                      yesterdayLabel: l10n.aajYesterdayChip,
                      spentLabel: l10n.aajSpentTodayLabel,
                      entriesLabel: l10n.aajEntriesChip(rows.length),
                    ),
                    const SizedBox(height: UdaoSpacing.xl),
                    SectionHeader(
                      label: l10n.aajMovementTitle,
                      number: '01',
                    ),
                    _TxnListCard(txns: rows),
                    if (_walletBudget != null) ...<Widget>[
                      const SizedBox(height: UdaoSpacing.xl),
                      _BudgetStrip(status: _walletBudget!),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Gradient hero: today's spend in huge Syne numerals with count-up,
/// the vs-yesterday delta chip, and the entries count.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.spentToday,
    required this.delta,
    required this.yesterdayLabel,
    required this.spentLabel,
    required this.entriesLabel,
  });

  final Money spentToday;
  final Money delta;
  final String yesterdayLabel;
  final String spentLabel;
  final String entriesLabel;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Container(
      padding: const EdgeInsets.all(UdaoSpacing.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(UdaoRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            sem.flame.withValues(alpha: 0.18),
            scheme.surfaceContainerLow,
          ],
        ),
        border: Border.all(color: sem.flame.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            spentLabel.toUpperCase(),
            style: text.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: UdaoSpacing.sm),
          MoneyDisplay(money: spentToday, hero: true, delta: delta),
          const SizedBox(height: UdaoSpacing.md),
          Text(
            '$yesterdayLabel · $entriesLabel',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Phase-08: the wallet Lakshman Rekha strip — spend bar + what's
/// left, tap to open the budgets screen.
class _BudgetStrip extends StatelessWidget {
  const _BudgetStrip({required this.status});

  final BudgetStatus status;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    final DateTime? end = status.windowEnd;
    final int daysLeft = end == null
        ? 0
        : (IstDates.startOfDay(end)
                    .difference(IstDates.startOfDay(IstDates.nowIst()))
                    .inDays +
                1)
            .clamp(0, 999);

    return UdaoCard(
      accent: status.exceeded ? UdaoCardAccent.flame : UdaoCardAccent.gold,
      onTap: () => unawaited(context.push(Routes.budgets)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.budgetTitle.toUpperCase(),
                  style: text.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Text(
                status.exceeded
                    ? l10n.budgetExceededStamp
                    : '${status.remaining.formatPlain()} · '
                        '${l10n.budgetDaysLeft(daysLeft)}',
                style: text.labelLarge?.copyWith(
                  color:
                      status.exceeded ? context.semantic.flame : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: UdaoSpacing.md),
          SpendBar(
            label: l10n.budgetLeftLabel,
            spent: status.spent,
            budget: status.effectiveLimit,
          ),
        ],
      ),
    );
  }
}

/// The day's movement — TxnRows inside one soft rounded surface.
class _TxnListCard extends StatelessWidget {
  const _TxnListCard({required this.txns});

  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(UdaoRadius.lg),
        color: scheme.surfaceContainerLow,
        border: Border.all(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          for (int i = 0; i < txns.length; i++) ...<Widget>[
            if (i > 0)
              Divider(
                height: 1,
                indent: UdaoSpacing.xl + UdaoSpacing.md,
                endIndent: UdaoSpacing.md,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
            TxnRow(txn: txns[i]),
          ],
        ],
      ),
    );
  }
}
