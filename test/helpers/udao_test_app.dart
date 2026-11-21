// phase-01
// Shared harness: pump any component inside a fully-themed UDAO
// MaterialApp (dark by default — pass `dark: false` for paper mode).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_theme.dart';

Future<void> pumpUdao(
  WidgetTester tester,
  Widget child, {
  bool dark = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: dark ? UdaoTheme.dark() : UdaoTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}
