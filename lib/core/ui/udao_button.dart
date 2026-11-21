// phase-01
// UDAO button — 4 variants × 3 sizes, loading state is a skeleton
// pulse (never a spinner), press scale 0.97 with the brand spring.
// All sizes keep a ≥48dp touch target.
import 'package:flutter/material.dart';

import '../theme/udao_motion.dart';
import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import 'haptics.dart';
import 'skeleton.dart';

enum UdaoButtonVariant { flameFilled, limeFilled, glass, danger }

enum UdaoButtonSize { sm, md, lg }

class UdaoButton extends StatefulWidget {
  const UdaoButton({
    required this.label,
    this.onTap,
    this.variant = UdaoButtonVariant.flameFilled,
    this.size = UdaoButtonSize.md,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final UdaoButtonVariant variant;
  final UdaoButtonSize size;
  final bool loading;

  @override
  State<UdaoButton> createState() => _UdaoButtonState();
}

class _UdaoButtonState extends State<UdaoButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;
    final TextTheme text = Theme.of(context).textTheme;

    final (Color background, Color foreground, Color? border) =
        switch (widget.variant) {
      UdaoButtonVariant.flameFilled => (scheme.primary, scheme.onPrimary, null),
      UdaoButtonVariant.limeFilled => (sem.lime, scheme.onSecondary, null),
      UdaoButtonVariant.glass => (
        scheme.surface,
        scheme.onSurface,
        sem.cardBorder,
      ),
      UdaoButtonVariant.danger => (scheme.error, scheme.onError, null),
    };

    final bool enabled = widget.onTap != null && !widget.loading;

    final double height = switch (widget.size) {
      UdaoButtonSize.sm => 48,
      UdaoButtonSize.md => 52,
      UdaoButtonSize.lg => 56,
    };

    final EdgeInsetsGeometry padding = switch (widget.size) {
      UdaoButtonSize.sm => const EdgeInsets.symmetric(
        horizontal: UdaoSpacing.lg,
      ),
      UdaoButtonSize.md => const EdgeInsets.symmetric(
        horizontal: UdaoSpacing.xl,
      ),
      UdaoButtonSize.lg => const EdgeInsets.symmetric(
        horizontal: UdaoSpacing.xxl,
      ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? _handleTap : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: UdaoMotion.fast,
          curve: UdaoMotion.spring,
          child: AnimatedOpacity(
            duration: UdaoMotion.fast,
            opacity: enabled ? 1.0 : 0.5,
            child: Container(
              height: height,
              padding: padding,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(UdaoRadius.pill),
                border: border == null ? null : Border.all(color: border),
              ),
              child: widget.loading
                  ? const _ButtonLoadingPulse()
                  : Text(
                      widget.label.toUpperCase(),
                      style: text.labelLarge?.copyWith(color: foreground),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleTap() {
    UdaoHaptics.tap();
    widget.onTap?.call();
  }
}

/// The loading treatment: a pulsing skeleton strip. No spinners.
class _ButtonLoadingPulse extends StatefulWidget {
  const _ButtonLoadingPulse();

  @override
  State<_ButtonLoadingPulse> createState() => _ButtonLoadingPulseState();
}

class _ButtonLoadingPulseState extends State<_ButtonLoadingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return Opacity(opacity: 0.4 + 0.6 * _controller.value, child: child);
        },
        child: const SkeletonLine(width: 96, height: 14),
      ),
    );
  }
}
