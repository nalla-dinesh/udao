// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:udao/core/ui/money_display.dart';
import 'package:udao/core/utils/money.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('renders the exact hi-format amount', (WidgetTester tester) async {
    await pumpUdao(
      tester,
      MoneyDisplay(money: Money.fromRupees(12, paise: 34)),
    );
    expect(find.text('₹12.34'), findsOneWidget);
  });

  testWidgets('animates from old to new value on change and lands exactly',
      (WidgetTester tester) async {
    final Money first = Money.fromRupees(100);
    final Money second = Money.fromRupees(200);

    await pumpUdao(tester, MoneyDisplay(money: first));
    expect(find.text('₹100'), findsOneWidget);

    await pumpUdao(tester, MoneyDisplay(money: second));
    await tester.pump(const Duration(milliseconds: 150));
    final String mid = tester.widget<Text>(find.textContaining('₹')).data!;
    expect(mid, isNot('₹200'), reason: 'mid-animation value');

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('₹200'), findsOneWidget);
  });

  testWidgets('delta chip: down is flame with caret-down', (
    WidgetTester tester,
  ) async {
    await pumpUdao(
      tester,
      MoneyDisplay(
        money: Money.fromRupees(420),
        delta: Money.fromRupees(-55),
      ),
    );
    expect(find.text('₹55'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is PhosphorIcon && w.icon == PhosphorIconsBold.caretDown,
      ),
      findsOneWidget,
    );
  });

  testWidgets('delta chip: up is success with caret-up', (
    WidgetTester tester,
  ) async {
    await pumpUdao(
      tester,
      MoneyDisplay(
        money: Money.fromRupees(420),
        delta: Money.fromRupees(80),
      ),
    );
    expect(find.text('₹80'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is PhosphorIcon && w.icon == PhosphorIconsBold.caretUp,
      ),
      findsOneWidget,
    );
  });

  testWidgets('compact mode hides the delta chip', (WidgetTester tester) async {
    await pumpUdao(
      tester,
      MoneyDisplay(
        money: Money.fromRupees(99),
        delta: Money.fromRupees(-12),
        compact: true,
      ),
    );
    expect(find.text('₹99'), findsOneWidget);
    expect(find.text('₹12'), findsNothing);
    expect(find.byType(PhosphorIcon), findsNothing);
  });
}
