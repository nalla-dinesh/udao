// phase-07 — KhelScreen widget smoke: mounts over the test DB, shows
// the streak state, deterministic against the real clock (a seeded
// debit on yesterday pins the streak to zero; a live streak pinned
// to yesterday keeps its length). Pump-based (never pumpAndSettle —
// see the Aaj screen note).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/streak_state.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/query_repos.dart';
import 'package:udao/features/shell/screens/khel_screen.dart';
import 'package:udao/l10n/app_localizations.dart';

import '../../data/db/test_db.dart' as helper;

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      theme: UdaoTheme.dark(),
      localizationsDelegates: <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: KhelScreen(),
    ),
  );
}

Future<void> _settle(WidgetTester tester, {int maxPumps = 60}) async {
  for (int i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

Txn _debitYesterday(String id) {
  final DateTime at =
      IstDates.startOfDay(IstDates.nowIst()).subtract(const Duration(days: 1)).add(
        const Duration(hours: 10),
      );
  return Txn(
    id: id,
    amount: Money(10000),
    direction: TxnDirection.debit,
    source: TxnSource.manual,
    rawText: '',
    merchantRaw: 'Test',
    merchantClean: 'Test',
    bankOrApp: 'manual',
    occurredAt: at,
    capturedAt: at,
    confidence: 0.98,
    dedupKey: 'dk-khel-screen-$id',
  );
}

void main() {
  late UdaoDatabase db;

  setUp(() async {
    db = await helper.createTestDb();
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  testWidgets('mounts and shows the zero-streak state', (tester) async {
    // A debit on yesterday pins the streak to zero deterministically.
    await TxnDao(db.db).upsertByDedupKey(_debitYesterday('s1'));

    await tester.pumpWidget(_app());
    await _settle(tester);

    expect(find.byType(KhelScreen), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.text('Chindi Ladder'), findsOneWidget);
    expect(find.text('Badges'), findsOneWidget);
    expect(find.text('Challenges'), findsOneWidget);
  });

  testWidgets('a live streak pinned to yesterday renders its length',
      (tester) async {
    final DateTime yesterday =
        IstDates.startOfDay(IstDates.nowIst()).subtract(const Duration(days: 1));
    await StreakRepo(db).write(
      StreakState(
        currentStart: yesterday.subtract(const Duration(days: 4)),
        length: 4,
        freezesLeft: 2,
        longest: 9,
        lastNoSpendDate: yesterday,
      ),
    );

    await tester.pumpWidget(_app());
    await _settle(tester);

    expect(find.text('4'), findsWidgets);
    expect(find.text('9'), findsWidgets);
  });
}
