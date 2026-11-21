// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/skeleton.dart';
import 'package:udao/core/ui/udao_button.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('renders label and fires onTap', (WidgetTester tester) async {
    bool fired = false;
    await pumpUdao(
      tester,
      UdaoButton(label: 'GO', onTap: () => fired = true),
    );

    expect(find.text('GO'), findsOneWidget);
    await tester.tap(find.text('GO'));
    expect(fired, isTrue);
  });

  testWidgets('without onTap it is disabled and inert', (
    WidgetTester tester,
  ) async {
    await pumpUdao(tester, const UdaoButton(label: 'DEAD'));

    // Semantics annotation is present (button: true, enabled: false)...
    expect(
      find.descendant(
        of: find.byType(UdaoButton),
        matching: find.byWidgetPredicate((Widget w) => w is Semantics),
      ),
      findsWidgets,
    );

    // ...and the visual disabled treatment is the 0.5 opacity dip.
    final AnimatedOpacity opacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(UdaoButton),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, 0.5);

    await tester.tap(find.text('DEAD'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading state shows the skeleton pulse, not a spinner',
      (WidgetTester tester) async {
    bool fired = false;
    await pumpUdao(
      tester,
      UdaoButton(label: 'WAIT', loading: true, onTap: () => fired = true),
    );

    expect(
      find.descendant(
        of: find.byType(UdaoButton),
        matching: find.byType(SkeletonLine),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byType(UdaoButton), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(fired, isFalse, reason: 'loading buttons never fire');
  });
}
