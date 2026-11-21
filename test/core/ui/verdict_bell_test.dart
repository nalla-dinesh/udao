// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/verdict_bell.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('renders as a notification preview: app, time, title, body',
      (WidgetTester tester) async {
    await pumpUdao(
      tester,
      const VerdictBell(
        appName: 'UDAO',
        title: 'Aisa dikhega',
        body: 'Aaj 420 rupaye ud gaye.',
        timeLabel: '8:30 PM',
      ),
    );
    expect(find.text('UDAO'), findsOneWidget);
    expect(find.text('8:30 PM'), findsOneWidget);
    expect(find.text('Aisa dikhega'), findsOneWidget);
    expect(find.text('Aaj 420 rupaye ud gaye.'), findsOneWidget);
  });

  testWidgets('long bodies clamp at two lines', (WidgetTester tester) async {
    const String long =
        'Bahut lamba roast jo do lines se zyada ho jayega pakka aur definitively.';
    await pumpUdao(
      tester,
      const VerdictBell(
        appName: 'UDAO',
        title: 'T',
        body: long,
        timeLabel: '8:30 PM',
      ),
    );
    final Text text = tester.widget<Text>(find.text(long));
    expect(text.maxLines, 2);
  });
}
