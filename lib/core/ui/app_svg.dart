// phase-01
// `flutter_svg` wrapper: optional theme tint + semantics label.
//
// Bad/missing assets render as an empty box with an error log instead
// of crashing (flutter_svg's asset loader never throws past the
// builder). All brand marks use `currentColor`, so tinting via
// [color] works on every asset.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppSvg extends StatelessWidget {
  const AppSvg(
    this.asset, {
    super.key,
    this.width,
    this.height,
    this.color,
    this.semanticsLabel,
  });

  final String asset;
  final double? width;
  final double? height;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: width,
      height: height,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
      semanticsLabel: semanticsLabel,
    );
  }
}
