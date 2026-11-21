// phase-04
// QuickAdd widget flow: Likho saves a manual txn in ≤3 taps through
// an in-memory fake TxnDao (real DB semantics live in the DAO unit
// tests); Bolo turns spoken Hinglish into a confirm card and a
// voice-source txn. VoiceInput is faked.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/features/capture/capture_providers.dart' show txnDaoProvider;
import 'package:udao/features/capture/ports/capture_ports_providers.dart';
import 'package:udao/features/capture/ports/voice_input.dart';
import 'package:udao/features/capture/quick/quick_add_sheet.dart';
import 'fake_txn_dao.dart';
import 'package:udao/l10n/app_localizations.dart';


class _FakeVoice implements VoiceInput {
  _FakeVoice(this.reply);
  final Result<String> reply;

  @override
  Future<bool> initialize() async => true;

  @override
  Future<Result<String>> listenOnce({
    String localeId = 'en-IN',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return reply;
  }

  @override
  Future<void> stop() async {}
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
      home: const Scaffold(body: SizedBox.shrink()),
    ),
  );
}



/// Realistic phone viewport (412x915 logical). The default 800x600
/// test surface clips tall bottom sheets: the modal's content column
/// gets only ~550px there, while the 520px QuickAdd sheet + dialog
/// chrome needs ~582px. Real devices are 800+ logical px tall, so
/// the sheet that ships is the sheet under test.
void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Bounded pumpAndSettle.
///
/// The parse/write stages mount shimmer skeletons whose
/// `AnimationController..repeat()` keeps frames scheduled BY DESIGN —
/// a plain pumpAndSettle can only exit once the stage flips, and a
/// stalled async chain would burn its entire 10-minute fake-clock
/// budget before failing opaquely. Capping the pump count makes a
/// stall fail inside the following EXPECTs (e.g. the saved-toast
/// text not found) with a message that can actually be diagnosed.
Future<void> _settle(WidgetTester tester, {int maxPumps = 50}) async {
  for (int i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

void main() {
  // In-memory fake DAO: the widget FLOW is under test here — real DB
  // semantics live in the DAO / statement-import unit tests.
  late FakeTxnDao txnDao;

  setUp(() {
    txnDao = FakeTxnDao();
  });

  testWidgets('Likho: 1-2-5 on the pad -> Save -> manual txn written',
      (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[txnDaoProvider.overrideWithValue(txnDao)],
    );
    addTearDown(container.dispose);
    _phoneViewport(tester);
    await tester.pumpWidget(_app(container));

    await tester.pump();
    // Fire-and-forget: the returned future completes when the sheet
    // is DISMISSED — awaiting it deadlocks the test (the taps that
    // would close the sheet sit behind the await).
    unawaited(showQuickAddSheet(tester.element(find.byType(SizedBox))));
    await _settle(tester);

    // Likho tab.
    await tester.tap(find.text('Type'));
    await _settle(tester);

    // Amount: 1, 2, 5 on the big pad.
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();
    await tester.tap(find.text('5'));
    await tester.pump();

    // Merchant + category via chips.
    await tester.enterText(
      find.byType(TextField).first,
      'Swiggy',
    );
    await tester.pump();
    await tester.tap(find.text('Khaana'));
    await tester.pump();

    expect(find.text('\u20b9125'), findsOneWidget);

    await tester.tap(find.text('SAVE'));
    await _settle(tester);

    final Result<int> count = await txnDao.count();
    expect(count.valueOrNull, 1);
    final Result<List<Txn>> rows = await txnDao.page(limit: 5);
    final Txn t = rows.valueOrNull!.single;
    expect(t.amount.paise, 12500);
    expect(t.source, TxnSource.manual);
    expect(t.categoryId, 'cat_khaana');
    expect(t.merchantClean, 'Swiggy');
  });

  testWidgets('Bolo: "sawa sau auto ka" -> confirm card -> voice txn',
      (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        txnDaoProvider.overrideWithValue(txnDao),
        voiceInputProvider.overrideWithValue(
          _FakeVoice(const Ok<String>('sawa sau auto ka')),
        ),
      ],
    );
    addTearDown(container.dispose);
    _phoneViewport(tester);
    await tester.pumpWidget(_app(container));

    // Fire-and-forget: the returned future completes when the sheet
    // is DISMISSED — awaiting it deadlocks the test (the taps that
    // would close the sheet sit behind the await).
    unawaited(showQuickAddSheet(tester.element(find.byType(SizedBox))));
    await _settle(tester);

    // Bolo is the default tab.
    await tester.tap(find.text('START SPEAKING'));
    await _settle(tester);

    // The confirm question card (test locale is en).
    expect(find.textContaining('Is this right?'), findsOneWidget);
    expect(find.textContaining('\u20b9125'), findsOneWidget);
    expect(find.textContaining('auto'), findsWidgets);

    await tester.tap(find.text('SAVE'));
    await _settle(tester);

    final Result<List<Txn>> rows = await txnDao.page(limit: 5);
    final Txn t = rows.valueOrNull!.single;
    expect(t.amount.paise, 12500);
    expect(t.source, TxnSource.voice);
    expect(t.categoryId, 'cat_transport');
    expect(t.direction, TxnDirection.debit);
  });

  testWidgets('Bolo: nothing heard -> honest snack, nothing written',
      (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        txnDaoProvider.overrideWithValue(txnDao),
        voiceInputProvider.overrideWithValue(
          _FakeVoice(const Err<String>(CaptureFailure('voice_timeout'))),
        ),
      ],
    );
    addTearDown(container.dispose);
    _phoneViewport(tester);
    await tester.pumpWidget(_app(container));

    // Fire-and-forget: the returned future completes when the sheet
    // is DISMISSED — awaiting it deadlocks the test (the taps that
    // would close the sheet sit behind the await).
    unawaited(showQuickAddSheet(tester.element(find.byType(SizedBox))));
    await _settle(tester);

    await tester.tap(find.text('START SPEAKING'));
    await _settle(tester);

    expect(find.textContaining('Nothing was heard'), findsOneWidget);
    final Result<int> count = await txnDao.count();
    expect(count.valueOrNull, 0);
  });
}
