// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/skeleton.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('SkeletonLine renders one shimmer per line',
      (WidgetTester tester) async {
    await pumpUdao(tester, const SkeletonLine(lines: 3));
    expect(
      find.descendant(
        of: find.byType(SkeletonLine),
        matching: find.byWidgetPredicate((Widget w) => w is CustomPaint),
      ),
      findsNWidgets(3),
    );
  });

  testWidgets('SkeletonBlock renders and keeps shimmering',
      (WidgetTester tester) async {
    await pumpUdao(tester, const SkeletonBlock(height: 64));
    expect(find.byType(SkeletonBlock), findsOneWidget);

    // Repeating animation: pump into the future, never pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tester.takeException(), isNull);
  });
}
