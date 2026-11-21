// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/capture_health_dao.dart';
import 'package:udao/data/db/dao/pending_review_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/capture_event.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/parser_types.dart';
import 'package:udao/data/repos/capture_pipeline_result.dart';
import 'package:udao/data/repos/ledger_repo.dart';

import '../db/test_db.dart' as helper;

void main() {
  late UdaoDatabase db;
  late LedgerRepo repo;
  late TxnDao txns;
  late CaptureHealthDao health;
  late PendingReviewDao reviews;

  setUp(() async {
    db = await helper.createTestDb();
    repo = LedgerRepo(db);
    txns = TxnDao(db.db);
    health = CaptureHealthDao(db.db);
    reviews = PendingReviewDao(db.db);
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  ParserInput sms(
    String text, {
    String? sender = 'VM-HDFCBK',
    DateTime? at,
  }) =>
      ParserInput(
        text: text,
        receivedAt: at ?? DateTime(2026, 10, 27, 18, 45),
        sender: sender,
      );

  ParserInput notif(String pkg, String text, {DateTime? at}) =>
      ParserInput(
        text: text,
        receivedAt: at ?? DateTime(2026, 10, 27, 18, 45),
        packageKey: pkg,
      );

  test('auto-band capture writes a txn + health row', () async {
    final Result<IngestOutcome> r = await repo.ingest(
      sms(
        'Rs.148.00 debited from A/c No. XX1234 on 27-10-26 '
            'REF 512345678901 SWIGGY.',
      ),
    );
    final IngestOutcome out = r.valueOrNull!;
    expect(out.status, IngestStatus.autoAccepted);
    expect(out.txnId, isNotNull);
    final Txn t = (await txns.findById(out.txnId!)).valueOrNull!;
    expect(t.amount.paise, 14800);
    expect(t.merchantClean, 'Swiggy');
    expect(t.source, TxnSource.sms);
    expect(t.bankOrApp, 'hdfc');
    final List<CaptureEvent> events = (await health.recent()).valueOrNull!;
    expect(events.single.parsed, isTrue);
    expect(events.single.parserId, 'hdfc');
    expect(events.single.rawText, contains('SWIGGY'));
    expect(events.single.dropReason, isNull);
  });

  test('notification source is tagged for package-keyed inputs', () async {
    await repo.ingest(
      notif('com.google.android.apps.nbu.paysa', 'You sent ₹150 to Swiggy'),
    );
    final List<Txn> page = (await txns.page()).valueOrNull!;
    expect(page.single.source, TxnSource.notification);
  });

  test('exact duplicate ingest is a no-op duplicate outcome', () async {
    await repo.ingest(
      sms(
        'Rs.148.00 debited from A/c No. XX1234 on 27-10-26 '
            'REF 512345678901 SWIGGY.',
      ),
    );
    final Result<IngestOutcome> again = await repo.ingest(
      sms(
        'Rs.148.00 debited from A/c No. XX1234 on 27-10-26 '
            'REF 512345678901 SWIGGY.',
        at: DateTime(2026, 10, 27, 18, 46),
      ),
    );
    expect(again.valueOrNull!.status, IngestStatus.duplicate);
    expect((await txns.count()).valueOrNull, 1);
    final List<CaptureEvent> events = (await health.recent()).valueOrNull!;
    // recent() is newest-first: the duplicate record (18:46) leads,
    // the original capture (18:45) is last.
    expect(events.first.deduped, isTrue);
  });

  test('cross-source near-duplicate is suppressed via findNear', () async {
    final DateTime at = DateTime(2026, 10, 27, 18, 45);
    // GPay notification lands first (no ref number).
    await repo.ingest(
      notif('com.google.android.apps.nbu.paysa', 'You sent ₹150 to Swiggy', at: at),
    );
    // The HDFC SMS for the same payment arrives 3 minutes later with
    // its own ref -> different fingerprint, but findNear catches it.
    final Result<IngestOutcome> bank = await repo.ingest(
      sms(
        'Rs.150.00 debited from A/c No. XX1234 on 27-10-26 '
            'REF 512345678901 SWIGGY.',
        at: at.add(const Duration(minutes: 3)),
      ),
    );
    expect(bank.valueOrNull!.status, IngestStatus.duplicate);
    expect((await txns.count()).valueOrNull, 1);
  });

  test('review-band capture queues instead of writing', () async {
    final Result<IngestOutcome> r = await repo.ingest(
      notif('com.google.android.apps.nbu.paysa', 'Payment of ₹250 pending approval'),
    );
    final IngestOutcome out = r.valueOrNull!;
    expect(out.status, IngestStatus.pendingReview);
    expect(out.reviewEntry, isNotNull);
    expect(out.reviewEntry!.amount!.paise, 25000);
    expect((await txns.count()).valueOrNull, 0);
    expect((await reviews.pendingCount()).valueOrNull, 1);
  });

  test('OTP drop records the drop code, no txn, no review', () async {
    final Result<IngestOutcome> r =
        await repo.ingest(sms('Your OTP is 4832. Do not share.'));
    expect(r.failureOrNull?.message, 'otp_security');
    expect((await txns.count()).valueOrNull, 0);
    expect((await reviews.pendingCount()).valueOrNull, 0);
    final List<CaptureEvent> events = (await health.recent()).valueOrNull!;
    expect(events.single.dropReason, 'otp_security');
    expect(events.single.parsed, isFalse);
  });

  test('promo drop records promo_marketing', () async {
    final Result<IngestOutcome> r = await repo.ingest(
      sms(
        'FLAT 50% OFF on all orders above Rs.500!',
        sender: null,
      ),
    );
    expect(r.failureOrNull?.message, 'promo_marketing');
  });

  test('no-parser-match drop records the code', () async {
    final Result<IngestOutcome> r = await repo.ingest(
      sms('Dear Customer, your KYC is pending.'),
    );
    expect(r.failureOrNull?.message, 'no_parser_match');
    final List<CaptureEvent> events = (await health.recent()).valueOrNull!;
    expect(events.single.dropReason, 'no_parser_match');
  });

  test('health stats aggregate per day', () async {
    await repo.ingest(
      sms(
        'Rs.148.00 debited from A/c No. XX1234 on 27-10-26 '
            'REF 512345678901 SWIGGY.',
      ),
    );
    await repo.ingest(sms('Your OTP is 4832. Do not share.'));
    final List<CaptureDayStats> stats =
        (await health.statsByDay()).valueOrNull!;
    expect(stats.single.seen, 2);
    expect(stats.single.parsed, 1);
  });

  test('purge blanks raw_text after the privacy window', () async {
    final DateTime old = DateTime(2026, 10, 1, 10);
    await repo.ingest(
      sms(
        'Rs.148.00 debited from A/c No. XX1234 on 27-10-26 '
            'REF 512345678901 SWIGGY.',
        at: old,
      ),
    );
    final int purged =
        (await health.purgeRawTextOlderThan(old.add(const Duration(days: 2))))
            .valueOrNull!;
    expect(purged, 1);
    final List<CaptureEvent> events = (await health.recent()).valueOrNull!;
    expect(events.single.rawText, isNull);
    expect(events.single.rawHash, isNotEmpty);
  });

  test('warmUp opens the database without error', () async {
    await repo.warmUp();
    // Second call is a no-op on the cached handle.
    await repo.warmUp();
  });
}
