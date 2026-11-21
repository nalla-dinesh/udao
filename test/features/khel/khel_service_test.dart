// phase-07 — KhelService over a real (FFI in-memory) DB: day sums,
// persistence, freeze token flow, idempotency, snapshot degradation.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/badge.dart';
import 'package:udao/data/models/streak_state.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/query_repos.dart';
import 'package:udao/features/khel/khel_service.dart';

import '../../data/db/test_db.dart' as helper;

/// Fixed "now"s for deterministic windows (IST-shifted UTC
/// convention — date components are what matter).
final DateTime kToday = DateTime.utc(2026, 10, 27, 12);
final DateTime kYesterday = DateTime.utc(2026, 10, 26, 12);

Txn _debitOn(DateTime at, String id) {
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
    dedupKey: 'dk-khel-$id',
  );
}

void main() {
  late UdaoDatabase db;
  late TxnDao txns;
  late KvDao kv;
  late KhelService service;
  late StreakRepo streaks;
  late KhelRepo khel;

  setUp(() async {
    db = await helper.createTestDb();
    txns = TxnDao(db.db);
    kv = KvDao(db.db);
    streaks = StreakRepo(db);
    khel = KhelRepo(db);
    service = KhelService(
      streaks: streaks,
      khel: khel,
      txns: txns,
      kv: kv,
    );
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  test('fresh install, clean yesterday — streak 1, first_day badge', () async {
    final Result<KhelEvaluation> r = await service.evaluate(now: kToday);
    expect(r.valueOrNull, isNotNull);
    expect(r.valueOrNull!.state.length, 1);
    expect(r.valueOrNull!.state.currentStart, DateTime.utc(2026, 10, 26));
    expect(r.valueOrNull!.badgesUnlocked, contains('first_day'));

    final Result<StreakState> persisted = await streaks.read();
    expect(persisted.valueOrNull!.length, 1);
  });

  test('a debit on yesterday keeps the fresh state at zero', () async {
    await txns.upsertByDedupKey(
      _debitOn(DateTime.utc(2026, 10, 26, 10), 't1'),
    );
    final Result<KhelEvaluation> r = await service.evaluate(now: kToday);
    expect(r.valueOrNull!.state.length, 0);
    expect(r.valueOrNull!.state.currentStart, isNull);
    expect(r.valueOrNull!.badgesUnlocked, isEmpty);
  });

  test('days walk forward across passes — 2 clean days -> streak 2', () async {
    final Result<KhelEvaluation> first = await service.evaluate(now: kYesterday);
    expect(first.valueOrNull!.state.length, 1);

    final Result<KhelEvaluation> second = await service.evaluate(now: kToday);
    expect(second.valueOrNull!.state.length, 2,
        reason: 'the 26th was clean too — judged in the second pass');
  });

  test('a spend after a streak breaks it (live transition)', () async {
    await service.evaluate(now: kYesterday); // streak 1 (25th clean)
    await txns.upsertByDedupKey(
      _debitOn(DateTime.utc(2026, 10, 26, 10), 't2'),
    );
    final Result<KhelEvaluation> r = await service.evaluate(now: kToday);
    expect(r.valueOrNull!.state.length, 0);
    expect(r.valueOrNull!.state.longest, 1, reason: 'history kept');
  });

  test('evaluation is idempotent — re-running never double-counts', () async {
    await service.evaluate(now: kToday);
    final Result<KhelEvaluation> second = await service.evaluate(now: kToday);
    expect(second.valueOrNull!.state.length, 1,
        reason: 'lastNoSpendDate advanced past yesterday');
  });

  test('committed freeze protects a spend-day and clears the token', () async {
    // Build a live streak: yesterday clean -> length 1.
    await service.evaluate(now: kYesterday);

    // Commit a freeze for the 26th, then spend on it.
    final DateTime freezeDay = DateTime.utc(2026, 10, 26, 9);
    final Result<bool> committed = await service.commitFreezeForDay(freezeDay);
    expect(committed.valueOrNull, isTrue);
    await txns.upsertByDedupKey(_debitOn(DateTime.utc(2026, 10, 26, 18), 't3'));

    final Result<KhelEvaluation> r = await service.evaluate(now: kToday);
    expect(r.valueOrNull!.state.length, 1, reason: 'protected, not grown');
    expect(r.valueOrNull!.state.freezesLeft, 1);
    expect(r.valueOrNull!.badgesUnlocked, contains('freeze_first'));

    // Token consumed: nothing pending anymore.
    expect(await service.freezeCommittedFor(freezeDay), isFalse);
  });

  test('freeze commit refused with zero tokens', () async {
    await streaks.write(
      const StreakState(length: 3, freezesLeft: 0, longest: 3),
    );
    final Result<bool> r = await service.commitFreezeForDay(kToday);
    expect(r.valueOrNull, isFalse);
  });

  test('challenge completion earns freezes (7-day run)', () async {
    // Seed a 6-day live streak directly, judge one clean day.
    final DateTime start = DateTime.utc(2026, 10, 20);
    await streaks.write(
      StreakState(
        currentStart: start,
        length: 6,
        freezesLeft: 0,
        longest: 6,
        lastNoSpendDate: DateTime.utc(2026, 10, 25),
      ),
    );
    final Result<KhelEvaluation> r = await service.evaluate(now: kToday);
    expect(r.valueOrNull!.state.length, 7);
    expect(r.valueOrNull!.challengesCompleted, contains('no_spend_7'));
    expect(r.valueOrNull!.state.freezesLeft, 1,
        reason: 'the 7-day challenge pays one freeze');
  });

  test('badges persist as unseen rows', () async {
    final Result<KhelEvaluation> r = await service.evaluate(now: kToday);
    final List<String> ids = r.valueOrNull!.badgesUnlocked;
    final Result<List<Badge>> badges = await khel.allBadges();
    final Set<String> stored =
        badges.valueOrNull!.map((Badge b) => b.id).toSet();
    expect(stored, containsAll(ids));
    expect(
      badges.valueOrNull!.every((Badge b) => !b.seen),
      isTrue,
      reason: 'fresh unlocks glow until viewed',
    );
  });

  test('snapshot degrades to a usable state on evaluate failure', () async {
    // Close the DB under the service — everything fails softly.
    await db.close();
    final KhelSnapshot snap = await service.snapshot();
    expect(snap.state.length, 0);
    expect(snap.todaySpendPaise, 0);
    expect(snap.badges, isEmpty);
    expect(snap.challenges, isEmpty);
  });
}
