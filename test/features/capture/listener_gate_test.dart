// phase-03
// Gate screen widget tests: the not-granted prime state (deep link
// fires), the returned-without-grant nudge, and the granted state
// (listening card + 30s test flight + RAW/PARSED chips from the live
// streams). The bridge and the health notifier are faked — no
// platform channels, no timers left behind.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/features/capture/bridge/capture_raw_event.dart';
import 'package:udao/features/capture/bridge/listener_status.dart';
import 'package:udao/features/capture/capture_providers.dart';
import 'package:udao/features/capture/permission/listener_gate_screen.dart';
import 'package:udao/features/capture/pipeline/ledger_events.dart';
import 'package:udao/l10n/app_localizations.dart';

import 'fake_capture_bridge.dart';

Widget _gateApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: UdaoTheme.dark(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ListenerGateScreen(),
    ),
  );
}

void main() {
  testWidgets('not granted: prime card + settings deep link + nudge',
      (WidgetTester tester) async {
    final FakeCaptureBridge bridge = FakeCaptureBridge();
    final ProviderContainer container = ProviderContainer(
      overrides: captureTestOverrides(bridge),
    );
    addTearDown(container.dispose);
    addTearDown(bridge.close);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();

    // Prime state (test locale resolves to the en fallback). The CTA
    // lives in a UdaoButton, which renders its label UPPERCASED.
    expect(find.text('Let UDAO count your money'), findsOneWidget);
    expect(find.text('OPEN NOTIFICATION ACCESS'), findsOneWidget);
    expect(find.text('Capture is still OFF'), findsOneWidget);
    expect(find.text('Test flight'), findsNothing);

    // Deep link fires once.
    await tester.tap(find.text('OPEN NOTIFICATION ACCESS'));
    await tester.pump();
    expect(bridge.openSettingsCalls, 1);

    // Returning without granting flips the copy to the nudge.
    expect(
      find.text(
        'Access is still off — find "UDAO Capture" in the list and switch it on.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('granted: listening card + test flight + live chips',
      (WidgetTester tester) async {
    // Tall surface so the whole gate (chips included) is BUILT —
    // ListView is lazy and offscreen children do not exist for
    // finders. Deterministic regardless of font metrics.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final DateTime now = DateTime(2026, 10, 27, 18, 44);
    final DateTime istNow = IstDates.toIst(now);
    final FakeCaptureBridge bridge = FakeCaptureBridge(
      statusValue: ListenerStatus(
        connected: true,
        lastEventAt: now.millisecondsSinceEpoch,
        componentEnabled: true,
      ),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: captureTestOverrides(bridge),
    );
    addTearDown(container.dispose);
    addTearDown(bridge.close);

    await tester.pumpWidget(_gateApp(container));
    await tester.pump();

    expect(find.text('Capture ON — listening'), findsOneWidget);
    expect(find.text('Test flight'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
    // Expected string computed with the SAME ist transform the screen
    // uses, so the assertion holds on any test-runner timezone.
    expect(
      find.textContaining(
        'Last event: ${IstDates.isoDate(istNow)} '
        '${istNow.hour.toString().padLeft(2, '0')}:'
        '${istNow.minute.toString().padLeft(2, '0')}',
      ),
      findsOneWidget,
    );

    // Countdown ticks while nothing has landed yet. (A captured txn
    // STOPS the monitor by design — check the countdown BEFORE the
    // chips, or the timer is already cancelled.)
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('15 s'), findsOneWidget);

    // RAW chip: a live notification lands from the fake bridge.
    bridge.emit(
      const CaptureRawEvent(
        pkg: 'com.phonepe.app',
        title: '',
        text: '',
        bigText: '',
        subText: '',
        ts: 1,
      ),
    );
    await tester.pump();
    expect(find.text('com.phonepe.app'), findsOneWidget);

    // PARSED chip: a captured txn lands on the ledger events stream —
    // monitor passes, ticker dies, the big text flips to a check mark.
    // LedgerEvents is an async broadcast controller (production
    // semantics), so the delivery microtask needs a pump boundary:
    // double-pump renders the post-listener frame deterministically.
    container.read(ledgerEventsProvider).emit(
          const TxnCaptured(
            txnId: 't1',
            amountPaise: 15000,
            merchantClean: 'Swiggy',
            direction: 'debit',
            confidence: 0.98,
            categoryId: 'cat_khaana',
          ),
        );
    await tester.pump();
    await tester.pump();
    expect(find.text('\u20b9150 \u00b7 Swiggy \u00b7 cat_khaana'), findsOneWidget);
    expect(find.text('\u2713'), findsOneWidget);
    expect(
      find.text('15 s'),
      findsNothing,
      reason: 'monitor stopped after capture',
    );

    // No pending timers left behind for the framework to complain.
    await tester.pump(const Duration(seconds: 15));
  });
}
