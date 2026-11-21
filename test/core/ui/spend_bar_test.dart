// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:udao/core/ui/spend_bar.dart';
import 'package:udao/core/utils/money.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  test('fillRatio: straight division inside budget', () {
    expect(
      SpendBar.fillRatio(Money.fromRupees(600), Money.fromRupees(1000)),
      closeTo(0.6, 0.001),
    );
  });

  test('fillRatio: clamps overflow at 1.0 and handles zero budget', () {
    expect(
      SpendBar.fillRatio(Money.fromRupees(860), Money.fromRupees(600)),
      1.0,
      reason: 'overflow clamps',
    );
    expect(
      SpendBar.fillRatio(const Money.zero(), const Money.zero()),
      0.0,
      reason: 'empty budget, empty spend',
    );
    expect(
      SpendBar.fillRatio(Money.fromRupees(1), const Money.zero()),
      1.0,
      reason: 'spending against no budget is fully blown',
    );
  });

  testWidgets('in-budget bar renders amounts with no warning glyph',
      (WidgetTester tester) async {
    await pumpUdao(
      tester,
      SpendBar(
        label: 'CHAI',
        spent: Money.fromRupees(180),
        budget: Money.fromRupees(500),
      ),
    );
    expect(find.text('CHAI'), findsOneWidget);
    expect(find.text('₹180 / ₹500'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is PhosphorIcon && w.icon == PhosphorIconsBold.warning,
      ),
      findsNothing,
    );
  });

  testWidgets('overflow bar shows the flame warning glyph',
      (WidgetTester tester) async {
    await pumpUdao(
      tester,
      SpendBar(
        label: 'SWIGGY',
        spent: Money.fromRupees(860),
        budget: Money.fromRupees(600),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is PhosphorIcon && w.icon == PhosphorIconsBold.warning,
      ),
      findsOneWidget,
    );
  });
}
