// phase-04
// The Dart leg of the SMS contract: every corpus bank-SMS sample,
// wrapped as a WAL-shaped CaptureRawEvent (`pkg = sms:<SENDER>`),
// flows through the REAL pipeline (real DB, filters, parsers, dedup)
// — exactly what UdaoSmsReceiver + WAL replay produce on device.
// Asserts: sender decoding, txn labelling (TxnSource.sms — never
// notification), drops never write (OTPs/promos), and no raw OTP
// text anywhere in the ledger.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/repos/capture_pipeline_result.dart';
import 'package:udao/data/repos/ledger_repo.dart';
import 'package:udao/features/capture/bridge/capture_raw_event.dart';
import 'package:udao/features/capture/pipeline/capture_pipeline.dart';
import 'package:udao/features/capture/pipeline/ledger_events.dart';

import '../../data/db/test_db.dart';

void main() {
  final Map<String, Object?> corpus =
      jsonDecode(File('test/fixtures/corpus_sms.json').readAsStringSync())
          as Map<String, Object?>;
  final List<Map<String, Object?>> samples =
      (corpus['samples']! as List<dynamic>).cast<Map<String, Object?>>();

  late UdaoDatabase db;
  late CapturePipeline pipeline;
  late TxnDao txnDao;

  setUp(() async {
    db = await createTestDb();
    final LedgerEvents events = LedgerEvents();
    txnDao = TxnDao(db.db);
    pipeline = CapturePipeline(
      repo: LedgerRepo(db),
      txnDao: txnDao,
      kvDao: KvDao(db.db),
      events: events,
    );
    addTearDown(events.dispose);
  });

  tearDown(() async {
    await disposeTestDb(db);
  });

  CaptureRawEvent smsEvent(Map<String, Object?> sample) {
    final String? sender = sample['sender'] as String?;
    return CaptureRawEvent(
      pkg: sender == null ? 'sms:' : 'sms:$sender',
      title: '',
      text: sample['text']! as String,
      bigText: '',
      subText: '',
      // corpus receivedAtIso: 2026-10-27T18:45:03+05:30
      ts: 1730049303000,
    );
  }

  test('raw event sender decodes from the sms: pkg prefix (and only there)',
      () {
    const CaptureRawEvent sms = CaptureRawEvent(
      pkg: 'sms:VM-HDFCBK',
      title: '',
      text: 'Rs.148 debited from A/c No. XX1234',
      bigText: '',
      subText: '',
      ts: 1730000000000,
    );
    const CaptureRawEvent notif = CaptureRawEvent(
      pkg: 'com.phonepe.app',
      title: '',
      text: 'paid',
      bigText: '',
      subText: '',
      ts: 1730000000000,
    );
    const CaptureRawEvent bare = CaptureRawEvent(
      pkg: 'sms:',
      title: '',
      text: 'x',
      bigText: '',
      subText: '',
      ts: 1730000000000,
    );
    expect(sms.sender, 'VM-HDFCBK');
    expect(notif.sender, isNull);
    expect(bare.sender, isNull);
  });

  test('the native WAL line round-trips into the pipeline input', () {
    // The exact JSON UdaoSmsReceiver/SmsGate writes natively.
    const String line =
        '{"pkg":"sms:VM-HDFCBK","title":null,"text":"Rs.148 debited",'
        '"bigText":null,"subText":null,"ts":1730000000000}';
    final CaptureRawEvent? raw = CaptureRawEvent.fromLine(line);
    expect(raw, isNotNull);
    expect(raw!.sender, 'VM-HDFCBK');
    expect(raw.text, 'Rs.148 debited');
    expect(raw.title, '');
  });

  test('full corpus through the pipeline: ${samples.length} sms events',
      () async {
    int landed = 0;
    int drops = 0;
    final Set<String> otpBodies = <String>{};

    for (final Map<String, Object?> s in samples) {
      final Map<String, Object?> e = s['expect']! as Map<String, Object?>;
      final Result<IngestOutcome> outcome =
          await pipeline.run(smsEvent(s));

      switch (e['class']! as String) {
        case 'drop':
          drops++;
          expect(
            outcome,
            isA<Err<IngestOutcome>>(),
            reason: 'sample ${s['id']} must drop (${e['dropReason']})',
          );
          if (e['dropReason'] == 'otp_security') {
            otpBodies.add(s['text']! as String);
          }
        case 'auto':
        case 'pending':
          landed++;
          expect(
            outcome,
            isA<Ok<IngestOutcome>>(),
            reason: 'sample ${s['id']} must land (auto/pending/dup)',
          );
      }
    }

    expect(samples.length, 185);
    expect(drops, 16);
    expect(landed, 169);

    // Everything stored is labelled SMS — the pipeline nulls
    // packageKey for sms:* events, so TxnSource lands on sms.
    final Database rawDb = await db.db;
    final List<Map<String, Object?>> rows =
        await rawDb.rawQuery('SELECT source, raw_text FROM txn');
    expect(rows, isNotEmpty);
    for (final Map<String, Object?> row in rows) {
      expect(
        row['source'],
        'sms',
        reason: 'sms corpus must never label txns notification',
      );
    }

    // OTP text never reaches storage.
    for (final Map<String, Object?> row in rows) {
      for (final String otp in otpBodies) {
        expect(row['raw_text'] as String, isNot(contains(otp)));
      }
    }
  });

  test('replay of the whole corpus is absorbed (at-least-once WAL)', () async {
    for (final Map<String, Object?> s in samples) {
      await pipeline.run(smsEvent(s));
    }
    final Result<int> first = await txnDao.count();
    for (final Map<String, Object?> s in samples) {
      await pipeline.run(smsEvent(s));
    }
    final Result<int> second = await txnDao.count();
    expect(
      second.valueOrNull,
      first.valueOrNull,
      reason: 'WAL replay must not double-count',
    );
  });
}
