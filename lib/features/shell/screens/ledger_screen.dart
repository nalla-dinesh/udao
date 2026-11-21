// phase-01 (phase-06: live read-back; phase-07 UI pass: day-grouped
// TxnRow list with per-day totals).
//
// Ledger — the kitaab. Entries grouped by day (Aaj / Kal / date),
// each group carrying its day total, rendered as TxnRows inside a
// soft surface. Pull to refresh; live on every captured txn.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/udao_spacing.dart';
import '../../../core/theme/udao_theme_extension.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/section_header.dart';
import '../../../core/ui/txn_row.dart';
import '../../../core/ui/udao_empty_state.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/txn.dart';
import '../../../l10n/app_localizations.dart';
import '../../capture/capture_providers.dart'
    show ledgerEventsProvider, txnDaoProvider;
import '../../capture/pipeline/ledger_events.dart';

class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({super.key});

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  List<Txn>? _txns;
  Failure? _error;
  StreamSubscription<TxnCaptured>? _events;

  @override
  void initState() {
    super.initState();
    _load();
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
    final result = await ref.read(txnDaoProvider).page(limit: 200);
    if (!mounted) {
      return;
    }
    result.when(
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

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final List<Txn>? txns = _txns;
    final List<Txn> rows = txns ?? const <Txn>[];
    final List<_DayGroup> groups = _group(rows);

    return Scaffold(
      body: SafeArea(
        // Same rule as Aaj: no animated loading state — see the note
        // there about pumpAndSettle and the fake-async zone.
        child: RefreshIndicator(
          onRefresh: _load,
          child: rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: <Widget>[
                    const SizedBox(height: 96),
                    UdaoEmptyState(
                      illustration: AppIcons.verdictBell,
                      title: l10n.ledgerEmptyTitle,
                      body: _error == null
                          ? l10n.ledgerEmptyBody
                          : '${l10n.ledgerEmptyBody}\n($_error)',
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(UdaoSpacing.xl),
                  children: <Widget>[
                    SectionHeader(label: l10n.ledgerTitle, number: '02'),
                    for (final _DayGroup g in groups) ...<Widget>[
                      _DayHeader(group: g),
                      const SizedBox(height: UdaoSpacing.sm),
                      _DayCard(txns: g.txns),
                      const SizedBox(height: UdaoSpacing.lg),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  List<_DayGroup> _group(List<Txn> rows) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime todayStart =
        IstDates.startOfDay(IstDates.nowIst());
    final DateTime yesterdayStart =
        todayStart.subtract(const Duration(days: 1));

    final Map<String, _DayGroup> byDay = <String, _DayGroup>{};
    for (final Txn t in rows) {
      final DateTime day = IstDates.startOfDay(t.occurredAt);
      final String key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final _DayGroup? existing = byDay[key];
      if (existing == null) {
        String label;
        if (day == todayStart) {
          label = l10n.ledgerDayToday;
        } else if (day == yesterdayStart) {
          label = l10n.ledgerDayYesterday;
        } else {
          label =
              '${day.day.toString().padLeft(2, '0')} ${_month(day.month)} ${day.year}';
        }
        byDay[key] = _DayGroup(dayStart: day, label: label, txns: <Txn>[t]);
      } else {
        existing.txns.add(t);
      }
    }
    return byDay.values.toList(growable: false);
  }

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _month(int m) => _months[m - 1];
}

class _DayGroup {
  _DayGroup({
    required this.dayStart,
    required this.label,
    required this.txns,
  });

  final DateTime dayStart;
  final String label;
  final List<Txn> txns;

  Money get debitTotal => txns
      .where((Txn t) => t.direction == TxnDirection.debit)
      .fold(const Money.zero(), (Money a, Txn t) => a + t.amount);
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.group});

  final _DayGroup group;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final UdaoSemantic sem = context.semantic;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: UdaoSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              group.label.toUpperCase(),
              style: text.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 2,
              ),
            ),
          ),
          Text(
            '₹${_fmt(group.debitTotal)}',
            style: text.titleMedium?.copyWith(color: sem.flame),
          ),
        ],
      ),
    );
  }

  static String _fmt(Money m) {
    final int r = m.paise ~/ 100;
    final int p = m.paise % 100;
    return p == 0 ? '$r' : '$r.${p.toString().padLeft(2, '0')}';
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.txns});

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
