// phase-06
// The platform-engine seam (Kotlin AiBridge behind 'udao/ai').
// Everything above this file is pure Dart and unit-testable with a
// fake engine; everything below it is one thin adapter.
import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';

/// Typed engine events (the wire maps from AiBridge.kt).
sealed class AiEngineEvent {
  const AiEngineEvent({required this.sessionId});

  final int sessionId;
}

/// Cumulative text so far (the Kotlin side forwards MediaPipe's
/// partial as-is; diffing to deltas is the runtime's job).
class AiEngineToken extends AiEngineEvent {
  const AiEngineToken({required super.sessionId, required this.text});

  final String text;
}

class AiEngineDone extends AiEngineEvent {
  const AiEngineDone({
    required super.sessionId,
    required this.elapsedMs,
    required this.totalChars,
  });

  final int elapsedMs;
  final int totalChars;
}

class AiEngineError extends AiEngineEvent {
  const AiEngineError({
    required super.sessionId,
    required this.code,
    required this.message,
  });

  final String code;
  final String message;
}

/// Contract of the Kotlin side (AiBridge.kt — see its header for the
/// wire contract; static_verify §6p pins the parity).
abstract class AiInferenceEngine {
  Future<Result<bool>> loadModel({
    required String path,
    int maxTokens = 1024,
    int maxImages = 0,
  });

  Future<Result<bool>> unload();

  Future<Result<bool>> isLoaded();

  Future<Result<int>> createSession({double temperature = 0.8, int topK = 40});

  Future<Result<bool>> closeSession(int sessionId);

  Future<Result<bool>> generate({
    required int sessionId,
    required String prompt,
  });

  Future<Result<bool>> generateVision({
    required int sessionId,
    required String prompt,
    required String imagePath,
  });

  Future<Result<bool>> cancelGenerate(int sessionId);

  /// Broadcast, never-pausing event stream (sessionId-tagged).
  Stream<AiEngineEvent> get events;
}

/// Real engine: MethodChannel 'udao/ai' + EventChannel 'udao/ai/stream'.
class PlatformAiInferenceEngine implements AiInferenceEngine {
  const PlatformAiInferenceEngine();

  static const MethodChannel _control = MethodChannel('udao/ai');
  static const EventChannel _stream = EventChannel('udao/ai/stream');

  static Stream<AiEngineEvent>? _cached;

  @override
  Stream<AiEngineEvent> get events {
    return _cached ??= _stream
        .receiveBroadcastStream()
        .map(_parseEvent)
        .where((AiEngineEvent e) => e != _invalid)
        .cast<AiEngineEvent>();
  }

  static const AiEngineEvent _invalid = AiEngineError(
    sessionId: -1,
    code: 'invalid',
    message: '',
  );

  static AiEngineEvent _parseEvent(Object? raw) {
    if (raw is! Map) {
      return _invalid;
    }
    final int sessionId = (raw['sessionId'] as num?)?.toInt() ?? -1;
    final String type = raw['type'] as String? ?? '';
    switch (type) {
      case 'token':
        return AiEngineToken(
          sessionId: sessionId,
          text: raw['text'] as String? ?? '',
        );
      case 'done':
        return AiEngineDone(
          sessionId: sessionId,
          elapsedMs: (raw['elapsedMs'] as num?)?.toInt() ?? 0,
          totalChars: (raw['totalChars'] as num?)?.toInt() ?? 0,
        );
      case 'error':
        return AiEngineError(
          sessionId: sessionId,
          code: raw['code'] as String? ?? 'unknown',
          message: raw['message'] as String? ?? '',
        );
    }
    return _invalid;
  }

  Future<Result<Object?>> _call(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      return Ok<Object?>(await _control.invokeMethod<Object?>(method, args));
    } on PlatformException catch (e) {
      return Err<Object?>(_mapPlatform(e));
    } on MissingPluginException {
      // Widget tests / hosts without the Kotlin side — honest absent.
      return const Err<Object?>(ModelFailure('model-absent'));
    }
  }

  static ModelFailure _mapPlatform(PlatformException e) {
    switch (e.code) {
      case 'UDAO_AI_NOT_LOADED':
        return const ModelFailure('ai-not-loaded');
      case 'UDAO_AI_LOAD_FAILED':
        return const ModelFailure('ai-load-failed');
      case 'UDAO_AI_OOM':
        return const ModelFailure('ai-oom');
      case 'UDAO_AI_BUSY':
        return const ModelFailure('ai-busy');
      case 'UDAO_AI_NO_VISION':
        return const ModelFailure('ai-no-vision');
      case 'UDAO_AI_SESSION_FAILED':
        return const ModelFailure('ai-session-failed');
      case 'UDAO_AI_BAD_ARGS':
        return const ModelFailure('ai-bad-args');
    }
    return ModelFailure('ai-${e.code}');
  }

  @override
  Future<Result<bool>> loadModel({
    required String path,
    int maxTokens = 1024,
    int maxImages = 0,
  }) async {
    final Result<Object?> r = await _call('loadModel', <String, Object?>{
      'path': path,
      'maxTokens': maxTokens,
      'maxImages': maxImages,
    });
    return r.fold(
      (Failure f) => Err<bool>(f),
      (Object? v) => Ok<bool>(v is Map && v['ok'] == true),
    );
  }

  @override
  Future<Result<bool>> unload() async {
    return _bool(await _call('unload'));
  }

  @override
  Future<Result<bool>> isLoaded() async {
    final Result<Object?> r = await _call('isLoaded');
    return r.fold(
      (Failure f) => Err<bool>(f),
      (Object? v) => Ok<bool>(v == true),
    );
  }

  @override
  Future<Result<int>> createSession({
    double temperature = 0.8,
    int topK = 40,
  }) async {
    final Result<Object?> r = await _call(
      'createSession',
      <String, Object?>{'temperature': temperature, 'topK': topK},
    );
    return r.fold(
      (Failure f) => Err<int>(f),
      (Object? v) => v is Map && v['sessionId'] is num
          ? Ok<int>((v['sessionId']! as num).toInt())
          : const Err<int>(ModelFailure('ai-session-failed')),
    );
  }

  @override
  Future<Result<bool>> closeSession(int sessionId) async {
    return _bool(await _call(
      'closeSession',
      <String, Object?>{'sessionId': sessionId},
    ),);
  }

  @override
  Future<Result<bool>> generate({
    required int sessionId,
    required String prompt,
  }) async {
    return _bool(await _call(
      'generate',
      <String, Object?>{
        'sessionId': sessionId,
        'prompt': prompt,
      },
    ),);
  }

  @override
  Future<Result<bool>> generateVision({
    required int sessionId,
    required String prompt,
    required String imagePath,
  }) async {
    return _bool(await _call(
      'generateVision',
      <String, Object?>{
        'sessionId': sessionId,
        'prompt': prompt,
        'imagePath': imagePath,
      },
    ),);
  }

  @override
  Future<Result<bool>> cancelGenerate(int sessionId) async {
    return _bool(await _call(
      'cancelGenerate',
      <String, Object?>{'sessionId': sessionId},
    ),);
  }

  Result<bool> _bool(Result<Object?> r) => r.fold(
        (Failure f) => Err<bool>(f),
        (Object? v) => Ok<bool>(v == true || v == null),
      );
}
