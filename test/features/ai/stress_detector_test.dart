// phase-06
// StressDetector: pure 2-of-3 decision + gatherer against a real
// (ffi in-memory) DB + app-open stamping.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/query_repos.dart';
import 'package:udao/data/models/budget.dart';
import 'package:udao/features/ai/persona/stress_detector.dart';

import '../../data/db/test_db.dart' as helper;

void main() {
  group('pure decision (2-of-3)', () {
    const StressDetector d = StressDetector();

    test('no flags → not detected', () {
      expect(d.evaluate(const StressSignals()).detected, isFalse);
    });

    test('one flag alone never triggers', () {
      expect(
        d.evaluate(const StressSignals(spendRateDrop: true)).detected,
        isFalse,
      );
      expect(
        d.evaluate(const StressSignals(openFrequencyDrop: true)).detected,
        isFalse,
      );
      expect(
        d.evaluate(const StressSignals(consecutiveBreachDays: 3)).detected,
        isFalse,
      );
      expect(
        d.evaluate(const StressSignals(consecutiveBreachDays: 7)).detected,
        isFalse,
      );
    });

    test('two flags → detected, flags reported', () {
      final StressVerdict v = d.evaluate(
        const StressSignals(
          spendRateDrop: true,
          openFrequencyDrop: true,
        ),
      );
      expect(v.detected, isTrue);
      expect(v.flags, containsAll(<String>['spend-rate', 'open-frequency']));
    });

    test('spend + breach → detected', () {
      expect(
        d
            .evaluate(
              const StressSignals(
                spendRateDrop: true,
                consecutiveBreachDays: 4,
              ),
            )
            .detected,
        isTrue,
      );
    });

    test('open + breach(3) → detected', () {
      expect(
        d
            .evaluate(
              const StressSignals(
                openFrequencyDrop: true,
                consecutiveBreachDays: 3,
              ),
            )
            .detected,
        isTrue,
      );
    });

    test('all three → detected with 3 flags', () {
      final StressVerdict v = d.evaluate(
        const StressSignals(
          spendRateDrop: true,
          openFrequencyDrop: true,
          consecutiveBreachDays: 5,
        ),
      );
      expect(v.detected, isTrue);
      expect(v.flags, hasLength(3));
    });

    test('breach streak of 2 is not a breach flag', () {
      expect(
        const StressSignals(consecutiveBreachDays: 2).breachStreak,
        isFalse,
      );
      expect(
        const StressSignals(consecutiveBreachDays: 3).breachStreak,
        isTrue,
      );
    });
  });

  group('gatherer + stamping (real DB)', () {
    test('spend-rate drop: quiet week after a loud month', () async {
      final db = await helper.createTestDb();
      try {
        final TxnDao txns = TxnDao(db.db);
        final KvDao kv = KvDao(db.db);
        final BudgetRepo budgets = BudgetRepo(db);
        final DateTime now = DateTime(2026, 10, 30, 12);

        // Baseline: Rs.600/day for the previous ~3 weeks.
        final List<Txn> seed = <Txn>[];
        for (int back = 8; back <= 29; back++) {
          seed.add(_debit(now.subtract(Duration(days: back)), 600));
        }
        // Recent 7 days: near zero (Rs.50 once).
        seed.add(_debit(now.subtract(const Duration(days: 5)), 50));
        await txns.insertAllAtomic(seed);
        // no wallet budget → breach streak stays 0.

        final StressInputGatherer g = StressInputGatherer(
          txns: txns,
          budgets: budgets,
          kv: kv,
          clock: () => now,
        );
        final StressSignals s = await g.gather();
        expect(
          s.spendRateDrop,
          isTrue,
          reason: 'recent daily ~7 vs baseline 600',
        );
        expect(s.consecutiveBreachDays, 0);
      } finally {
        await helper.disposeTestDb(db);
      }
    });

    test('spend-rate drop: busy week → no drop signal', () async {
      final db = await helper.createTestDb();
      try {
        final TxnDao txns = TxnDao(db.db);
        final DateTime now = DateTime(2026, 10, 30, 12);
        final List<Txn> seed = <Txn>[];
        for (int back = 0; back <= 29; back++) {
          seed.add(_debit(now.subtract(Duration(days: back)), 500));
        }
        await txns.insertAllAtomic(seed);

        final StressInputGatherer g = StressInputGatherer(
          txns: txns,
          budgets: BudgetRepo(db),
          kv: KvDao(db.db),
          clock: () => now,
        );
        expect((await g.gather()).spendRateDrop, isFalse);
      } finally {
        await helper.disposeTestDb(db);
      }
    });

    test('empty history → no false positive on fresh install', () async {
      final db = await helper.createTestDb();
      try {
        final StressInputGatherer g = StressInputGatherer(
          txns: TxnDao(db.db),
          budgets: BudgetRepo(db),
          kv: KvDao(db.db),
          clock: () => DateTime(2026, 10, 30),
        );
        final StressSignals s = await g.gather();
        expect(s.spendRateDrop, isFalse);
        expect(s.openFrequencyDrop, isFalse);
        expect(s.consecutiveBreachDays, 0);
      } finally {
        await helper.disposeTestDb(db);
      }
    });

    test('open-frequency drop: 2 recent days vs 8 older days', () async {
      final db = await helper.createTestDb();
      try {
        final KvDao kv = KvDao(db.db);
        final DateTime now = DateTime(2026, 10, 30, 12);
        await stampAppOpenDay(kv, at: now);
        await stampAppOpenDay(
          kv,
          at: now.subtract(const Duration(days: 3)),
        );
        for (int back = 15; back <= 22; back++) {
          await stampAppOpenDay(
            kv,
            at: now.subtract(Duration(days: back)),
          );
        }
        final StressInputGatherer g = StressInputGatherer(
          txns: TxnDao(db.db),
          budgets: BudgetRepo(db),
          kv: kv,
          clock: () => now,
        );
        expect(
          (await g.gather()).openFrequencyDrop,
          isTrue,
          reason: '2 vs 8 opens',
        );
      } finally {
        await helper.disposeTestDb(db);
      }
    });

    test('open-frequency: no previous window → no signal', () async {
      final db = await helper.createTestDb();
      try {
        final KvDao kv = KvDao(db.db);
        final DateTime now = DateTime(2026, 10, 30, 12);
        await stampAppOpenDay(kv, at: now);
        final StressInputGatherer g = StressInputGatherer(
          txns: TxnDao(db.db),
          budgets: BudgetRepo(db),
          kv: kv,
          clock: () => now,
        );
        expect((await g.gather()).openFrequencyDrop, isFalse);
      } finally {
        await helper.disposeTestDb(db);
      }
    });

    test('wallet-budget pace breaches stack into a streak', () async {
      final db = await helper.createTestDb();
      try {
        final TxnDao txns = TxnDao(db.db);
        final DateTime now = DateTime(2026, 10, 30, 12);
        // Wallet budget Rs.3000/mo → daily share Rs.100.
        final BudgetRepo budgets = BudgetRepo(db);
        await budgets.upsert(_walletBudget(3000));
        // 3 consecutive breach days (today partial + yesterday + day-2).
        final List<Txn> seed = <Txn>[
          _debit(now.subtract(const Duration(days: 0)), 400),
          _debit(now.subtract(const Duration(days: 1)), 500),
          _debit(now.subtract(const Duration(days: 2)), 600),
        ];
        await txns.insertAllAtomic(seed);

        final StressInputGatherer g = StressInputGatherer(
          txns: txns,
          budgets: budgets,
          kv: KvDao(db.db),
          clock: () => now,
        );
        expect((await g.gather()).consecutiveBreachDays, 3);
      } finally {
        await helper.disposeTestDb(db);
      }
    });

    test('budget streak interrupted by a calm day', () async {
      final db = await helper.createTestDb();
      try {
        final TxnDao txns = TxnDao(db.db);
        final BudgetRepo budgets = BudgetRepo(db);
        final DateTime now = DateTime(2026, 10, 30, 12);
        await budgets.upsert(_walletBudget(3000));
        await txns.insertAllAtomic(<Txn>[
          _debit(now.subtract(const Duration(days: 1)), 400),
          _debit(now.subtract(const Duration(days: 2)), 500),
          // day-3 calm → streak stops at 2.
          _debit(now.subtract(const Duration(days: 3)), 20),
          _debit(now.subtract(const Duration(days: 4)), 700),
        ]);
        final StressInputGatherer g = StressInputGatherer(
          txns: txns,
          budgets: budgets,
          kv: KvDao(db.db),
          clock: () => now,
        );
        expect((await g.gather()).consecutiveBreachDays, 2);
      } finally {
        await helper.disposeTestDb(db);
      }
    });
  });

  group('stampAppOpenDay', () {
    test('stamps once per day and caps at 28 entries', () async {
      final db = await helper.createTestDb();
      try {
        final KvDao kv = KvDao(db.db);
        final DateTime now = DateTime(2026, 10, 30, 9);
        await stampAppOpenDay(kv, at: now);
        await stampAppOpenDay(kv, at: now.add(const Duration(hours: 3)));
        final String? first =
            (await kv.get(StressInputGatherer.kvOpenDays)).valueOrNull;
        expect(first, '2026-10-30');

        for (int back = 1; back <= 40; back++) {
          await stampAppOpenDay(
            kv,
            at: now.subtract(Duration(days: back)),
          );
        }
        final String? capped =
            (await kv.get(StressInputGatherer.kvOpenDays)).valueOrNull;
        final List<String> days = capped!.split(',');
        expect(days.length, 28);
        expect(days.first, '2026-10-30');
        expect(days, isNot(contains('2026-09-20')));
      } finally {
        await helper.disposeTestDb(db);
      }
    });
  });
}

Budget _walletBudget(int rupees) => Budget(
      id: 'wallet',
      limit: Money.fromRupees(rupees),
      period: BudgetPeriod.monthly,
      rollover: false,
      active: true,
    );

Txn _debit(DateTime at, int rupees) => Txn(
      id: 't-${at.millisecondsSinceEpoch}-$rupees-${at.microsecond}',
      amount: Money.fromRupees(rupees),
      direction: TxnDirection.debit,
      source: TxnSource.sms,
      rawText: 'Rs.$rupees.00 debited',
      merchantRaw: 'TESTPAY',
      merchantClean: 'testpay',
      bankOrApp: 'hdfc',
      occurredAt: at,
      capturedAt: at,
      confidence: 0.95,
      dedupKey: 'dk-${at.millisecondsSinceEpoch}-$rupees-${at.microsecond}',
    );
