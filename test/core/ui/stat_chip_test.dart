// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:udao/core/ui/stat_chip.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('renders label and value', (WidgetTester tester) async {
    await pumpUdao(
      tester,
      const StatChip(label: 'AAJ UDA', value: '₹420'),
    );
    expect(find.text('AAJ UDA'), findsOneWidget);
    expect(find.text('₹420'), findsOneWidget);
  });

  testWidgets('trend glyph follows the direction', (WidgetTester tester) async {
    await pumpUdao(
      tester,
      const StatChip(label: 'AAJ UDA', value: '₹420', trendUp: false),
    );
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is PhosphorIcon && w.icon == PhosphorIconsBold.trendDown,
      ),
      findsOneWidget,
    );

    await pumpUdao(
      tester,
      const StatChip(label: 'BACHAYA', value: '₹1.2k', trendUp: true),
    );
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is PhosphorIcon && w.icon == PhosphorIconsBold.trendUp,
      ),
      findsOneWidget,
    );
  });
}
