// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/level_bar.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('renders the requested number of segments',
      (WidgetTester tester) async {
    await pumpUdao(tester, const LevelBar(currentIndex: 2, segmentCount: 6));

    final List<Container> segments =
        tester.widgetList<Container>(find.byType(Container)).where((Container c) {
      return c.constraints?.maxHeight == 8;
    }).toList();
    expect(segments, hasLength(6));
  });

  testWidgets('renders label and keeps pulsing without exceptions',
      (WidgetTester tester) async {
    await pumpUdao(
      tester,
      const LevelBar(currentIndex: 3, segmentCount: 6, label: 'LEVEL 4/6'),
    );
    expect(find.text('LEVEL 4/6'), findsOneWidget);

    // The current segment pulses forever — pump, never pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
  });
}
