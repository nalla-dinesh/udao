// phase-03
// The 40-event end-to-end burn: unique txns, exact duplicates, OTP
// drops, promo drops and pending-review events flow through the REAL
// pipeline (real DB, real filters, real parsers, real dedup) — only
// the bridge is faked, and the pipeline never touches it anyway.
// Asserts the ledger contents, the kv metric counters and the
// TxnCaptured broadcast.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/repos/capture_pipeline_result.dart';
import 'package:udao/data/repos/ledger_repo.dart';
import 'package:udao/features/capture/bridge/capture_raw_event.dart';
import 'package:udao/features/capture/pipeline/capture_pipeline.dart';
import 'package:udao/features/capture/pipeline/ledger_events.dart';

import '../../data/db/test_db.dart';

const String _gpay = 'com.google.android.apps.nbu.paysa';
const String _phonepe = 'com.phonepe.app';

void main() {
  late UdaoDatabase db;
  late CapturePipeline pipeline;
  late LedgerEvents events;
  final DateTime base = DateTime(2026, 10, 27, 9, 0);

  CaptureRawEvent raw({
    required String pkg,
    required String text,
    required int offsetMs,
  }) {
    return CaptureRawEvent(
      pkg: pkg,
      title: '',
      text: text,
      bigText: '',
      subText: '',
      ts: base.millisecondsSinceEpoch + offsetMs,
    );
  }

  setUp(() async {
    db = await createTestDb();
    events = LedgerEvents();
    pipeline = CapturePipeline(
      repo: LedgerRepo(db),
      txnDao: TxnDao(db.db),
      kvDao: KvDao(db.db),
      events: events,
    );
  });

  tearDown(() async {
    await disposeTestDb(db);
    events.dispose();
  });

  test('40 mixed events -> correct ledger, counters and broadcast', () async {
    // 28 unique, parseable debits with cycling merchants. Amounts
    // vary so every fingerprint differs.
    final List<CaptureRawEvent> unique = <CaptureRawEvent>[
      for (int i = 0; i < 28; i++)
        raw(
          pkg: i.isEven ? _gpay : _phonepe,
          text: i.isEven
              ? '\u20b9${50 + i * 3} sent to ${_merchants[i % _merchants.length]}'
              : '\u20b9${50 + i * 3} paid to ${_merchants[i % _merchants.length]} via PhonePe',
          offsetMs: i * 1000,
        ),
    ];
    // 5 exact duplicates of the first five uniques (WAL replay shape).
    final List<CaptureRawEvent> dupes = <CaptureRawEvent>[
      for (int i = 0; i < 5; i++) unique[i],
    ];
    // 3 OTP drops.
    final List<CaptureRawEvent> otps = <CaptureRawEvent>[
      for (int i = 0; i < 3; i++)
        raw(
          pkg: _gpay,
          text: '${400000 + i * 7} is your One Time Password (OTP). '
              'Valid for 5 minutes.',
          offsetMs: 60000 + i * 1000,
        ),
    ];
    // 2 promo drops.
    final List<CaptureRawEvent> promos = <CaptureRawEvent>[
      for (int i = 0; i < 2; i++)
        raw(
          pkg: 'net.one97.paytm',
          text: 'Cashback offer! Get Rs.50 back on your next recharge.',
          offsetMs: 70000 + i * 1000,
        ),
    ];
    // 2 pending-review events (parse ok, not enough signal to
    // auto-accept; corpus-shape texts).
    final List<CaptureRawEvent> pendings = <CaptureRawEvent>[
      raw(
        pkg: _phonepe,
        text: 'Transaction \u20b988 at CHAI POINT successful',
        offsetMs: 80000,
      ),
      raw(
        pkg: _gpay,
        text: 'Payment of \u20b9250 pending approval',
        offsetMs: 81000,
      ),
    ];

    final List<CaptureRawEvent> all = <CaptureRawEvent>[
      ...unique,
      ...dupes,
      ...otps,
      ...promos,
      ...pendings,
    ];
    expect(all, hasLength(40));

    // Broadcast listener armed BEFORE the run: emissions are
    // synchronous (broadcast controller), so after every awaited
    // run() the list is already complete.
    final List<TxnCaptured> broadcast = <TxnCaptured>[];
    final StreamSubscription<TxnCaptured> sub =
        events.stream.listen(broadcast.add);

    for (final CaptureRawEvent event in all) {
      await pipeline.run(event);
    }

    // Ledger: exactly the 28 unique txns — dupes absorbed, drops
    // discarded, pendings parked in review (not in txn).
    final Result<int> count = await TxnDao(db.db).count();
    expect(count.valueOrNull, 28);

    // Broadcast: one event per auto-accepted txn, none for the rest.
    expect(broadcast, hasLength(28));
    expect(broadcast.every((TxnCaptured e) => e.amountPaise > 0), isTrue);
    // Ordering preserved: first broadcast is the first unique event.
    expect(broadcast.first.merchantClean, 'Swiggy');
    expect(broadcast.first.amountPaise, (50 + 0 * 3) * 100);

    // Counters (kv — counts only, never raw text: privacy law).
    final KvDao kv = KvDao(db.db);
    expect((await kv.get('cap_txn')).valueOrNull, '28');
    expect((await kv.get('cap_dup')).valueOrNull, '5');
    expect((await kv.get('cap_review')).valueOrNull, '2');
    expect((await kv.get('cap_drop_otp_security')).valueOrNull, '3');
    expect((await kv.get('cap_drop_promo_marketing')).valueOrNull, '2');

    // Categorization: alias-map merchants got their cat_*; CHAI WALA
    // (unknown) kept a null category and bumped cat_unknown.
    final Result<List<Txn>> page =
        await TxnDao(db.db).page(limit: 100, offset: 0);
    final List<Txn> txns = page.valueOrNull ?? const <Txn>[];
    expect(txns, hasLength(28));

    final int chaiWala = txns
        .where((Txn t) => t.merchantClean == 'Chai Wala')
        .length;
    expect(chaiWala, 5, reason: '28 events / 5 merchants');
    expect(
      txns
          .where((Txn t) => t.merchantClean == 'Chai Wala')
          .every((Txn t) => t.categoryId == null),
      isTrue,
      reason: 'unknown merchants stay uncategorised ("Other")',
    );
    expect(
      txns
          .where((Txn t) => t.merchantClean == 'Swiggy')
          .every((Txn t) => t.categoryId == 'cat_khaana'),
      isTrue,
    );
    expect(
      txns
          .where((Txn t) => t.merchantClean == 'Blinkit')
          .every((Txn t) => t.categoryId == 'cat_groceries'),
      isTrue,
    );
    expect(
      txns
          .where((Txn t) => t.merchantClean == 'Amazon')
          .every((Txn t) => t.categoryId == 'cat_shopping'),
      isTrue,
    );
    expect((await kv.get('cat_unknown')).valueOrNull, '5');
    expect((await kv.get('cap_review')).valueOrNull, '2');

    await sub.cancel();
  });

  test('drop path stays silent on the broadcast and counts only the drop',
      () async {
    int heard = 0;
    final StreamSubscription<TxnCaptured> sub =
        events.stream.listen((_) => heard++);

    await pipeline.run(
      raw(
        pkg: _gpay,
        text: 'Cashback offer! Get Rs.50 back on your next recharge.',
        offsetMs: 5000,
      ),
    );

    expect(heard, 0, reason: 'drops never emit TxnCaptured');
    final KvDao kv = KvDao(db.db);
    expect((await kv.get('cap_txn')).valueOrNull, isNull);
    expect((await kv.get('cap_drop_promo_marketing')).valueOrNull, '1');

    await sub.cancel();
  });

  test('re-running the same event twice is idempotent (WAL replay shape)',
      () async {
    final CaptureRawEvent e = raw(
      pkg: _gpay,
      text: '\u20b9148 sent to Swiggy',
      offsetMs: 1000,
    );
    final Result<IngestOutcome> first = await pipeline.run(e);
    final Result<IngestOutcome> second = await pipeline.run(e);

    expect(first.valueOrNull?.status, IngestStatus.autoAccepted);
    expect(second.valueOrNull?.status, IngestStatus.duplicate);

    final Result<int> txns = await TxnDao(db.db).count();
    expect(txns.valueOrNull, 1);
    final KvDao kv = KvDao(db.db);
    expect((await kv.get('cap_txn')).valueOrNull, '1');
    expect((await kv.get('cap_dup')).valueOrNull, '1');
  });
}

const List<String> _merchants = <String>[
  'Swiggy',
  'Zepto',
  'BLINKIT',
  'CHAI WALA',
  'Amazon',
];
