// phase-08 — BudgetScreen widget smoke: empty state on a fresh DB,
// hero + spend bar with a seeded wallet line, flame stamp when the
// line is crossed, and the edit sheet opens with its target picker.
// Pump-based (never pumpAndSettle — see the Aaj screen note).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/budget.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/query_repos.dart';
import 'package:udao/core/ui/spend_bar.dart';
import 'package:udao/features/budget/budget_screen.dart';
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
      home: BudgetScreen(),
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

void main() {
  late UdaoDatabase db;
  late BudgetRepo budgets;
  late TxnDao txns;

  setUp(() async {
    db = await helper.createTestDb();
    budgets = BudgetRepo(db);
    txns = TxnDao(db.db);
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  Future<void> seedWalletLine(int limitPaise, {int spentPaise = 0}) async {
    await budgets.upsert(Budget(
      id: 'wallet',
      categoryId: null,
      limit: Money(limitPaise),
      period: BudgetPeriod.monthly,
      rollover: false,
      active: true,
    ));
    if (spentPaise > 0) {
      // nowIst() is the exact instant statusOf counts up to, so
      // this txn is inside the current window on ANY day of the
      // month (a plain DateTime.now() can fall out at month edges).
      final DateTime at = IstDates.nowIst();
      await txns.upsertByDedupKey(Txn(
        id: 't-$spentPaise',
        amount: Money(spentPaise),
        direction: TxnDirection.debit,
        source: TxnSource.manual,
        rawText: '',
        merchantRaw: 'Test',
        merchantClean: 'Test',
        bankOrApp: 'manual',
        occurredAt: at,
        capturedAt: at,
        confidence: 0.98,
        dedupKey: 'dk-budget-screen-$spentPaise',
      ));
    }
  }

  testWidgets('fresh DB: the honest empty state', (tester) async {
    await tester.pumpWidget(_app());
    await _settle(tester);

    expect(find.byType(BudgetScreen), findsOneWidget);
    expect(find.text('Koi rekha nahi'), findsOneWidget);
  });

  testWidgets('a wallet line renders the hero and the spend bar',
      (tester) async {
    await seedWalletLine(500000, spentPaise: 150000);
    await tester.pumpWidget(_app());
    await _settle(tester);

    // Hero label (uppercased by the hero itself) + the spend bar.
    expect(find.text('POORA WALLET'), findsOneWidget);
    expect(find.byType(SpendBar), findsOneWidget);
    expect(find.text('REKHA CROSS'), findsNothing);
  });

  testWidgets('a crossed line flames', (tester) async {
    await seedWalletLine(100000, spentPaise: 250000);
    await tester.pumpWidget(_app());
    await _settle(tester);

    expect(find.text('REKHA CROSS'), findsOneWidget);
  });

  testWidgets('FAB opens the sheet with the target picker; a save lands',
      (tester) async {
    await tester.pumpWidget(_app());
    await _settle(tester);
    expect(find.text('Koi rekha nahi'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);

    // Sheet title + the wallet target chip. 'Nayi rekha' appears
    // TWICE while the sheet is open: FAB label + sheet title.
    expect(find.text('Nayi rekha'), findsNWidgets(2));
    expect(find.text('Poora wallet'), findsOneWidget);

    // Type a limit and save (UdaoButton uppercases its label).
    await tester.enterText(find.byType(TextField), '5000');
    await tester.tap(find.text('REKHA LAGAO'));
    await _settle(tester);
    await _settle(tester);

    // The sheet closed (only the FAB label remains) and the hero
    // took the new line.
    expect(find.text('Nayi rekha'), findsNWidgets(1));
    expect(find.text('POORA WALLET'), findsOneWidget);
  });
}
