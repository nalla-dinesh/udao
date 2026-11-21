// phase-05
// Health dashboard widget tests — the three stamp fixtures (SHARP /
// DHYAN DO / BAND), the gap-alert flush, the keep-alive lever and
// the battery card's flavor split. Everything runs on fakes: no
// channels, no real database (phase-04 lessons applied — tall
// viewport so the lazy ListView builds, bounded pumps, snackbars
// instead of awaited modals).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/platform/app_flavor.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/data/db/dao/capture_health_dao.dart';
import 'package:udao/features/capture/bridge/listener_status.dart';
import 'package:udao/features/survival/health/battery_optimization_card.dart';
import 'package:udao/features/survival/health/health_dashboard_screen.dart';
import 'package:udao/features/survival/health/survival_models.dart';
import 'package:udao/features/survival/jobs/background_jobs.dart';
import 'package:udao/l10n/app_localizations.dart';

import '../fake_survival_bridge.dart';
import '../../capture/fake_capture_bridge.dart';

Widget _dashApp(ProviderContainer container, {Widget? home}) {
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
      home: home ?? const _DashHost(),
    ),
  );
}

class _DashHost extends StatelessWidget {
  const _DashHost();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: HealthDashboardScreen());
  }
}

const int _now = 1793000000000; // fixed clock (2026-ish)

List<CaptureDayStats> _stats7() => <CaptureDayStats>[
      for (int i = 0; i < 7; i++)
        CaptureDayStats(dayStartMs: _now - i * 86400000, seen: 10 + i, parsed: 8, deduped: 2),
    ];

