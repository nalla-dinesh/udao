// phase-01
// Full-app smoke: fresh install lands on onboarding, the 5 steps walk
// through, finishing persists the flags, phase-03 drops the user on
// the capture gate, and its continue CTA opens the shell.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udao/app.dart';
import 'package:udao/core/ui/udao_bottom_nav.dart';
import 'package:udao/data/db/udao_database.dart';

import 'data/db/test_db.dart' as helper;
import 'features/capture/fake_capture_bridge.dart';

void main() {
  // The shell's Aaj/Ledger tabs read the ledger live (phase-06
  // errata) — without an injected DB those reads hit the production
  // singleton and strand inside the fake-async zone (pumpAndSettle
  // timeout). Fresh in-memory DB per test, same as the chat widgets.
  late UdaoDatabase db;
  setUp(() async {
    db = await helper.createTestDb();
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  testWidgets('fresh install → 5 onboarding steps → capture gate → shell',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      ProviderScope(
        overrides: captureTestOverrides(FakeCaptureBridge()),
        child: const UdaoApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Step 1: brand.
    expect(find.text('UDAO'), findsWidgets);
    expect(
      find.text('Watch your money fly. You will get laughs AND sense.'),
      findsOneWidget,
    );

    // Walk steps 2–5 with NEXT.
    for (int i = 0; i < 4; i++) {
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();
    }

    // Step 5 is the name step — the CTA has become START.
    expect(find.text('START'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Dinesh');
    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();

    // Phase 03: onboarding now ends on the capture gate (prime state
    // with the faked bridge — notification access is off). UdaoButton
    // renders labels UPPERCASED — assert the rendered form.
    expect(find.text('Let UDAO count your money'), findsOneWidget);
    expect(find.text('OPEN NOTIFICATION ACCESS'), findsOneWidget);

    // Continue past the gate into the shell.
    await tester.tap(find.text('DONE — CONTINUE'));
    await tester.pumpAndSettle();

    // Shell is up: bottom nav + Aaj empty state.
    expect(find.byType(UdaoBottomNav), findsOneWidget);
    expect(find.text('Nothing yet today'), findsOneWidget);

    // The flags persisted.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_done'), isTrue);
    expect(prefs.getString('user_name'), 'Dinesh');
    expect(prefs.getString('personality'), 'savage');
    expect(prefs.getBool('notification_intent'), isFalse);
  });

  testWidgets('returning user skips onboarding entirely',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_done': true,
    });

    await tester.pumpWidget(const ProviderScope(child: UdaoApp()));
    await tester.pumpAndSettle();

    expect(find.byType(UdaoBottomNav), findsOneWidget);
    expect(find.text('Nothing yet today'), findsOneWidget);
  });
}
