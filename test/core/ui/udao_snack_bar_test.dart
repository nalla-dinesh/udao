// phase-01
// SnackBar tests. Every test ends past the 3.5s auto-dismiss window
// so no Timer survives the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/core/ui/udao_button.dart';
import 'package:udao/core/ui/udao_snack_bar.dart';


Future<void> _pumpLauncher(
  WidgetTester tester, {
  required UdaoSnackBarIntent intent,
  required String message,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: UdaoTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (BuildContext context) => UdaoButton(
              label: 'FIRE',
              onTap: () => UdaoSnackBar.show(
                context,
                message: message,
                intent: intent,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the message as a top overlay stamp',
      (WidgetTester tester) async {
    await _pumpLauncher(
      tester,
      intent: UdaoSnackBarIntent.roast,
      message: 'Bhai, budget se bahar ho gaya tu.',
    );

    await tester.tap(find.text('FIRE'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Bhai, budget se bahar ho gaya tu.'), findsOneWidget);
    expect(find.text('ROAST'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(
      find.text('Bhai, budget se bahar ho gaya tu.'),
      findsNothing,
      reason: 'auto-dismissed',
    );
  });

  testWidgets('tapping the notice dismisses it early',
      (WidgetTester tester) async {
    await _pumpLauncher(
      tester,
      intent: UdaoSnackBarIntent.warn,
      message: 'Kal tak bill bhar de.',
    );

    await tester.tap(find.text('FIRE'));
    // First frame inserts the overlay and starts the entrance tween at
    // t=0 (still translated -48px off-screen); the second pump settles it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Kal tak bill bhar de.'), findsOneWidget);

    await tester.tap(find.text('Kal tak bill bhar de.'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Kal tak bill bhar de.'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('intent tags: info PAATAA, warn DHYAAN, roast ROAST',
      (WidgetTester tester) async {
    for (final (UdaoSnackBarIntent intent, String tag)
        in <(UdaoSnackBarIntent, String)>[
      (UdaoSnackBarIntent.info, 'PAATAA'),
      (UdaoSnackBarIntent.warn, 'DHYAAN'),
      (UdaoSnackBarIntent.roast, 'ROAST'),
    ]) {
      await _pumpLauncher(tester, intent: intent, message: 'test $tag');
      await tester.tap(find.text('FIRE'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(tag), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    }
  });
}
