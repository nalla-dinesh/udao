// phase-06
// AiTelemetry: counters persist in kv, snapshot math, zero content.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/features/ai/runtime/llm_events.dart';
import 'package:udao/features/ai/telemetry/ai_telemetry.dart';

import '../../data/db/test_db.dart' as helper;

void main() {
  late UdaoDatabase db;
  late AiTelemetry t;

  setUp(() async {
    db = await helper.createTestDb();
    t = AiTelemetry(kv: KvDao(db.db));
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  test('empty snapshot is all zeros', () async {
    final AiTelemetrySnapshot s = await t.snapshot();
    expect(s, AiTelemetrySnapshot.empty);
  });

  test('generation counters: tokens + latency accumulate', () async {
    await t.recordGeneration(
      null,
      usage: const LlmUsage(
        promptChars: 400, outputChars: 100, elapsedMs: 1200,
      ),
    );
    await t.recordGeneration(
      null,
      usage: const LlmUsage(
        promptChars: 400, outputChars: 100, elapsedMs: 800,
      ),
    );
    final AiTelemetrySnapshot s = await t.snapshot();
    expect(s.generations, 2);
    expect(s.estimatedTokens, 250, reason: '(400+100)*2 / 4');
    expect(s.avgLatencyMs, 1000);
  });

  test('failed generations count but add no usage', () async {
    const LlmUsage u =
        LlmUsage(promptChars: 100, outputChars: 0, elapsedMs: 50);
    await t.recordGeneration(null, usage: u);
    await t.recordGeneration(const ModelFailure('ai-oom'));
    final AiTelemetrySnapshot s = await t.snapshot();
    expect(s.generations, 1);
    expect(s.estimatedTokens, 25);
  });

  test('tool calls split ok/failed', () async {
    await t.recordToolCall(true);
    await t.recordToolCall(true);
    await t.recordToolCall(false);
    final AiTelemetrySnapshot s = await t.snapshot();
    expect(s.toolCallsOk, 2);
    expect(s.toolCallsFailed, 1);
  });

  test('guardrail blocks + model loads tracked', () async {
    await t.recordGuardrailBlock();
    await t.recordModelLoad(ok: true);
    await t.recordModelLoad(ok: false);
    final AiTelemetrySnapshot s = await t.snapshot();
    expect(s.guardrailBlocks, 1);
    expect(s.modelLoads, 1);
    expect(s.modelLoadFailures, 1);
  });

  test('persisted kv carries counters only — never content', () async {
    await t.recordGeneration(
      null,
      usage: const LlmUsage(
        promptChars: 40, outputChars: 0, elapsedMs: 10,
      ),
    );
    await t.recordGuardrailBlock();
    final String? raw =
        (await KvDao(db.db).get(AiTelemetry.kvCounters)).valueOrNull;
    expect(raw, isNotNull);
    final Map<String, Object?> decoded =
        jsonDecode(raw!) as Map<String, Object?>;
    expect(decoded.keys, everyElement(matches(r'^[a-zA-Z]+$')));
    expect(raw, isNot(contains('prompt')));
    expect(raw, isNot(contains('user')));
  });
}