void main() {
  group('stamp fixtures', () {
    testWidgets('healthy listener + fresh events → SHARP', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final FakeCaptureBridge capture = FakeCaptureBridge(
        statusValue: const ListenerStatus(
          connected: true,
          lastEventAt: _now - 3 * 60 * 60 * 1000,
          componentEnabled: true,
        ),
      );
      final FakeSurvivalBridge survival = FakeSurvivalBridge();
      final ProviderContainer container = ProviderContainer(
        overrides: survivalTestOverrides(
          captureBridge: capture,
          survivalBridge: survival,
          stats: _stats7(),
          clock: _now,
        ),
      );
      addTearDown(container.dispose);
      addTearDown(capture.close);

      await tester.pumpWidget(_dashApp(container));
      await tester.pump();
      await tester.pump();

      expect(find.text('SHARP'), findsOneWidget);
      // Sparkline card + drop counters from the fixture. StatChip
      // renders its label UPPERCASED (same convention as UdaoButton).
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('SEEN'), findsOneWidget);
      expect(find.text('PARSED'), findsOneWidget);
      expect(find.text('DUPES DROPPED'), findsOneWidget);
      // Listener card, bound.
      expect(
        find.text('Bound — system binding is live.'),
        findsOneWidget,
      );
      // Battery exempt card (fake default power state).
      expect(
        find.text('Battery optimization: exempted'),
        findsOneWidget,
      );
      // No gap alert card.
      expect(find.text('Gaps found this week'), findsNothing);
    });

    testWidgets('connected but 25h stale → PAY ATTENTION (DHYAN DO)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final FakeCaptureBridge capture = FakeCaptureBridge(
        statusValue: const ListenerStatus(
          connected: true,
          lastEventAt: _now - 25 * 60 * 60 * 1000,
          componentEnabled: true,
        ),
      );
      final FakeSurvivalBridge survival = FakeSurvivalBridge();
      final ProviderContainer container = ProviderContainer(
        overrides: survivalTestOverrides(
          captureBridge: capture,
          survivalBridge: survival,
          clock: _now,
        ),
      );
      addTearDown(container.dispose);
      addTearDown(capture.close);

      await tester.pumpWidget(_dashApp(container));
      await tester.pump();
      await tester.pump();

      expect(find.text('PAY ATTENTION'), findsOneWidget);
      expect(find.text('SHARP'), findsNothing);
      expect(find.text('OFF'), findsNothing);
    });

    testWidgets('disconnected → OFF (BAND) + unbound listener card',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final FakeCaptureBridge capture = FakeCaptureBridge(
        statusValue: const ListenerStatus(
          connected: false,
          lastEventAt: 0,
          componentEnabled: false,
        ),
      );
      final FakeSurvivalBridge survival = FakeSurvivalBridge();
      final ProviderContainer container = ProviderContainer(
        overrides: survivalTestOverrides(
          captureBridge: capture,
          survivalBridge: survival,
          clock: _now,
        ),
      );
      addTearDown(container.dispose);
      addTearDown(capture.close);

      await tester.pumpWidget(_dashApp(container));
      await tester.pump();
      await tester.pump();

      expect(find.text('OFF'), findsOneWidget);
      expect(
        find.text('Not bound — the system binding is missing.'),
        findsOneWidget,
      );
      expect(find.text('Service component: DISABLED'), findsOneWidget);
    });
  });

  group('gap alert flush', () {
    testWidgets('pending payload renders + flush posts and clears',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final FakeCaptureBridge capture = FakeCaptureBridge(
        statusValue: const ListenerStatus(
          connected: true,
          lastEventAt: _now,
          componentEnabled: true,
        ),
      );
      final FakeSurvivalBridge survival = FakeSurvivalBridge();
      final FakeKvDao kv = FakeKvDao()
        ..seed(
          BackgroundJobs.kvGapAlertPending,
          jsonEncode(<String, Object?>{
            'generatedAt': _now,
            'severity': 'watch',
            'silentWeekdays': 3,
            'listenerSilentHours': null,
            'reasons': <String>['weekday_silence'],
          }),
        );
      final ProviderContainer container = ProviderContainer(
        overrides: survivalTestOverrides(
          captureBridge: capture,
          survivalBridge: survival,
          kv: kv,
          clock: _now,
        ),
      );
      addTearDown(container.dispose);
      addTearDown(capture.close);

      await tester.pumpWidget(_dashApp(container));
      await tester.pump();
      await tester.pump();

      expect(find.text('Gaps found this week'), findsOneWidget);
      // Widget tests resolve to the en fallback (gate-test convention).
      expect(
        find.text('3 weekday(s) with zero captured payments.'),
        findsOneWidget,
      );

      // Tap "seen" → notification posted + kv cleared.
      await tester.tap(find.text('SEEN — CLEAR IT'));
      await tester.pump();
      await tester.pump();
      expect(survival.postNotificationCalls, 1);
      expect(survival.lastPostedId, 1003);
      expect(kv.read(BackgroundJobs.kvGapAlertPending), isNull);
      expect(find.text('Gaps found this week'), findsNothing);
    });
  });

  group('keep-alive lever', () {
    testWidgets('arm posts to the bridge and refreshes state',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final FakeCaptureBridge capture = FakeCaptureBridge(
        statusValue: const ListenerStatus(
          connected: true,
          lastEventAt: _now,
          componentEnabled: true,
        ),
      );
      final FakeSurvivalBridge survival = FakeSurvivalBridge();
      final ProviderContainer container = ProviderContainer(
        overrides: survivalTestOverrides(
          captureBridge: capture,
          survivalBridge: survival,
          clock: _now,
        ),
      );
      addTearDown(container.dispose);
      addTearDown(capture.close);

      await tester.pumpWidget(_dashApp(container));
      await tester.pump();
      await tester.pump();

      expect(find.text('ARM KEEP-ALIVE'), findsOneWidget);
      await tester.tap(find.text('ARM KEEP-ALIVE'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(survival.startKeepAliveCalls, 1);
      // State refreshed → stop CTA now present.
      expect(find.text('STOP KEEP-ALIVE'), findsOneWidget);
    });
  });

  group('battery optimization card (flavor split)', () {
    testWidgets('power flavor: direct dialog CTA fires the direct ask',
        (tester) async {
      final FakeSurvivalBridge survival = FakeSurvivalBridge(
        powerState: const PowerState(
          ignoringBatteryOptimizations: false,
          powerSaverMode: false,
          backgroundRestricted: false,
          standbyBucket: 10,
          deviceIdle: false,
        ),
      );
      final FakeCaptureBridge capture = FakeCaptureBridge();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          ...survivalTestOverrides(
            captureBridge: capture,
            survivalBridge: survival,
          ),
          appFlavorProvider.overrideWith((Ref ref) async => AppFlavor.power),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(capture.close);

      await tester.pumpWidget(_dashApp(container, home: const _BattHost()));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Battery optimization: ON (bad for capture)'),
        findsOneWidget,
      );
      expect(find.text('OPEN DIRECT DIALOG'), findsOneWidget);

      await tester.tap(find.text('OPEN DIRECT DIALOG'));
      await tester.pump();
      await tester.pump();
      expect(survival.requestIgnoreBatteryCalls, 1);
      expect(survival.openBatteryListCalls, 0);
    });

    testWidgets('play flavor: list CTA, never the direct dialog',
        (tester) async {
      final FakeSurvivalBridge survival = FakeSurvivalBridge(
        powerState: const PowerState(
          ignoringBatteryOptimizations: false,
          powerSaverMode: false,
          backgroundRestricted: null,
          standbyBucket: null,
          deviceIdle: false,
        ),
      );
      final FakeCaptureBridge capture = FakeCaptureBridge();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          ...survivalTestOverrides(
            captureBridge: capture,
            survivalBridge: survival,
          ),
          appFlavorProvider.overrideWith((Ref ref) async => AppFlavor.play),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(capture.close);

      await tester.pumpWidget(_dashApp(container, home: const _BattHost()));
      await tester.pump();
      await tester.pump();

      expect(find.text('OPEN BATTERY LIST'), findsOneWidget);
      expect(find.text('OPEN DIRECT DIALOG'), findsNothing);

      await tester.tap(find.text('OPEN BATTERY LIST'));
      await tester.pump();
      await tester.pump();
      expect(survival.openBatteryListCalls, 1);
      expect(survival.requestIgnoreBatteryCalls, 0);
    });
  });

  testWidgets('exempt state renders the calm card', (tester) async {
    final FakeSurvivalBridge survival = FakeSurvivalBridge();
    final FakeCaptureBridge capture = FakeCaptureBridge();
    final ProviderContainer container = ProviderContainer(
      overrides: survivalTestOverrides(
        captureBridge: capture,
        survivalBridge: survival,
      ),
    );
    addTearDown(container.dispose);
    addTearDown(capture.close);

    await tester.pumpWidget(_dashApp(container, home: const _BattHost()));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Battery optimization: exempted'),
      findsOneWidget,
    );
    expect(find.text('OPEN BATTERY LIST'), findsNothing);
  });
}

class _BattHost extends StatelessWidget {
  const _BattHost();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: BatteryOptimizationCard());
  }
}
