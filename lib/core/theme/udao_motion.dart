// phase-01
// Motion tokens — durations, stagger and the brand spring. No
// component invents its own curve.
import 'package:flutter/animation.dart';

abstract final class UdaoMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 450);

  /// Stagger delay between sequential list/section reveals.
  static const Duration stagger = Duration(milliseconds: 60);

  /// One shimmer cycle for skeleton blocks.
  static const Duration shimmer = Duration(milliseconds: 1200);

  /// Spring with ~20% overshoot — the UDAO "pop".
  static const Cubic spring = Cubic(0.2, 0.9, 0.25, 1.15);

  /// Standard decel curve for entrances.
  static const Cubic ease = Curves.easeOutCubic;
}
