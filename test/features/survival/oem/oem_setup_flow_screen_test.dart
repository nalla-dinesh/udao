// phase-05
// OEM setup flow screen: Poco-detected phone gets the Xiaomi guide,
// deep links fire through the seam, a missed deep link degrades to
// the manual steps message, and the ack writes the versioned kv key.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/features/survival/oem/oem_setup_flow_screen.dart';
import 'package:udao/features/survival/survival_providers.dart';
import 'package:udao/l10n/app_localizations.dart';

import '../../capture/fake_capture_bridge.dart';
import '../fake_survival_bridge.dart';

Widget _oemApp(ProviderContainer container) {
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
      home: const OemSetupFlowScreen(),
    ),
  );
}

void main() {
  testWidgets('Poco phone → Xiaomi guide with steps + manual fallback',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final FakeCaptureBridge capture = FakeCaptureBridge();
    final FakeSurvivalBridge survival = FakeSurvivalBridge();
    final FakeKvDao kv = FakeKvDao();
    final ProviderContainer container = ProviderContainer(
      overrides: survivalTestOverrides(
        captureBridge: capture,
        survivalBridge: survival,
        kv: kv,
        deviceInfo: const UdaoDeviceInfo(
          manufacturer: 'Xiaomi',
          brand: 'poco',
          model: '22101316C',
          versionRelease: '14',
          isEmulator: false,
        ),
      ),
    );
    addTearDown(container.dispose);
    addTearDown(capture.close);

    await tester.pumpWidget(_oemApp(container));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Survival setup — Xiaomi / MIUI (Poco, Redmi included)'),
      findsOneWidget,
    );
    expect(find.text('Why this phone needs it'), findsOneWidget);
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Step 2'), findsOneWidget);
    // Manual fallback card ALWAYS present.
    expect(
      find.text('Deep link kaam na kare toh (manual path)'),
      findsOneWidget,
    );
    // dontkillmyapp reference surfaced.
    expect(
      find.textContaining('dontkillmyapp.com/xiaomi'),
      findsOneWidget,
    );

    // Deep link button fires the component through the seam.
    await tester.tap(find.text('AUTOSTART SCREEN KHOLO'));
    await tester.pump();
    await tester.pump();
    expect(survival.openOemComponents, hasLength(1));
    expect(
      survival.openOemComponents.single,
      contains('com.miui.securitycenter'),
    );
    expect(
      find.text('Opened the OEM screen — flip the setting there.'),
      findsOneWidget,
    );

    // Ack writes the versioned kv key and disables the CTA.
    await tester.tap(find.text('DONE — I SET THIS UP'));
    await tester.pump();
    await tester.pump();
    expect(kv.read(SurvivalKvKeys.oemSetupAck), isNotNull);
    expect(find.text('MARKED DONE'), findsOneWidget);
  });

  testWidgets('missed deep link degrades honestly to manual steps',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final FakeCaptureBridge capture = FakeCaptureBridge();
    final FakeSurvivalBridge survival = FakeSurvivalBridge()
      ..openOemResult = false;
    final ProviderContainer container = ProviderContainer(
      overrides: survivalTestOverrides(
        captureBridge: capture,
        survivalBridge: survival,
        deviceInfo: const UdaoDeviceInfo(
          manufacturer: 'samsung',
          brand: 'samsung',
          model: 'SM-S918B',
          versionRelease: '15',
          isEmulator: false,
        ),
      ),
    );
    addTearDown(container.dispose);
    addTearDown(capture.close);

    await tester.pumpWidget(_oemApp(container));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Survival setup — Samsung (One UI)'),
      findsOneWidget,
    );

    await tester.tap(find.text('BATTERY SETTINGS KHOLO'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
        'This path does not exist on your version — use the manual steps below.',
      ),
      findsOneWidget,
    );
  });
}
