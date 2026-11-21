// phase-06
// Test doubles for the AI stack. Laws applied (phase-04/05 lessons):
//   * NO Future.delayed in statics — Completer-based never-futures
//     only (a pending FakeTimer fails the binding invariants).
//   * Fakes deliver synchronously where the real thing streams.
import 'dart:async';

import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/features/ai/runtime/ai_engine.dart';

/// Scriptable engine: tests queue the event batches each session
/// should emit.
class FakeAiInferenceEngine implements AiInferenceEngine {
  FakeAiInferenceEngine({this.loaded = false});

  bool loaded;

  final List<int> createdSessions = <int>[];
  final List<String> loadedPaths = <String>[];
  int unloadCalls = 0;
  int cancelCalls = 0;
  final Map<int, String> promptsBySession = <int, String>{};

  /// sessionId -> list of event batches to emit on generate().
  final Map<int, List<AiEngineEvent>> script = <int, List<AiEngineEvent>>{};

  /// Next session id handed out.
  int _nextId = 1;

  final StreamController<AiEngineEvent> _events =
      StreamController<AiEngineEvent>.broadcast();

  void emit(AiEngineEvent event) => _events.add(event);

  @override
  Stream<AiEngineEvent> get events => _events.stream;

  @override
  Future<Result<bool>> loadModel({
    required String path,
    int maxTokens = 1024,
    int maxImages = 0,
  }) async {
    loadedPaths.add(path);
    loaded = true;
    return const Ok<bool>(true);
  }

  @override
  Future<Result<bool>> unload() async {
    unloadCalls++;
    loaded = false;
    return const Ok<bool>(true);
  }

  @override
  Future<Result<bool>> isLoaded() async => Ok<bool>(loaded);

  @override
  Future<Result<int>> createSession({
    double temperature = 0.8,
    int topK = 40,
  }) async {
    final int id = _nextId++;
    createdSessions.add(id);
    return Ok<int>(id);
  }

  @override
  Future<Result<bool>> closeSession(int sessionId) async => const Ok<bool>(true);

  @override
  Future<Result<bool>> generate({
    required int sessionId,
    required String prompt,
  }) async {
    promptsBySession[sessionId] = prompt;
    final List<AiEngineEvent>? batch = script[sessionId];
    if (batch != null) {
      scheduleMicrotask(() {
        for (final AiEngineEvent event in batch) {
          emit(event);
        }
      });
    }
    return const Ok<bool>(true);
  }

  @override
  Future<Result<bool>> generateVision({
    required int sessionId,
    required String prompt,
    required String imagePath,
  }) async =>
      generate(sessionId: sessionId, prompt: prompt);

  @override
  Future<Result<bool>> cancelGenerate(int sessionId) async {
    cancelCalls++;
    return const Ok<bool>(true);
  }

  void dispose() => _events.close();
}

/// A never-completing future with ZERO timers (errata-2 lesson).
final Future<Never> neverFuture = Completer<Never>().future;

/// Engine whose channel is simply absent (widget tests / old hosts).
class AbsentAiInferenceEngine implements AiInferenceEngine {
  @override
  Stream<AiEngineEvent> get events => const Stream<AiEngineEvent>.empty();

  @override
  Future<Result<bool>> loadModel({
    required String path,
    int maxTokens = 1024,
    int maxImages = 0,
  }) async =>
      const Err<bool>(ModelFailure('model-absent'));

  @override
  Future<Result<bool>> unload() async => const Ok<bool>(true);

  @override
  Future<Result<bool>> isLoaded() async => const Ok<bool>(false);

  @override
  Future<Result<int>> createSession({
    double temperature = 0.8,
    int topK = 40,
  }) async =>
      const Err<int>(ModelFailure('ai-not-loaded'));

  @override
  Future<Result<bool>> closeSession(int sessionId) async => const Ok<bool>(true);

  @override
  Future<Result<bool>> generate({
    required int sessionId,
    required String prompt,
  }) async =>
      const Err<bool>(ModelFailure('ai-not-loaded'));

  @override
  Future<Result<bool>> generateVision({
    required int sessionId,
    required String prompt,
    required String imagePath,
  }) async =>
      const Err<bool>(ModelFailure('ai-not-loaded'));

  @override
  Future<Result<bool>> cancelGenerate(int sessionId) async =>
      const Ok<bool>(true);
}
