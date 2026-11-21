// phase-04
// Import review widget flow: pick (faked picker + faked extractor) →
// skeleton parse → summary card → ONE confirm writes through an
// in-memory fake TxnDao (real DB semantics live in the DAO/service
// unit tests). Also the password re-prompt path for encrypted PDFs.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/features/capture/capture_providers.dart';
import 'package:udao/features/capture/import/import_review_screen.dart';
import 'fake_txn_dao.dart';
import 'package:udao/features/capture/ports/capture_ports_providers.dart';
import 'package:udao/features/capture/ports/pdf_text_extractor.dart';
import 'package:udao/features/capture/ports/statement_source.dart';
import 'package:udao/l10n/app_localizations.dart';


const String hdfcText = '''
HDFC BANK LIMITED
Statement of account  01/06/26 to 30/06/26
Account No: 50100123456767    IFSC: HDFC0000123

Date        Narration                                        Chq./Ref.No.    Value Dt    Withdrawal    Deposit    Balance

01/06/26    UPI/401234567890/SWIGGY/YESB0PTX                 401234567890    01/06/26    349.00                    45,678.90
02/06/26    NEFT CR-HDFC0000123-ACME CORP-SALARY             123456789012    02/06/26                 65,000.00    1,10,678.90

Statement generated 30/06/26
''';

class _FakeSource implements StatementSource {
  _FakeSource(this.file);
  final PickedStatement? file;
  int calls = 0;

  @override
  Future<Result<PickedStatement?>> pick(StatementFormat format) async {
    calls++;
    return Ok<PickedStatement?>(file);
  }
}

class _FakeExtractor implements PdfTextExtractor {
  _FakeExtractor(this.text, {this.passwordRequired});
  final String text;
  final String? passwordRequired;

  @override
  Future<Result<PdfExtract>> extract(String path, {String? password}) async {
    if (passwordRequired != null && password != passwordRequired) {
      return const Err<PdfExtract>(ParseFailure('pdf_password'));
    }
    return Ok(PdfExtract(pages: <String>[text]));
  }
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
      home: const ImportReviewScreen(),
    ),
  );
}


/// Bounded pumpAndSettle.
///
/// The parse/write stages mount shimmer skeletons whose
/// `AnimationController..repeat()` keeps frames scheduled BY DESIGN —
/// a plain pumpAndSettle can only exit once the stage flips, and a
/// stalled async chain would burn its entire 10-minute fake-clock
/// budget before failing opaquely. Capping the pump count makes a
/// stall fail inside the following EXPECTs (e.g. 'hdfc.pdf' not
/// found) with a message that can actually be diagnosed.
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

  testWidgets('PDF pick -> parse -> summary -> confirm writes 2 txns',
      (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        txnDaoProvider.overrideWithValue(txnDao),
        statementSourceProvider.overrideWithValue(
          _FakeSource(
            const PickedStatement(
              path: '/f/hdfc.pdf',
              displayName: 'hdfc.pdf',
            ),
          ),
        ),
        pdfTextExtractorProvider
            .overrideWithValue(_FakeExtractor(hdfcText)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    await tester.tap(find.text('CHOOSE FILE'));
    await tester.pump(); // parsing skeleton frame
    await _settle(tester);

    // Summary card.
    expect(find.text('hdfc.pdf'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Duplicates'), findsOneWidget);
    expect(find.textContaining('ADD 2 TRANSACTIONS'), findsOneWidget);

    await tester.tap(find.textContaining('ADD 2 TRANSACTIONS'));
    await _settle(tester);

    final Result<int> count = await txnDao.count();
    expect(count.valueOrNull, 2);
  });

  testWidgets('cancel at the picker stays idle (no error UI)',
      (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        txnDaoProvider.overrideWithValue(txnDao),
        statementSourceProvider
            .overrideWithValue(_FakeSource(null)),
        pdfTextExtractorProvider
            .overrideWithValue(_FakeExtractor(hdfcText)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    await tester.tap(find.text('CHOOSE FILE'));
    await _settle(tester);

    expect(find.text('CHOOSE FILE'), findsOneWidget);
    expect(find.textContaining('Could not'), findsNothing);
    expect((await txnDao.count()).valueOrNull, 0);
  });

  testWidgets('encrypted PDF: password sheet appears, then parses',
      (WidgetTester tester) async {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        txnDaoProvider.overrideWithValue(txnDao),
        statementSourceProvider.overrideWithValue(
          _FakeSource(
            const PickedStatement(
              path: '/f/enc.pdf',
              displayName: 'enc.pdf',
            ),
          ),
        ),
        pdfTextExtractorProvider.overrideWithValue(
          _FakeExtractor(hdfcText, passwordRequired: 'hunter2'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    await tester.tap(find.text('CHOOSE FILE'));
    await _settle(tester);

    // Password prompt.
    expect(find.text('Statement password'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hunter2');
    await tester.tap(find.text('OPEN STATEMENT'));
    await tester.pump();
    await _settle(tester);

    expect(find.text('enc.pdf'), findsOneWidget);
    expect(find.textContaining('ADD 2 TRANSACTIONS'), findsOneWidget);
  });

  testWidgets('duplicate re-import confirms to zero new',
      (WidgetTester tester) async {
    // Seed the ledger with the same two payments.
    final _FakeExtractor extractor = _FakeExtractor(hdfcText);
    final ProviderContainer seed = ProviderContainer(
      overrides: <Override>[
        txnDaoProvider.overrideWithValue(txnDao),
        statementSourceProvider.overrideWithValue(
          _FakeSource(
            const PickedStatement(
              path: '/f/hdfc.pdf',
              displayName: 'hdfc.pdf',
            ),
          ),
        ),
        pdfTextExtractorProvider.overrideWithValue(extractor),
      ],
    );
    addTearDown(seed.dispose);

    await tester.pumpWidget(_app(seed));
    await _settle(tester);
    await tester.tap(find.text('CHOOSE FILE'));
    await _settle(tester);
    await tester.tap(find.textContaining('ADD 2 TRANSACTIONS'));
    await _settle(tester);
    expect((await txnDao.count()).valueOrNull, 2);

    // Same file again: everything is a duplicate, CTA disabled.
    await tester.tap(find.text('CHOOSE FILE'));
    await _settle(tester);

    expect(find.text('hdfc.pdf'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.textContaining('ADD 0 TRANSACTIONS'), findsOneWidget);
    expect((await txnDao.count()).valueOrNull, 2);
  });
}
