// phase-01
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/core/ui/udao_button.dart';
import 'package:udao/core/ui/udao_dialog.dart';


void main() {
  Future<void> pumpWithTrigger(WidgetTester tester, VoidCallback onFire) {
    return tester.pumpWidget(
      MaterialApp(
        theme: UdaoTheme.dark(),
        home: Scaffold(
          body: Center(
            child: UdaoButton(label: 'OPEN', onTap: onFire),
          ),
        ),
      ),
    );
  }

  testWidgets('sheet shows title, body, CTA; CTA pops and fires',
      (WidgetTester tester) async {
    bool ctaFired = false;
    await pumpWithTrigger(tester, () {
      unawaited(
        UdaoDialog.show(
          context: tester.state(find.byType(Scaffold)).context,
          title: 'Pakka?',
          child: const Text('Ye final jawab hai tera?'),
          ctaLabel: 'HN PAKKA',
          onCta: () => ctaFired = true,
        ),
      );
    });

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    expect(find.text('Pakka?'), findsOneWidget);
    expect(find.text('Ye final jawab hai tera?'), findsOneWidget);

    await tester.tap(find.text('HN PAKKA'));
    await tester.pumpAndSettle();

    expect(ctaFired, isTrue);
    expect(find.text('Pakka?'), findsNothing, reason: 'sheet popped');
  });

  testWidgets('confirm dialog: confirm → true, cancel → false',
      (WidgetTester tester) async {
    bool? confirmed;
    await pumpWithTrigger(tester, () async {
      confirmed = await UdaoConfirmDialog.show(
        context: tester.state(find.byType(Scaffold)).context,
        title: 'Delete kar de?',
        message: 'Wapas nahi aayega, samjha?',
        confirmLabel: 'HN DELETE',
        cancelLabel: 'NA RE',
        destructive: true,
      );
    });

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('Delete kar de?'), findsOneWidget);

    await tester.tap(find.text('NA RE'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HN DELETE'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
