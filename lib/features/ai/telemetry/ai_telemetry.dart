// phase-06
// Local AI telemetry (debug + transparency): estimated tokens,
// latency, tool-call outcomes, guardrail blocks, model loads. All
// counters live in kv; NOTHING here ever stores message content
// (privacy law — counts and durations only).
import 'dart:async';
import 'dart:convert';

import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';
import '../../../data/db/dao/kv_dao.dart';
import '../runtime/llm_events.dart';

class AiTelemetrySnapshot {
  const AiTelemetrySnapshot({
    required this.estimatedTokens,
    required this.generations,
    required this.avgLatencyMs,
    required this.toolCallsOk,
    required this.toolCallsFailed,
    required this.guardrailBlocks,
    required this.modelLoads,
    required this.modelLoadFailures,
  });

  final int estimatedTokens;
  final int generations;
  final int avgLatencyMs;
  final int toolCallsOk;
  final int toolCallsFailed;
  final int guardrailBlocks;
  final int modelLoads;
  final int modelLoadFailures;

  static const AiTelemetrySnapshot empty = AiTelemetrySnapshot(
    estimatedTokens: 0,
    generations: 0,
    avgLatencyMs: 0,
    toolCallsOk: 0,
    toolCallsFailed: 0,
    guardrailBlocks: 0,
    modelLoads: 0,
    modelLoadFailures: 0,
  );

  /// Value object — snapshots are compared (tests, settings diffing).
  @override
  bool operator ==(Object other) =>
      other is AiTelemetrySnapshot &&
      other.estimatedTokens == estimatedTokens &&
      other.generations == generations &&
      other.avgLatencyMs == avgLatencyMs &&
      other.toolCallsOk == toolCallsOk &&
      other.toolCallsFailed == toolCallsFailed &&
      other.guardrailBlocks == guardrailBlocks &&
      other.modelLoads == modelLoads &&
      other.modelLoadFailures == modelLoadFailures;

  @override
  int get hashCode => Object.hash(
        estimatedTokens,
        generations,
        avgLatencyMs,
        toolCallsOk,
        toolCallsFailed,
        guardrailBlocks,
        modelLoads,
        modelLoadFailures,
      );

  @override
  String toString() =>
      'AiTelemetrySnapshot(tokens=$estimatedTokens, gens=$generations, '
      'avgMs=$avgLatencyMs, toolOk=$toolCallsOk, toolFail=$toolCallsFailed, '
      'blocks=$guardrailBlocks, loads=$modelLoads, loadFails='
      '$modelLoadFailures)';
}

class AiTelemetry {
  AiTelemetry({required KvDao kv}) : _kv = kv;

  final KvDao _kv;

  static const String kvCounters = 'ai.telemetry.counters';

  Map<String, Object?> _emptyCounters() => <String, Object?>{
        'tokens': 0,
        'generations': 0,
        'latencyMs': 0,
        'toolOk': 0,
        'toolFail': 0,
        'blocks': 0,
        'loads': 0,
        'loadFails': 0,
      };

  Future<Map<String, Object?>> _read() async {
    final Result<String?> raw = await _kv.get(kvCounters);
    final String? json = raw.valueOrNull;
    if (json == null || json.isEmpty) {
      return _emptyCounters();
    }
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
    } on FormatException {
      // fall through to empty
    }
    return _emptyCounters();
  }

  Future<void> _write(Map<String, Object?> counters) async {
    await _kv.set(kvCounters, jsonEncode(counters));
  }

  /// [failure] null = success.
  Future<void> recordGeneration(Failure? failure, {LlmUsage? usage}) async {
    final Map<String, Object?> counters = await _read();
    if (failure == null) {
      counters['generations'] = ((counters['generations'] ?? 0) as int) + 1;
      counters['tokens'] = ((counters['tokens'] ?? 0) as int) +
          (usage?.estimatedTokens ?? 0);
      counters['latencyMs'] = ((counters['latencyMs'] ?? 0) as int) +
          (usage?.elapsedMs ?? 0);
    }
    await _write(counters);
  }

  Future<void> recordToolCall(bool ok) async {
    final Map<String, Object?> counters = await _read();
    counters[ok ? 'toolOk' : 'toolFail'] =
        ((counters[ok ? 'toolOk' : 'toolFail'] ?? 0) as int) + 1;
    await _write(counters);
  }

  Future<void> recordGuardrailBlock() async {
    final Map<String, Object?> counters = await _read();
    counters['blocks'] = ((counters['blocks'] ?? 0) as int) + 1;
    await _write(counters);
  }

  Future<void> recordModelLoad({required bool ok}) async {
    final Map<String, Object?> counters = await _read();
    counters[ok ? 'loads' : 'loadFails'] =
        ((counters[ok ? 'loads' : 'loadFails'] ?? 0) as int) + 1;
    await _write(counters);
  }

  Future<AiTelemetrySnapshot> snapshot() async {
    final Map<String, Object?> counters = await _read();
    final int generations = (counters['generations'] ?? 0) as int;
    final int totalLatency = (counters['latencyMs'] ?? 0) as int;
    return AiTelemetrySnapshot(
      estimatedTokens: (counters['tokens'] ?? 0) as int,
      generations: generations,
      avgLatencyMs:
          generations == 0 ? 0 : (totalLatency / generations).round(),
      toolCallsOk: (counters['toolOk'] ?? 0) as int,
      toolCallsFailed: (counters['toolFail'] ?? 0) as int,
      guardrailBlocks: (counters['blocks'] ?? 0) as int,
      modelLoads: (counters['loads'] ?? 0) as int,
      modelLoadFailures: (counters['loadFails'] ?? 0) as int,
    );
  }
}
