// phase-08
// Budget edit sheet — draw or move a Lakshman Rekha. Target picker
// (whole wallet + 16 seed categories), amount, period, rollover.
// Built on the QuickAdd survival pattern: fixed-height sheet, the
// middle scrolls, the CTA is pinned outside it (r9–r11 lessons) and
// never awaits a modal-open future.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/result/result.dart' show Result;
import '../../core/theme/udao_spacing.dart';
import '../../core/theme/udao_theme_extension.dart';
import '../../core/ui/udao_button.dart';
import '../../core/ui/udao_dialog.dart';
import '../../core/ui/udao_snack_bar.dart';
import '../../core/utils/money.dart';
import '../../data/models/budget.dart';
import '../../data/models/category.dart';
import '../../l10n/app_localizations.dart';
import 'budget_providers.dart';
import 'budget_service.dart';

/// Opens the sheet for a NEW budget, or an EDIT of [existing].
Future<void> showBudgetSheet(
  BuildContext context, {
  Budget? existing,
}) {
  return UdaoDialog.show<void>(
    context: context,
    title: existing == null
        ? AppLocalizations.of(context).budgetNewTitle
        : AppLocalizations.of(context).budgetEditTitle,
    child: SizedBox(
      // 520: chips wrap + amount + period + rollover ≈ 440px of
      // content + sheet chrome — CTA stays above the fold on phones.
      height: 520,
      child: _BudgetSheetBody(existing: existing),
    ),
  );
}

class _BudgetSheetBody extends ConsumerStatefulWidget {
  const _BudgetSheetBody({this.existing});

  final Budget? existing;

  @override
  ConsumerState<_BudgetSheetBody> createState() => _BudgetSheetBodyState();
}

class _BudgetSheetBodyState extends ConsumerState<_BudgetSheetBody> {
  late String? _categoryId = widget.existing?.categoryId;
  late BudgetPeriod _period =
      widget.existing?.period ?? BudgetPeriod.monthly;
  late bool _rollover = widget.existing?.rollover ?? true;
  // late: the initializer reads `widget`, which only exists after
  // the State is mounted (eager field initializers cannot see it).
  late final TextEditingController _limit = TextEditingController(
    text: widget.existing == null
        ? ''
        : _rupeesPlain(widget.existing!.limit),
  );
  bool _saving = false;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  static String _rupeesPlain(Money m) {
    final int r = m.paise ~/ 100;
    final int p = m.paise % 100;
    return p == 0 ? '$r' : '$r.${p.toString().padLeft(2, '0')}';
  }

  Future<void> _save(AppLocalizations l10n) async {
    final int? paise = int.tryParse(_limit.text.trim());
    if (paise == null || paise <= 0) {
      UdaoSnackBar.show(context, message: l10n.budgetLimitError);
      return;
    }
    setState(() => _saving = true);
    final Result<Budget> saved = await ref.read(budgetServiceProvider).save(
          categoryId: _categoryId,
          limit: Money(paise * 100),
          period: _period,
          rollover: _rollover,
        );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (saved.isErr) {
      UdaoSnackBar.show(context, message: saved.failureOrNull!.message);
      return;
    }
    Navigator.of(context).pop();
    UdaoSnackBar.show(context, message: l10n.budgetSavedSnack);
  }

  Future<void> _remove(AppLocalizations l10n) async {
    final Budget? existing = widget.existing;
    if (existing == null) {
      return;
    }
    setState(() => _saving = true);
    final Result<void> removed =
        await ref.read(budgetServiceProvider).remove(existing.id);
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (removed.isErr) {
      UdaoSnackBar.show(context, message: removed.failureOrNull!.message);
      return;
    }
    Navigator.of(context).pop();
    UdaoSnackBar.show(context, message: l10n.budgetDeletedSnack);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The middle scrolls; the CTA is pinned after it.
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.budgetTargetLabel.toUpperCase(),
                  style: text.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: UdaoSpacing.sm),
                Wrap(
                  spacing: UdaoSpacing.sm,
                  runSpacing: UdaoSpacing.sm,
                  children: <Widget>[
                    _TargetChip(
                      label: l10n.budgetWalletLabel,
                      icon: PhosphorIconsBold.wallet,
                      selected: _categoryId == null,
                      onTap: () => setState(() => _categoryId = null),
                    ),
                    for (final Category c in kSeedCategories)
                      _TargetChip(
                        label: c.name,
                        icon: PhosphorIconsBold.tag,
                        selected: _categoryId == c.id,
                        onTap: () => setState(() => _categoryId = c.id),
                      ),
                  ],
                ),
                const SizedBox(height: UdaoSpacing.lg),
                Text(
                  l10n.budgetLimitLabel.toUpperCase(),
                  style: text.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: UdaoSpacing.sm),
                TextField(
                  controller: _limit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: false),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  style: text.headlineMedium,
                  decoration: InputDecoration(
                    prefixText: '₹',
                    hintText: l10n.budgetLimitHint,
                  ),
                ),
                const SizedBox(height: UdaoSpacing.lg),
                Text(
                  l10n.budgetPeriodLabel.toUpperCase(),
                  style: text.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: UdaoSpacing.sm),
                Wrap(
                  spacing: UdaoSpacing.sm,
                  children: <Widget>[
                    _TargetChip(
                      label: l10n.budgetPeriodMonthly,
                      icon: PhosphorIconsBold.calendarBlank,
                      selected: _period == BudgetPeriod.monthly,
                      onTap: () => setState(
                          () => _period = BudgetPeriod.monthly),
                    ),
                    _TargetChip(
                      label: l10n.budgetPeriodWeekly,
                      icon: PhosphorIconsBold.calendarDot,
                      selected: _period == BudgetPeriod.weekly,
                      onTap: () =>
                          setState(() => _period = BudgetPeriod.weekly),
                    ),
                  ],
                ),
                const SizedBox(height: UdaoSpacing.lg),
                // Rollover — the friendly switch.
                Container(
                  padding: const EdgeInsets.all(UdaoSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(UdaoRadius.card),
                    color: scheme.surfaceContainerLow,
                    border: Border.all(color: sem.cardBorder),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        PhosphorIconsBold.arrowFatLineRight,
                        size: 20,
                        color: _rollover ? sem.lime : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: UdaoSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(l10n.budgetRolloverLabel,
                                style: text.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              l10n.budgetRolloverSub,
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _rollover,
                        onChanged: (bool v) => setState(() => _rollover = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: UdaoSpacing.md),
        // Pinned CTAs — reachable at any height / text scale.
        Row(
          children: <Widget>[
            if (widget.existing != null)
              Expanded(
                child: UdaoButton(
                  label: l10n.budgetDeleteCta,
                  variant: UdaoButtonVariant.danger,
                  size: UdaoButtonSize.lg,
                  onTap: _saving ? null : () => unawaited(_remove(l10n)),
                ),
              ),
            if (widget.existing != null)
              const SizedBox(width: UdaoSpacing.md),
            Expanded(
              flex: 2,
              child: UdaoButton(
                label: l10n.budgetSaveCta,
                size: UdaoButtonSize.lg,
                loading: _saving,
                onTap: _saving ? null : () => unawaited(_save(l10n)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final UdaoSemantic sem = context.semantic;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: UdaoSpacing.md,
          vertical: UdaoSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(UdaoRadius.pill),
          color: selected
              ? sem.flame.withValues(alpha: 0.18)
              : scheme.surfaceContainerLow,
          border: Border.all(
            color: selected ? sem.flame : sem.cardBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 16,
              color: selected ? sem.flame : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: UdaoSpacing.xs),
            Text(
              label,
              style: text.labelLarge?.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
