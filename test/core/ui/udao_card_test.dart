// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/udao_card.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('renders its child and fires taps', (WidgetTester tester) async {
    bool fired = false;
    await pumpUdao(
      tester,
      UdaoCard(
        onTap: () => fired = true,
        child: const Text('CARD BODY'),
      ),
    );

    expect(find.text('CARD BODY'), findsOneWidget);
    await tester.tap(find.text('CARD BODY'));
    expect(fired, isTrue);
  });

  testWidgets('accent variants build in both themes', (
    WidgetTester tester,
  ) async {
    for (final bool dark in <bool>[true, false]) {
      for (final UdaoCardAccent accent in UdaoCardAccent.values) {
        await pumpUdao(
          tester,
          UdaoCard(
            accent: accent,
            child: const Text('A'),
          ),
          dark: dark,
        );
        expect(tester.takeException(), isNull, reason: '$accent/$dark');
      }
    }
  });
}
