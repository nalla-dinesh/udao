// phase-02
// The remaining DAOs in one catalog file: category, budget,
// subscription, streak, badge/challenge, jar, roast, kv,
// pending_review, capture_health.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/badge_dao.dart';
import 'package:udao/data/db/dao/budget_dao.dart';
import 'package:udao/data/db/dao/capture_health_dao.dart';
import 'package:udao/data/db/dao/category_dao.dart';
import 'package:udao/data/db/dao/jar_dao.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/dao/pending_review_dao.dart';
import 'package:udao/data/db/dao/roast_dao.dart';
import 'package:udao/data/db/dao/streak_dao.dart';
import 'package:udao/data/db/dao/subscription_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/badge.dart';
import 'package:udao/data/models/budget.dart';
import 'package:udao/data/models/capture_event.dart';
import 'package:udao/data/models/category.dart';
import 'package:udao/data/models/jar.dart';
import 'package:udao/data/models/pending_review_entry.dart';
import 'package:udao/data/models/roast_entry.dart';
import 'package:udao/data/models/txn.dart' show TxnDirection;
import 'package:udao/data/models/streak_state.dart';
import 'package:udao/data/models/subscription.dart';

import 'test_db.dart' as helper;

void main() {
  late UdaoDatabase db;

  setUp(() async {
    db = await helper.createTestDb();
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  group('CategoryDao', () {
    test('seeds are readable in sort order', () async {
      final CategoryDao dao = CategoryDao(db.db);
      final List<Category> all =
          (await dao.getAll()).valueOrNull!;
      expect(all.length, 16);
      expect(all.first.id, 'cat_khaana');
      expect(all.first.isEssential, isFalse);
      expect(
        all.any((Category c) => c.id == 'cat_rent_bill' && c.isEssential),
        isTrue,
      );
    });

    test('findById and upsertAll reseed', () async {
      final CategoryDao dao = CategoryDao(db.db);
      expect(
        (await dao.findById('cat_health')).valueOrNull?.isEssential,
        isTrue,
      );
      const Category custom = Category(
        id: 'cat_custom',
        name: 'Custom',
        icon: 'food',
        colorRole: 'flame',
        isEssential: false,
        sort: 99,
      );
      await dao.upsertAll(const <Category>[custom]);
      expect(
        (await dao.findById('cat_custom')).valueOrNull?.name,
        'Custom',
      );
    });
  });

  group('BudgetDao', () {
    test('upsert, getAll, findByCategory, delete', () async {
      final BudgetDao dao = BudgetDao(db.db);
      final Budget b = Budget(
        id: 'b1',
        categoryId: 'cat_khaana',
        limit: Money.fromRupees(2000),
        period: BudgetPeriod.monthly,
        rollover: false,
        active: true,
      );
      await dao.upsert(b);
      final List<Budget> active =
          (await dao.getAll()).valueOrNull!;
      expect(active.single.categoryId, 'cat_khaana');
      expect(active.single.limit.paise, 200000);
      await dao.upsert(
        b.copyWith(active: false),
      );
      expect((await dao.getAll()).valueOrNull, isEmpty);
      expect(
        (await dao.getAll(includeInactive: true)).valueOrNull!.length,
        1,
      );
      expect(
        (await dao.findByCategory('cat_khaana')).valueOrNull,
        isNull,
      );
      await dao.deleteById('b1');
      expect(
        (await dao.getAll(includeInactive: true)).valueOrNull,
        isEmpty,
      );
    });
  });

  group('SubscriptionDao', () {
    test('upsert, findByMerchant, markStatus', () async {
      final SubscriptionDao dao = SubscriptionDao(db.db);
      final Subscription s = Subscription(
        id: 's1',
        merchantClean: 'Netflix',
        amount: Money.fromRupees(199),
        cadenceDays: 30,
        lastSeen: DateTime(2026, 10, 27),
        status: SubscriptionStatus.active,
      );
      await dao.upsert(s);
      expect(
        (await dao.findByMerchant('Netflix')).valueOrNull!.single.id,
        's1',
      );
      await dao.markStatus('s1', SubscriptionStatus.dead);
      expect(
        (await dao.getAll()).valueOrNull!.single.status,
        SubscriptionStatus.dead,
      );
    });
  });

  group('StreakDao', () {
    test('read creates the initial single row', () async {
      final StreakDao dao = StreakDao(db.db);
      final StreakState s = (await dao.read()).valueOrNull!;
      expect(s.length, 0);
      expect(s.freezesLeft, StreakState.defaultFreezes);
    });

    test('write persists and reset restores initial state', () async {
      final StreakDao dao = StreakDao(db.db);
      final StreakState s = (await dao.read()).valueOrNull!;
      await dao.write(
        s.copyWith(
          currentStart: DateTime(2026, 10, 20),
          length: 7,
          longest: 7,
        ),
      );
      final StreakState loaded = (await dao.read()).valueOrNull!;
      expect(loaded.length, 7);
      expect(loaded.longest, 7);
      await dao.reset();
      expect((await dao.read()).valueOrNull!.length, 0);
    });
  });

  group('BadgeDao', () {
    test('badges and challenges round-trip', () async {
      final BadgeDao dao = BadgeDao(db.db);
      await dao.upsert(
        Badge(id: 'b_first_txn', unlockedAt: DateTime(2026, 10, 27)),
      );
      await dao.upsert(const Badge(id: 'b_streak_7'));
      await dao.markSeen('b_first_txn');
      final List<Badge> all = (await dao.getAll()).valueOrNull!;
      expect(
        all.firstWhere((Badge b) => b.id == 'b_first_txn').seen,
        isTrue,
      );
      expect(
        all.firstWhere((Badge b) => b.id == 'b_streak_7').unlockedAt,
        isNull,
      );

      await dao.upsertChallenge(
        const ChallengeProgress(
          id: 'c_nospend_30',
          metric: 'no_spend_days',
          current: 5,
          target: 30,
        ),
      );
      final List<ChallengeProgress> challenges =
          (await dao.allChallenges()).valueOrNull!;
      expect(challenges.single.current, 5);
    });
  });

  group('JarDao', () {
    test('insert, getAll ordering, update, delete', () async {
      final JarDao dao = JarDao(db.db);
      await dao.insert(
        Jar(
          id: 'j1',
          label: 'Goa trip',
          goal: Money.fromRupees(15000),
          saved: Money.fromRupees(1500),
          sort: 0,
          createdAt: DateTime(2026, 10, 1),
        ),
      );
      await dao.insert(
        Jar(
          id: 'j2',
          label: 'iPhone',
          goal: Money.fromRupees(80000),
          saved: const Money.zero(),
          sort: 1,
          createdAt: DateTime(2026, 10, 2),
        ),
      );
      final List<Jar> jars = (await dao.getAll()).valueOrNull!;
      expect(jars.map((Jar j) => j.id), <String>['j1', 'j2']);
      await dao.update(
        jars.first.copyWith(
          saved: Money.fromRupees(3000),
        ),
      );
      expect(
        (await dao.getAll()).valueOrNull!.first.saved.paise,
        300000,
      );
      await dao.deleteById('j2');
      expect((await dao.getAll()).valueOrNull!.length, 1);
    });
  });

  group('RoastDao', () {
    test('insert, recent ordering, usedTemplateOnDay', () async {
      final RoastDao dao = RoastDao(db.db);
      await dao.insert(
        RoastEntry(
          id: 'r1',
          templateId: 'tpl_a',
          createdAt: DateTime(2026, 10, 27, 10),
          surface: RoastSurface.verdict,
          text: 'Swiggy ki ATM ban gaya hai tu',
        ),
      );
      await dao.insert(
        RoastEntry(
          id: 'r2',
          templateId: 'tpl_b',
          createdAt: DateTime(2026, 10, 27, 12),
          surface: RoastSurface.micro,
          text: 'phir se?',
        ),
      );
      final List<RoastEntry> recent =
          (await dao.recent()).valueOrNull!;
      expect(recent.first.id, 'r2');
      expect(
        (await dao.usedTemplateOnDay(
          'tpl_a',
          DateTime(2026, 10, 27),
        ))
            .valueOrNull,
        isTrue,
      );
      expect(
        (await dao.usedTemplateOnDay(
          'tpl_a',
          DateTime(2026, 10, 26),
        ))
            .valueOrNull,
        isFalse,
      );
      expect(
        (await dao.usedTemplateOnDay(
          'tpl_z',
          DateTime(2026, 10, 27),
        ))
            .valueOrNull,
        isFalse,
      );
    });
  });

  group('KvDao', () {
    test('get/set/delete with reserved keys readable', () async {
      final KvDao dao = KvDao(db.db);
      expect((await dao.get('schema.welcome_done')).valueOrNull, isNull);
      await dao.set('schema.welcome_done', '1');
      expect(
        (await dao.get('schema.welcome_done')).valueOrNull,
        '1',
      );
      await dao.delete('schema.welcome_done');
      expect((await dao.get('schema.welcome_done')).valueOrNull, isNull);
    });
  });

  group('PendingReviewDao', () {
    test('insert, pending queue order, resolve, cleanup', () async {
      final PendingReviewDao dao = PendingReviewDao(db.db);
      for (int i = 0; i < 3; i++) {
        await dao.insert(
          PendingReviewEntry(
            id: 'p$i',
            source: 'sms',
            receivedAt: DateTime(2026, 10, 2 + i),
            rawText: 'raw $i',
            confidence: 0.7,
            amount: Money(100 + i),
            direction: TxnDirection.debit,
          ),
        );
      }
      expect((await dao.pendingCount()).valueOrNull, 3);
      final List<PendingReviewEntry> q =
          (await dao.pending()).valueOrNull!;
      expect(q.first.id, 'p0');

      await dao.resolve('p0', 'approved', at: DateTime(2026, 10, 3));
      expect((await dao.pendingCount()).valueOrNull, 2);
      expect(
        (await dao.pending()).valueOrNull!.first.id,
        'p1',
      );

      final DateTime old = DateTime(2026, 10, 1);
      final int n =
          (await dao.deleteResolvedBefore(DateTime(2026, 10, 5)))
              .valueOrNull!;
      expect(n, 1);
      expect(
        (await dao.deleteResolvedBefore(old)).valueOrNull,
        0,
      );
    });
  });

  group('CaptureHealthDao', () {
    test('insert, statsByDay, purge', () async {
      final CaptureHealthDao dao = CaptureHealthDao(db.db);
      final DateTime now = DateTime(2026, 10, 27, 12);
      await dao.insert(
        CaptureEvent(
          id: 'c1',
          source: 'sms',
          receivedAt: now,
          parsed: true,
          deduped: false,
          confidence: 0.9,
          rawHash: 'h1',
          rawText: 'secret text',
        ),
      );
      await dao.insert(
        CaptureEvent(
          id: 'c2',
          source: 'notification',
          receivedAt: now,
          parsed: false,
          deduped: false,
          confidence: 0,
          rawHash: 'h2',
          dropReason: 'otp_security',
        ),
      );
      final List<CaptureDayStats> stats =
          (await dao.statsByDay()).valueOrNull!;
      expect(stats.single.seen, 2);
      expect(stats.single.parsed, 1);

      // Purge: cutoff 24h BEFORE the events — still inside the
      // privacy window, nothing to blank.
      expect(
        (await dao.purgeRawTextOlderThan(
          now.subtract(const Duration(hours: 24)),
        ))
            .valueOrNull,
        0,
      );
      // Now everything is older than 24h -> raw_text blanked.
      expect(
        (await dao.purgeRawTextOlderThan(
          now.add(const Duration(days: 2)),
        ))
            .valueOrNull,
        1,
      );
      final List<CaptureEvent> events =
          (await dao.recent()).valueOrNull!;
      expect(
        events.firstWhere((CaptureEvent e) => e.id == 'c1').rawText,
        isNull,
      );
      expect(
        events.firstWhere((CaptureEvent e) => e.id == 'c1').rawHash,
        'h1',
      );
    });
  });
}
