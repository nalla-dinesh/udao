// phase-06
// Scripted LlmRuntime: emits a queue of sealed LlmEvents with NO
// timers (immediate microtask events — the binding invariants demand
// timer-free statics).
import 'dart:async';

import 'package:udao/core/errors/failure.dart';
import 'package:udao/features/ai/runtime/llm_events.dart';
import 'package:udao/features/ai/runtime/llm_runtime.dart';

class ScriptedRuntime implements LlmRuntime {
  ScriptedRuntime(this._batches);

  /// One entry per generate() call: the events to emit.
  final List<List<LlmEvent>> _batches;

  int calls = 0;
  final List<String> prompts = <String>[];
  final List<LlmRequest> requests = <LlmRequest>[];
  int cancelCalls = 0;

  /// What isLoaded reports (the interface exposes a bool getter).
  /// Defaults to FALSE: a scripted runtime has no model file behind
  /// it, so gates like RoastEngine's variation pass stay closed
  /// unless a test explicitly loads one.
  bool loaded = false;

  @override
  String? get modelName => 'scripted';

  @override
  bool get isLoaded => loaded;

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Stream<LlmEvent> generate(LlmRequest request) {
    prompts.add(request.prompt);
    requests.add(request);
    final int index = calls;
    calls++;
    final List<LlmEvent> batch = index < _batches.length
        ? _batches[index]
        : <LlmEvent>[const LlmError(ModelFailure('model-absent'))];
    // One stream PER generate() call, closed after the batch: a
    // shared never-closing broadcast stream hangs every `await for`
    // (the 30s-timeout errata). Closing is what makes the loop end.
    final StreamController<LlmEvent> call =
        StreamController<LlmEvent>();
    scheduleMicrotask(() {
      for (final LlmEvent event in batch) {
        call.add(event);
      }
      call.close();
    });
    return call.stream;
  }

  /// Kept for test symmetry — per-call controllers close themselves.
  void dispose() {}
}
