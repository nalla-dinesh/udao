// phase-01
// UdaoSnackBar — top-anchored stamp-style notice (3 intents),
// auto-dismisses after 3.5s, dismissible on tap, with haptics.
// Implemented on the root Overlay — Material SnackBars stay unused.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/udao_motion.dart';
import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import 'haptics.dart';

enum UdaoSnackBarIntent { info, warn, roast }

class UdaoSnackBar {
  UdaoSnackBar._();

  static void show(
    BuildContext context, {
    required String message,
    UdaoSnackBarIntent intent = UdaoSnackBarIntent.info,
  }) {
    final OverlayState? overlay = Overlay.maybeOf(
      context,
      rootOverlay: true,
    );
    if (overlay == null) {
      return;
    }
    UdaoHaptics.tap();

    final _SnackBarSession session = _SnackBarSession();
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) => _UdaoSnackBarOverlay(
        message: message,
        intent: intent,
        session: session,
      ),
    );
    session.entry = entry;
    overlay.insert(entry);
    session.startAutoDismiss();
  }
}

class _SnackBarSession {
  OverlayEntry? entry;
  Timer? _timer;
  bool _dismissed = false;

  void startAutoDismiss() {
    _timer = Timer(const Duration(milliseconds: 3500), dismiss);
  }

  void dismiss() {
    cancel();
    if (_dismissed) {
      return;
    }
    _dismissed = true;
    entry?.remove();
    entry = null;
  }

  /// Stops the auto-dismiss clock without touching the entry. Called
  /// when the overlay widget unmounts (tap-dismiss, test teardown,
  /// route death) so no dangling Timer outlives the widget tree —
  /// flutter_test fails tests on pending timers, and in the app a
  /// late fire would dismiss an already-dead overlay.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

class _UdaoSnackBarOverlay extends StatefulWidget {
  const _UdaoSnackBarOverlay({
    required this.message,
    required this.intent,
    required this.session,
  });

  final String message;
  final UdaoSnackBarIntent intent;
  final _SnackBarSession session;

  @override
  State<_UdaoSnackBarOverlay> createState() => _UdaoSnackBarOverlayState();
}

class _UdaoSnackBarOverlayState extends State<_UdaoSnackBarOverlay> {
  @override
  void dispose() {
    widget.session.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UdaoSnackBarIntent intent = widget.intent;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final UdaoSemantic sem = context.semantic;

    final (Color tone, IconData glyph, String tag) = switch (intent) {
      UdaoSnackBarIntent.info => (sem.sky, PhosphorIconsBold.info, 'PAATAA'),
      UdaoSnackBarIntent.warn => (sem.gold, PhosphorIconsBold.warning, 'DHYAAN'),
      UdaoSnackBarIntent.roast => (sem.flame, PhosphorIconsBold.fire, 'ROAST'),
    };

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(UdaoSpacing.lg),
          child: Align(
            alignment: Alignment.topCenter,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: UdaoMotion.base,
              curve: UdaoMotion.spring,
              builder: (BuildContext context, double t, Widget? child) {
                // The brand spring overshoots (t > 1) on purpose for
                // the translate dip; Opacity asserts outside 0..1, so
                // clamp just that leg.
                return Transform.translate(
                  offset: Offset(0, -48 * (1 - t)),
                  child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
                );
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.session.dismiss,
                child: RepaintBoundary(
                  child: Container(
                    // Accent edge as a positioned strip — a rounded
                    // BoxDecoration cannot carry a non-uniform Border, and
                    // Row+stretch forces infinite height in the overlay's
                    // unbounded context.
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(UdaoRadius.card),
                      border: Border.fromBorderSide(
                        BorderSide(color: sem.cardBorder),
                      ),
                      boxShadow: sem.raisedShadow,
                    ),
                    child: Stack(
                      children: <Widget>[
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 3,
                          child: ColoredBox(color: tone),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(UdaoSpacing.lg),
                          child: Row(
                            children: <Widget>[
                              PhosphorIcon(glyph, size: 20, color: tone),
                              const SizedBox(width: UdaoSpacing.md),
                              Expanded(
                                child: Text(
                                  widget.message,
                                  style: text.bodyMedium?.copyWith(
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: UdaoSpacing.md),
                              Text(
                                tag,
                                style: text.labelSmall?.copyWith(
                                  color: tone,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
