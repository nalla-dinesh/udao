// phase-01
// UdaoDialog — bottom-sheet dialogs with drag handle + flame header
// rule. `UdaoConfirmDialog` adds a confirm/cancel variant with
// optional destructive styling. No Material AlertDialog anywhere.
import 'package:flutter/material.dart';

import '../theme/udao_colors.dart';
import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import 'udao_button.dart';

class UdaoDialog {
  UdaoDialog._();

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    String? ctaLabel,
    VoidCallback? onCta,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: UdaoColors.transparent,
      barrierColor: Theme.of(
        context,
      ).colorScheme.scrim.withValues(alpha: 0.6),
      builder: (BuildContext sheetContext) => _UdaoSheet(
        title: title,
        ctaLabel: ctaLabel,
        onCta: onCta,
        child: child,
      ),
    );
  }
}

class _UdaoSheet extends StatelessWidget {
  const _UdaoSheet({
    required this.title,
    required this.child,
    this.ctaLabel,
    this.onCta,
  });

  final String title;
  final Widget child;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.all(UdaoSpacing.sm),
        padding: const EdgeInsets.all(UdaoSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(UdaoRadius.lg),
          border: Border.all(color: sem.cardBorder),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sem.cardBorder,
                    borderRadius: BorderRadius.circular(UdaoRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: UdaoSpacing.md),
              Text(
                title,
                style: text.headlineSmall?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: UdaoSpacing.sm),
              Container(
                height: 3,
                width: 48,
                decoration: BoxDecoration(
                  color: sem.flame,
                  borderRadius: BorderRadius.circular(UdaoRadius.pill),
                ),
              ),
              const SizedBox(height: UdaoSpacing.md),
              // Flexible, not bare: on short viewports (small phones,
              // landscape, large OS text scale) the sheet must shrink
              // its BODY rather than overflow under the fold — the
              // drag handle, title and CTA stay reachable.
              Flexible(child: child),
              if (ctaLabel != null) ...<Widget>[
                const SizedBox(height: UdaoSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: UdaoButton(
                    label: ctaLabel!,
                    onTap: () {
                      Navigator.of(context).pop();
                      onCta?.call();
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class UdaoConfirmDialog {
  UdaoConfirmDialog._();

  /// Returns `true` (confirm), `false` (cancel) or `null` (dismissed
  /// by tapping the barrier).
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: UdaoColors.transparent,
      barrierColor: Theme.of(
        context,
      ).colorScheme.scrim.withValues(alpha: 0.6),
      builder: (BuildContext sheetContext) => _ConfirmSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    return Container(
      margin: const EdgeInsets.all(UdaoSpacing.sm),
      padding: const EdgeInsets.all(UdaoSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(UdaoRadius.lg),
        border: Border.all(color: sem.cardBorder),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: sem.cardBorder,
                  borderRadius: BorderRadius.circular(UdaoRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: UdaoSpacing.md),
            Text(
              title,
              style: text.headlineSmall?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: UdaoSpacing.sm),
            Container(
              height: 3,
              width: 48,
              decoration: BoxDecoration(
                color: destructive ? scheme.error : sem.flame,
                borderRadius: BorderRadius.circular(UdaoRadius.pill),
              ),
            ),
            const SizedBox(height: UdaoSpacing.md),
            Text(
              message,
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: UdaoSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: UdaoButton(
                label: confirmLabel,
                variant: destructive
                    ? UdaoButtonVariant.danger
                    : UdaoButtonVariant.flameFilled,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ),
            const SizedBox(height: UdaoSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: UdaoButton(
                label: cancelLabel,
                variant: UdaoButtonVariant.glass,
                onTap: () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
