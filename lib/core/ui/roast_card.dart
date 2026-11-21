// phase-01
// RoastCard — the story-format roast surface. Gradient ink, severity
// stamp, big Syne line (3-line clamp), amount + share stamp footer.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import '../theme/udao_typography.dart';
import '../utils/money.dart';
import 'haptics.dart';

class RoastCard extends StatelessWidget {
  const RoastCard({
    required this.roastLine,
    required this.meta,
    required this.severityLabel,
    required this.shareLabel,
    this.amount,
    this.onTap,
    this.onShare,
    super.key,
  });

  final String roastLine;

  /// Top-right meta, e.g. "AAJ · 8:30 PM".
  final String meta;

  /// Severity stamp label, e.g. "TAPAK SEVERE".
  final String severityLabel;

  /// Share-CTA label (l10n), rendered as a stamp.
  final String shareLabel;
  final Money? amount;
  final VoidCallback? onTap;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Semantics(
      button: onTap != null,
      label: roastLine,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                UdaoHaptics.impact();
                onTap?.call();
              },
        child: Container(
          padding: const EdgeInsets.all(UdaoSpacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: sem.roastCardGradient,
            ),
            borderRadius: BorderRadius.circular(UdaoRadius.card),
            border: Border.all(color: sem.cardBorder),
            boxShadow: sem.raisedShadow,
          ),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: UdaoSpacing.sm,
                        vertical: UdaoSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(UdaoRadius.pill),
                        border: Border.all(color: sem.flame),
                      ),
                      child: Text(
                        severityLabel.toUpperCase(),
                        style: text.labelSmall?.copyWith(color: sem.flame),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      meta.toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: UdaoSpacing.md),
                Text(
                  roastLine,
                  style: text.headlineSmall?.copyWith(
                    fontFamily: UdaoTypography.syne,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: UdaoSpacing.lg),
                Row(
                  children: <Widget>[
                    if (amount != null) ...<Widget>[
                      Text(
                        amount!.formatHi(),
                        style: text.titleMedium?.copyWith(
                          color: sem.flame,
                        ),
                      ),
                      const SizedBox(width: UdaoSpacing.md),
                    ],
                    const Spacer(),
                    _ShareStamp(label: shareLabel, onTap: onShare),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareStamp extends StatelessWidget {
  const _ShareStamp({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final UdaoSemantic sem = context.semantic;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              UdaoHaptics.tap();
              onTap?.call();
            },
      child: SizedBox(
        height: 48,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: UdaoSpacing.lg),
          decoration: BoxDecoration(
            color: sem.flame.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(UdaoRadius.pill),
            border: Border.all(color: sem.flame),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PhosphorIcon(
                PhosphorIconsBold.shareNetwork,
                size: 16,
                color: sem.flame,
              ),
              const SizedBox(width: UdaoSpacing.sm),
              Text(
                label.toUpperCase(),
                style: text.labelLarge?.copyWith(color: sem.flame),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
