// phase-04
// SMS gate widget tests: power renders the honest priming + facts +
// permission flow; play renders ONLY the off-card (fail-closed on
// unknown flavor too). Permission branches covered via a fake port.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/platform/app_flavor.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/features/capture/permission/sms_gate_screen.dart';
import 'package:udao/core/ui/udao_button.dart';
import 'package:udao/features/capture/ports/capture_ports_providers.dart';
import 'package:udao/features/capture/ports/permission_port.dart';
import 'package:udao/l10n/app_localizations.dart';

class _FakePermissionPort implements PermissionPort {
  _FakePermissionPort({
    this.permanentlyDenied = false,
  });

  // Starts denied; tests flip it to drive the grant flow.
  bool granted = false;
  bool permanentlyDenied;
  int requests = 0;

  @override
  Future<bool> isGranted(CapturePermission permission) async => granted;

  @override
  Future<Result<bool>> request(CapturePermission permission) async {
    requests++;
    if (permanentlyDenied) {
      return const Err<bool>(PermissionFailure('permanently_denied'));
    }
    return Ok<bool>(granted);
  }

  @override
  Future<Result<bool>> openSystemSettings() async => const Ok<bool>(true);
}

Widget _app(ProviderContainer container) {
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
      home: const SmsGateScreen(),
    ),
  );
}

void main() {
  testWidgets('play build: ONLY the honest off-card, no allow CTA',
      (WidgetTester tester) async {
    final _FakePermissionPort port = _FakePermissionPort();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        permissionPortProvider.overrideWithValue(port),
        appFlavorProvider.overrideWith(
          (Ref ref) async => AppFlavor.play,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    expect(find.text('SMS is off in this build'), findsOneWidget);
    expect(find.text('ALLOW SMS ACCESS'), findsNothing);
    expect(find.byType(UdaoButton), findsNothing);
  });

  testWidgets('unknown flavor fails closed (off-card)',
      (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appFlavorProvider.overrideWith((Ref ref) async => AppFlavor.unknown),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();
    expect(find.text('SMS is off in this build'), findsOneWidget);
  });

  testWidgets(
      'power build: priming + honest facts + allow flow -> granted card',
      (WidgetTester tester) async {
    final _FakePermissionPort port = _FakePermissionPort();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        permissionPortProvider.overrideWithValue(port),
        appFlavorProvider.overrideWith(
          (Ref ref) async => AppFlavor.power,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    // Honest copy is all on screen.
    expect(find.text('Bank SMS se poora hisaab'), findsOneWidget);
    expect(find.textContaining('OTPs are dropped too'), findsOneWidget);
    expect(find.textContaining('24 hours'), findsOneWidget);
    expect(find.text('ALLOW SMS ACCESS'), findsOneWidget);

    // Deny once -> still denied (card stays, can retry).
    await tester.tap(find.text('ALLOW SMS ACCESS'));
    await tester.pumpAndSettle();
    expect(port.requests, 1);
    expect(find.text('ALLOW SMS ACCESS'), findsOneWidget);

    // Grant -> the granted card replaces the CTA.
    port.granted = true;
    await tester.tap(find.text('ALLOW SMS ACCESS'));
    await tester.pumpAndSettle();
    expect(find.text('Bank SMS capture is ON'), findsOneWidget);
    expect(find.text('ALLOW SMS ACCESS'), findsNothing);
  });

  testWidgets('power build: permanently denied -> settings CTA',
      (WidgetTester tester) async {
    final _FakePermissionPort port = _FakePermissionPort(
      permanentlyDenied: true,
    );
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        permissionPortProvider.overrideWithValue(port),
        appFlavorProvider.overrideWith(
          (Ref ref) async => AppFlavor.power,
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ALLOW SMS ACCESS'));
    await tester.pumpAndSettle();

    expect(find.textContaining('denied this permanently'), findsOneWidget);
    expect(find.text('OPEN SYSTEM SETTINGS'), findsOneWidget);
  });
}
