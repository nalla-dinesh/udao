// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/roast_card.dart';
import 'package:udao/core/utils/money.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  const String line = 'Aaj 420 rupaye chai mein udaye. Zinda rehna hai toh samjha kar.';

  Widget build({
    VoidCallback? onTap,
    VoidCallback? onShare,
    Money? amount,
  }) {
    return RoastCard(
      roastLine: line,
      meta: 'AAJ · 8:30 PM',
      severityLabel: 'TAPAK SEVERE',
      shareLabel: 'SHARE',
      amount: amount,
      onTap: onTap,
      onShare: onShare,
    );
  }

  testWidgets('renders roast line, stamp, meta, amount and share',
      (WidgetTester tester) async {
    await pumpUdao(
      tester,
      build(amount: Money.fromRupees(420)),
    );

    expect(find.text(line), findsOneWidget);
    expect(find.text('TAPAK SEVERE'), findsOneWidget);
    expect(find.text('AAJ · 8:30 PM'), findsOneWidget);
    expect(find.text('₹420'), findsOneWidget);
    expect(find.text('SHARE'), findsOneWidget);
  });

  testWidgets('card tap and share stamp tap are independent callbacks',
      (WidgetTester tester) async {
    int cardTaps = 0;
    int shareTaps = 0;
    await pumpUdao(
      tester,
      build(
        onTap: () => cardTaps++,
        onShare: () => shareTaps++,
        amount: Money.fromRupees(420),
      ),
    );

    await tester.tap(find.text(line));
    expect(cardTaps, 1);
    expect(shareTaps, 0);

    await tester.tap(find.text('SHARE'));
    expect(shareTaps, 1);
    expect(cardTaps, 1, reason: 'share must not bubble to the card');
  });

  testWidgets('roast line clamps at three lines', (WidgetTester tester) async {
    await pumpUdao(tester, build());
    final Text text = tester.widget<Text>(find.text(line));
    expect(text.maxLines, 3);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
