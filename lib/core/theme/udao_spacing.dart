// phase-01
// UDAO spacing / radius / elevation / motion tokens. 4pt grid.
import 'package:flutter/material.dart';

abstract final class UdaoSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class UdaoRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double card = 14;
  static const double lg = 16;

  /// Fully-rounded pill (chips, stamps, nav indicator).
  static const double pill = 999;
}

abstract final class UdaoElevation {
  /// Dark mode: borders carry the depth — no shadows.
  static const List<BoxShadow> darkRaised = <BoxShadow>[];

  /// Light mode: one soft shadow under raised surfaces.
  static const List<BoxShadow> lightRaised = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];
}
