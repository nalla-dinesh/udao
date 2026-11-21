// phase-01
// Skeletons — the app's ONLY loading treatment. Spinners are banned
// app-wide (CI grep: `CircularProgressIndicator` must stay at zero).
//
// Infinite-width blocks require a parent with bounded width
// (Column/Padding — the normal case).
import 'package:flutter/material.dart';

import '../theme/udao_motion.dart';
import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';

/// A single shimmering rounded block.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = UdaoRadius.md,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return _Shimmer(width: width, height: height, radius: radius);
  }
}

/// One or more shimmering text lines; the last line is shorter.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width = double.infinity,
    this.height = 12,
    this.lines = 1,
    this.spacing = UdaoSpacing.sm,
  });

  final double width;
  final double height;
  final int lines;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < lines; i++) ...<Widget>[
          if (i > 0) SizedBox(height: spacing),
          _Shimmer(
            width: i == lines - 1 && lines > 1 ? width * 0.6 : width,
            height: height,
            radius: height / 2,
          ),
        ],
      ],
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: UdaoMotion.shimmer)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final UdaoSemantic sem = context.semantic;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return Container(
            width: widget.width,
            height: widget.height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: sem.skeleton,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: child,
          );
        },
        child: CustomPaint(
          painter: _ShimmerHighlightPainter(
            animation: _controller,
            color: sem.skeletonHighlight,
          ),
        ),
      ),
    );
  }
}

/// Moving highlight band. `super(repaint: animation)` is what makes the
/// band actually sweep — without it the painter never repaints.
class _ShimmerHighlightPainter extends CustomPainter {
  _ShimmerHighlightPainter({required this.animation, required this.color})
      : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final RRect rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.shortestSide / 2),
    );
    final double bandWidth = size.width * 0.4;
    final double x = (size.width + bandWidth) * animation.value - bandWidth;
    final Path clip = Path()..addRRect(rrect);
    canvas.save();
    canvas.clipPath(clip);
    canvas.drawRect(
      Rect.fromLTWH(x, 0, bandWidth, size.height),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerHighlightPainter oldDelegate) =>
      oldDelegate.color != color;
}
