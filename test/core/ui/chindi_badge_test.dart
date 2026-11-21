// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:udao/core/ui/chindi_badge.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('unlocked badge shows the level numeral',
      (WidgetTester tester) async {
    await pumpUdao(tester, const ChindiBadge(level: 4));
    expect(find.text('4'), findsOneWidget);
    expect(find.byWidgetPredicate((Widget w) => w is PhosphorIcon), findsNothing);
  });

  testWidgets('locked badge shows the lock glyph instead',
      (WidgetTester tester) async {
    await pumpUdao(tester, const ChindiBadge(level: 6, unlocked: false));
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is PhosphorIcon && w.icon == PhosphorIconsBold.lock,
      ),
      findsOneWidget,
    );
    expect(find.text('6'), findsNothing);
  });

  testWidgets('justUnlocked fires the glow ring without crashing',
      (WidgetTester tester) async {
    await pumpUdao(tester, const ChindiBadge(level: 5, justUnlocked: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('5'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
