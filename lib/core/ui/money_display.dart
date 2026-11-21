// phase-01
// MoneyDisplay — THE hero component. Huge Syne numerals with the
// desi short format, optional delta chip, 300ms count-up on change.
//
// The count-up interpolates paise with a double for DISPLAY only —
// the final frame always lands on the exact integer `Money` value
// (monetary storage stays double-free by ADR/Phase-00 rule).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/udao_motion.dart';
import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import '../utils/money.dart';

class MoneyDisplay extends StatefulWidget {
  const MoneyDisplay({
    required this.money,
    this.delta,
    this.compact = false,
    this.hero = false,
    super.key,
  });

  final Money money;

  /// Signed change vs. yesterday — renders the delta chip when non-zero.
  final Money? delta;

  /// Dense variant for cards and rows.
  final bool compact;

  /// Extra-large display numerals (Aaj header).
  final bool hero;

  @override
  State<MoneyDisplay> createState() => _MoneyDisplayState();
}

class _MoneyDisplayState extends State<MoneyDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: UdaoMotion.base);

  Money _from = const Money.zero();
  double _t = 1.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_tick);
  }

  void _tick() {
    setState(() => _t = Curves.easeOutCubic.transform(_controller.value));
  }

  @override
  void didUpdateWidget(covariant MoneyDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.money != widget.money) {
      _from = oldWidget.money;
      _t = 0;
      unawaited(_controller.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final UdaoSemantic sem = context.semantic;

    final Money current = Money(
      (_from.paise + (widget.money.paise - _from.paise) * _t).round(),
    );

    final TextStyle? amountStyle = widget.hero
        ? text.displayLarge
        : widget.compact
            ? text.headlineSmall
            : text.displaySmall;

    Widget? deltaChip;
    final Money? delta = widget.delta;
    if (delta != null && !delta.isZero && !widget.compact) {
      final bool up = !delta.isNegative;
      final Color tone = up ? sem.success : sem.flame;
      deltaChip = Container(
        padding: const EdgeInsets.symmetric(
          horizontal: UdaoSpacing.md,
          vertical: UdaoSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(UdaoRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PhosphorIcon(
              up ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown,
              size: 14,
              color: tone,
            ),
            const SizedBox(width: UdaoSpacing.xs),
            Text(
              delta.abs().formatHi(),
              style: text.labelLarge?.copyWith(color: tone),
            ),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: Semantics(
        label: widget.money.formatPlain(),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                current.formatHi(),
                style: amountStyle?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (deltaChip != null) ...<Widget>[
                const SizedBox(height: UdaoSpacing.sm),
                deltaChip,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
