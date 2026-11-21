// phase-02
// The golden corpus run: 250 real-format notifications + SMSes
// (see `test/fixtures/README.md`), asserted field-by-field. The
// printed accuracy table is the phase-02 acceptance evidence —
// every field must clear 95%.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/data/parsers/filters.dart';
import 'package:udao/data/parsers/parser_registry.dart';
import 'package:udao/data/parsers/parser_types.dart';

const double kMinFieldAccuracy = 0.95;

class _Sample {
  _Sample(Map<String, Object?> json)
      : id = json['id']! as String,
        packageKey = json['packageKey'] as String?,
        sender = json['sender'] as String?,
        text = json['text']! as String,
        expect = (json['expect']! as Map<String, Object?>).cast<String, Object?>();
  final String id;
  final String? packageKey;
  final String? sender;
  final String text;
  final Map<String, Object?> expect;
}

void main() {
  final OtpFilter otpFilter = OtpFilter();
  final PromoFilter promoFilter = PromoFilter();

  final List<_Sample> all = <_Sample>[];
  for (final String name
      in <String>['corpus_notifications.json', 'corpus_sms.json']) {
    final Map<String, Object?> payload =
        (jsonDecode(File('test/fixtures/$name').readAsStringSync())
                as Map<String, Object?>)
            .cast<String, Object?>();
    final DateTime receivedAt = DateTime.parse(payload['receivedAtIso']! as String);
    for (final Map<String, Object?> raw
        in (payload['samples']! as List<Object?>).cast<Map<String, Object?>>()) {
      final _Sample s = _Sample(raw);
      all.add(s);
      _receivedById[s.id] = receivedAt;
    }
  }
  assert(all.length == 250, 'corpus must hold 250 samples');

  test('golden corpus: field accuracy >= 95% (250 samples)', () {
    final Map<String, int> pass = <String, int>{};
    final Map<String, int> total = <String, int>{};
    final List<String> failures = <String>[];

    void tally(String field, bool ok) {
      total[field] = (total[field] ?? 0) + 1;
      if (ok) {
        pass[field] = (pass[field] ?? 0) + 1;
      }
    }

    for (final _Sample s in all) {
      final ParserInput input = ParserInput(
        text: s.text,
        receivedAt: _receivedById[s.id]!,
        packageKey: s.packageKey,
        sender: s.sender,
      );
      final Map<String, Object?> want = s.expect;
      final String wantClass = want['class']! as String;

      // ---- run the exact LedgerRepo routing -----------------------
      String gotClass;
      String? gotDropReason;
      Result<ParsedTxn>? parsed;
      final String? otpReason = otpFilter.check(input).dropReason;
      final String? promoReason =
          otpReason == null ? promoFilter.check(input).dropReason : null;
      if (otpReason != null || promoReason != null) {
        gotClass = 'drop';
        gotDropReason = otpReason ?? promoReason;
      } else {
        parsed = runParserChain(input);
        if (parsed is Err<ParsedTxn>) {
          gotClass = 'drop';
          gotDropReason = parsed.failure.message;
        } else {
          final double conf = parsed.valueOrNull!.confidence;
          if (conf < ConfidencePolicy.reviewMin) {
            gotClass = 'drop';
            gotDropReason = 'low_confidence';
          } else {
            gotClass = conf >= ConfidencePolicy.autoAcceptMin ? 'auto' : 'pending';
          }
        }
      }

      tally('class', gotClass == wantClass);
      if (gotClass != wantClass) {
        failures.add('[${s.id}] class want=$wantClass got=$gotClass :: ${s.text}');
      }

      if (wantClass == 'drop') {
        tally(
          'dropReason',
          gotClass == 'drop' && gotDropReason == want['dropReason'],
        );
        continue;
      }

      final ParsedTxn? got = parsed?.valueOrNull;
      if (got == null) {
        for (final String f in <String>[
          'parserId',
          'amountPaise',
          'direction',
          'merchantClean',
          'confidenceMin',
          'occurredAtIsoDate',
        ]) {
          if (want.containsKey(f)) {
            tally(f, false);
          }
        }
        continue;
      }

      tally('parserId', got.parserId == want['parserId']);
      tally('amountPaise', got.amount.paise == want['amountPaise']);
      tally(
        'direction',
        got.direction.name == want['direction'],
      );
      tally('merchantClean', got.merchantClean == want['merchantClean']);
      tally(
        'confidenceMin',
        got.confidence >= (want['confidenceMin']! as num).toDouble(),
      );
      tally(
        'occurredAtIsoDate',
        IstDates.isoDate(got.occurredAt) == want['occurredAtIsoDate'],
      );
      if (want['hasVpa'] == true) {
        tally('hasVpa', got.vpa != null);
      }
      if (want['hasRef'] == true) {
        tally('hasRef', got.refNo != null);
      }
    }

    // ---- report ---------------------------------------------------
    final List<String> rows = <String>[];
    for (final String field in total.keys) {
      final int p = pass[field] ?? 0;
      final int n = total[field]!;
      final double pct = p / n;
      rows.add(
        '  $field'.padRight(20) +
            '$p/$n'.padLeft(9) +
            '  ${(pct * 100).toStringAsFixed(1)}%'.padLeft(7),
      );
      expect(
        pct,
        greaterThanOrEqualTo(kMinFieldAccuracy),
        reason: 'field $field below 95%:\n${failures.take(12).join('\n')}',
      );
    }
    // ignore: avoid_print
    print('── golden corpus accuracy (${all.length} samples) ──');
    // ignore: avoid_print
    rows.forEach(print);
    if (failures.isNotEmpty) {
      // ignore: avoid_print
      print('first failures:');
      // ignore: avoid_print
      failures.take(12).forEach(print);
    }
  });
}

final Map<String, DateTime> _receivedById = <String, DateTime>{};
