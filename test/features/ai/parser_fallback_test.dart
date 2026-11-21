// phase-06
// LlmFallbackParser (strict JSON, floor 0.65, honest errors) +
// FallbackParseService (pending stays pending, learned-pattern
// proposal) + LearnedPatternStore (approve/dismiss round-trip).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/pending_review_entry.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/db/dao/pending_review_dao.dart';
import 'package:udao/data/repos/pending_review_repo.dart';
import 'package:udao/features/ai/parser_fallback/learned_pattern.dart';
import 'package:udao/features/ai/parser_fallback/llm_parser.dart';
import 'package:udao/features/ai/runtime/llm_events.dart';

import '../../data/db/test_db.dart' as helper;
import 'fake_llm_runtime.dart';

void main() {
  group('LlmFallbackParser', () {
    test('model absent → honest model-absent, no generate call',
        () async {
      final ScriptedRuntime rt = ScriptedRuntime(const <List<LlmEvent>>[])
        ..loaded = false;
      final LlmFallbackParser p = LlmFallbackParser(runtime: rt);
      final Result<LlmParseResult> r =
          await p.parse('Rs.99 debited somewhere');
      expect(r.failureOrNull!.message, 'model-absent');
      expect(rt.calls, 0);
      rt.dispose();
    });

    test('valid JSON above the floor parses', () async {
      final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
        <LlmEvent>[
          const LlmToken('{"direction":"debit","amount":289.50,'
              '"merchant":"Swiggy","refNo":"372045678901","confidence":0.9}'),
          const LlmDone(
              LlmUsage(promptChars: 10, outputChars: 60, elapsedMs: 40,
              ),
              ),
        ],
      ])
        ..loaded = true;
      final LlmFallbackParser p = LlmFallbackParser(runtime: rt);
      final Result<LlmParseResult> r =
          await p.parse('UPI/372045678901/Payment to Swiggy/Rs.289.50');
      final LlmParseResult v = r.valueOrNull!;
      expect(v.direction, TxnDirection.debit);
      expect(v.amount, Money.fromRupees(289, paise: 50));
      expect(v.merchant, 'Swiggy');
      expect(v.refNo, '372045678901');
      expect(v.confidence, 0.9);
      // Parser runs cold: deterministic sampling + parser tag.
      expect(rt.requests.single.temperature, lessThan(0.3));
      expect(rt.requests.single.templateTag, 'parser');
      rt.dispose();
    });

    test('prose around the JSON is tolerated (first object wins)',
        () async {
      final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
        <LlmEvent>[
          const LlmToken('Sure! Here is the parse:\n'
              '{"direction":"credit","amount":12000.00,'
              '"merchant":"NEFT-SALARY INFOTECH","confidence":0.95}\n'
              'Hope that helps.'),
          const LlmDone(
              LlmUsage(promptChars: 10, outputChars: 60, elapsedMs: 30,
              ),
              ),
        ],
      ])
        ..loaded = true;
      final Result<LlmParseResult> r =
          await LlmFallbackParser(runtime: rt).parse('credited Rs.12000');
      expect(r.valueOrNull!.merchant, 'NEFT-SALARY INFOTECH');
      rt.dispose();
    });

    test('below the floor → ai-low-confidence (stays pending)',
        () async {
      final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
        <LlmEvent>[
          const LlmToken('{"direction":"debit","amount":99,'
              '"merchant":"??","confidence":0.4}'),
          const LlmDone(
              LlmUsage(promptChars: 5, outputChars: 30, elapsedMs: 10,
              ),
              ),
        ],
      ])
        ..loaded = true;
      final Result<LlmParseResult> r =
          await LlmFallbackParser(runtime: rt).parse('some odd sms');
      expect(r.failureOrNull!.message, 'ai-low-confidence');
      rt.dispose();
    });

    test('floor is exactly 0.65', () {
      expect(LlmFallbackParser.confidenceFloor, 0.65);
    });

    test('non-JSON output → ai-invalid-output', () async {
      final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
        <LlmEvent>[
          const LlmToken('I cannot parse this message, sorry.'),
          const LlmDone(
              LlmUsage(promptChars: 5, outputChars: 30, elapsedMs: 10,
              ),
              ),
        ],
      ])
        ..loaded = true;
      final Result<LlmParseResult> r =
          await LlmFallbackParser(runtime: rt).parse('weird');
      expect(r.failureOrNull!.message, 'ai-invalid-output');
      rt.dispose();
    });

    test('runtime error propagates', () async {
      final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
        <LlmEvent>[const LlmError(ModelFailure('ai-oom'))],
      ])
        ..loaded = true;
      final Result<LlmParseResult> r =
          await LlmFallbackParser(runtime: rt).parse('x');
      expect(r.failureOrNull!.message, 'ai-oom');
      rt.dispose();
    });

    test('five few-shots, all valid JSON targets', () {
      expect(LlmFallbackParser.fewShots, hasLength(5));
      for (final String shot in LlmFallbackParser.fewShots) {
        expect(shot, contains('{"direction":'));
        expect(shot, contains('"confidence":'));
      }
    });
  });

  group('LearnedPattern', () {
    test('escapeLiteral neutralises metacharacters', () {
      expect(LearnedPattern.escapeLiteral('a.b*c'), r'a\.b\*c');
      expect(LearnedPattern.escapeLiteral('(Rs.99)'), r'\(Rs\.99\)');
    });

    test('build turns literals into typed groups', () {
      const String sample = 'Rs.450.00 debited from HDFC Ref 506711234';
      final String pattern = LearnedPattern.build(
        sample: sample,
        amount: '450.00',
        merchant: 'HDFC',
        refNo: '506711234',
      );
      expect(pattern, contains('(?<amount>'));
      expect(pattern, contains('(?<merchant>'));
      expect(pattern, contains('(?<ref>'));
      // Compiles and matches its own sample.
      expect(LearnedPattern.testPattern(pattern, sample), isTrue);
      // And a structurally similar new message.
      expect(
        LearnedPattern.testPattern(
          pattern,
          'Rs.120.50 debited from ICIC Ref 998877665544',
        ),
        isTrue,
      );
    });

    test('testPattern rejects a broken regex honestly', () {
      expect(LearnedPattern.testPattern('(unclosed', 'sample'), isFalse);
    });
  });

  group('store + service (real DB)', () {
    late UdaoDatabase db;
    late KvDao kv;
    late PendingReviewRepo reviews;
    late LearnedPatternStore patterns;
    final DateTime now = DateTime(2026, 10, 30, 12);

    setUp(() async {
      db = await helper.createTestDb();
      kv = KvDao(db.db);
      reviews = PendingReviewRepo(db);
      patterns = LearnedPatternStore(kv: kv);
    });
    tearDown(() async {
      await helper.disposeTestDb(db);
    });

    test('propose → all() shows unapproved; approve flips it',
        () async {
      final Result<LearnedPatternEntry> p = await patterns.propose(
        pattern: r'^.*Rs\.\d+.*$',
        sample: 'Rs.99 debited',
        now: now,
      );
      final LearnedPatternEntry entry = p.valueOrNull!;
      expect(entry.approved, isFalse);

      final List<LearnedPatternEntry> list =
          (await patterns.all()).valueOrNull!;
      expect(list, hasLength(1));

      await patterns.approve(entry.id);
      final List<LearnedPatternEntry> approved =
          (await patterns.all()).valueOrNull!;
      expect(approved.single.approved, isTrue);

      // kv persistence is plain JSON (a LIST of entries).
      final String? raw =
          (await kv.get(LearnedPattern.kvStore)).valueOrNull;
      expect(raw, isNotNull);
      final List<Object?> stored = jsonDecode(raw!) as List<Object?>;
      expect(stored, hasLength(1));
      expect((stored.single as Map<String, Object?>)['approved'], true);
    });

    test('dismiss removes the proposal', () async {
      final Result<LearnedPatternEntry> p = await patterns.propose(
        pattern: r'^x$',
        sample: 'x',
        now: now,
      );
      await patterns.dismiss(p.valueOrNull!.id);
      expect((await patterns.all()).valueOrNull, isEmpty);
    });

    test('tryEntry updates the pending row and proposes a pattern',
        () async {
      final PendingReviewEntry entry = PendingReviewEntry(
        id: 'pr-1',
        source: 'sms',
        receivedAt: now,
        rawText: 'Rs.450.00 debited from HDFC Ref 506711234',
        confidence: 0.2,
      );
      final Result<void> added =
          await PendingReviewDao(db.db).insert(entry);
      expect(added.isOk, isTrue);

      final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
        <LlmEvent>[
          const LlmToken('{"direction":"debit","amount":450.00,'
              '"merchant":"HDFC","refNo":"506711234","confidence":0.92}'),
          const LlmDone(
              LlmUsage(promptChars: 10, outputChars: 60, elapsedMs: 35,
              ),
              ),
        ],
      ])
        ..loaded = true;
      final FallbackParseService service = FallbackParseService(
        parser: LlmFallbackParser(runtime: rt),
        reviews: reviews,
        patterns: patterns,
      );

      final Result<LlmParseResult> r =
          await service.tryEntry(entry, now: now);
      expect(r.valueOrNull!.merchant, 'HDFC');

      // The pending row now carries the model's read...
      final List<PendingReviewEntry> pending =
          (await reviews.pending(limit: 10)).valueOrNull!;
      expect(pending, isNotEmpty);
      expect(pending.first.amount, isNotNull);
      expect(pending.first.merchantClean, 'HDFC');
      expect(pending.first.parserId, 'llm-fallback');
      expect(
        pending.first.resolution,
        isNull,
        reason: 'STILL pending — a human approves',
      );

      // ...and a learned-regex proposal exists for Settings.
      final List<LearnedPatternEntry> proposals =
          (await patterns.all()).valueOrNull!;
      expect(proposals, hasLength(1));
      expect(proposals.single.approved, isFalse);
      rt.dispose();
    });
  });
}
