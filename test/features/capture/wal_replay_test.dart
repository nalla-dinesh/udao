// phase-03
// WAL replay on a real in-memory DB: torn-line skipping, dedup-absorbed
// replays, ack advancing past drops (at-least-once semantics), and
// raw-line parseability of the model round-trip.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/repos/ledger_repo.dart';
import 'package:udao/features/capture/bridge/capture_raw_event.dart';
import 'package:udao/features/capture/bridge/wal_replay.dart';
import 'package:udao/features/capture/pipeline/capture_pipeline.dart';
import 'package:udao/features/capture/pipeline/ledger_events.dart';

import '../../data/db/test_db.dart';
import 'fake_capture_bridge.dart';

const String _gpay = 'com.google.android.apps.nbu.paysa';
const String _phonepe = 'com.phonepe.app';

void main() {
  late UdaoDatabase db;
  late FakeCaptureBridge bridge;
  late CapturePipeline pipeline;
  late LedgerEvents events;
  final DateTime base = DateTime(2026, 10, 27, 10, 0);

  CaptureRawEvent event({
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
    bridge = FakeCaptureBridge();
  });

  tearDown(() async {
    await disposeTestDb(db);
    events.dispose();
    await bridge.close();
  });

  test('CaptureRawEvent line round-trip', () {
    final CaptureRawEvent original = event(
      pkg: _gpay,
      text: '\u20b9148 sent to Swiggy',
      offsetMs: 1000,
    );
    final CaptureRawEvent? parsed = CaptureRawEvent.fromLine(original.toLine());
    expect(parsed, isNotNull);
    expect(parsed!.pkg, original.pkg);
    expect(parsed.fullText, original.fullText);
    expect(parsed.ts, original.ts);
  });

  test('torn / malformed lines parse to null, never throw', () {
    expect(CaptureRawEvent.fromLine('{"pkg": "com.pho'), isNull);
    expect(CaptureRawEvent.fromLine('not json at all'), isNull);
    expect(CaptureRawEvent.fromLine('{"pkg": 42, "ts": "x"}'), isNull);
    expect(CaptureRawEvent.fromLine('{"ts": 123}'), isNull); // no pkg
    expect(
      CaptureRawEvent.fromLine(
        '{"pkg": "a.b", "title": null, "ts": 5}',
      ),
      isNotNull, // nullable fields tolerate nulls
    );
  });

  test('fullText prefers bigText and keeps subText', () {
    const CaptureRawEvent e = CaptureRawEvent(
      pkg: _phonepe,
      title: 'Paid',
      text: 'short',
      bigText: '\u20b999.50 paid to zepto via PhonePe',
      subText: 'UPI',
      ts: 42,
    );
    expect(
      e.fullText,
      'Paid\n\u20b999.50 paid to zepto via PhonePe\nUPI',
    );
    const CaptureRawEvent textOnly = CaptureRawEvent(
      pkg: _phonepe,
      title: '',
      text: 'body',
      bigText: '',
      subText: '',
      ts: 42,
    );
    expect(textOnly.fullText, 'body');
  });

  test('replay ingests, dedups, drops — then acks the max ts', () async {
    bridge.walValue.addAll(<CaptureRawEvent>[
      event(
        pkg: _gpay,
        text: '\u20b9148 sent to Swiggy',
        offsetMs: 1000,
      ),
      event(
        pkg: _gpay, // exact duplicate -> dedup absorbs (at-least-once)
        text: '\u20b9148 sent to Swiggy',
        offsetMs: 1000,
      ),
      event(
        pkg: _phonepe,
        text: '\u20b925 paid to CHAI WALA using PhonePe',
        offsetMs: 2000,
      ),
      event(
        pkg: _gpay, // OTP noise -> drop, but ack must still pass it
        text: '123456 is your One Time Password (OTP). Valid for 5 minutes.',
        offsetMs: 3000,
      ),
    ]);

    final Result<int> result =
        await replayWal(bridge: bridge, pipeline: pipeline);

    expect(result.valueOrNull, 4, reason: 'all four entries were handled');
    expect(
      bridge.ackedUpTo,
      base.millisecondsSinceEpoch + 3000,
      reason: 'ack advances past drops and duplicates',
    );

    final Result<int> txns = await TxnDao(db.db).count();
    expect(txns.valueOrNull, 2, reason: 'duplicate was absorbed by dedup');

    final KvDao kv = KvDao(db.db);
    expect((await kv.get('cap_txn')).valueOrNull, '2');
    expect((await kv.get('cap_dup')).valueOrNull, '1');
    expect((await kv.get('cap_drop_otp_security')).valueOrNull, '1');
    expect(
      (await kv.get('cat_unknown')).valueOrNull,
      '1',
      reason: 'CHAI WALA is not in the alias map',
    );
  });

  test('replay of an EMPTY wal acks nothing', () async {
    final Result<int> result =
        await replayWal(bridge: bridge, pipeline: pipeline);
    expect(result.valueOrNull, 0);
    expect(bridge.ackedUpTo, isNull);
  });

  test('replay failure propagates when the WAL cannot be read', () async {
    bridge.failReadWAL = true;
    final Result<int> result =
        await replayWal(bridge: bridge, pipeline: pipeline);
    expect(result, isA<Err<int>>());
    expect(bridge.ackedUpTo, isNull, reason: 'nothing acked on read failure');
  });
}
