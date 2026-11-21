// phase-06
// Gemma over the MediaPipe Kotlin seam (AiBridge). Responsibilities:
//   * session-per-request lifecycle (create → generate → close),
//   * Gemma turn formatting (system + history + prompt),
//   * cumulative→delta token diffing (MediaPipe partials are the
//     text-so-far; the diff makes the runtime robust either way),
//   * stop-marker trimming + error mapping,
//   * one generation at a time (the engine enforces it too — the
//     shared KV cache cannot serve two concurrent streams),
//   * cancellation even when the engine goes SILENT after cancel
//     (MediaPipe may simply stop calling back — a poller watches the
//     cancelled flag and terminates the stream honestly).
//
// TODO-VERIFY(local): the exact chat-template acceptance of the
// loaded .task file (MediaPipe applies no template of its own; the
// <start_of_turn> scaffolding below is the documented Gemma 2/3 IT
// format) and the vision path against a real gemma-3n model.
import 'dart:async';

import '../../../core/errors/failure.dart';
import '../../../core/log/udao_logger.dart';
import '../../../core/result/result.dart';
import 'ai_engine.dart';
import 'llm_events.dart';
import 'llm_runtime.dart';

class GemmaRuntime implements LlmRuntime {
  GemmaRuntime({required AiInferenceEngine engine})
      : _engine = engine,
        _log = udaoLog.child('ai');

  final AiInferenceEngine _engine;
  final UdaoLogger _log;

  String? _loadedName;
  int? _activeSessionId;
  bool _cancelled = false;

  /// How often the cancel-poller checks the flag (ms).
  static const int _cancelPollMs = 120;

  static const List<String> _stopMarkers = <String>[
    '<end_of_turn>',
    '<end_of_id>',
  ];

  @override
  String? get modelName => _loadedName;

  @override
  bool get isLoaded => _loadedName != null;

  /// Called by [ModelManager] after a successful engine load.
  void onModelLoaded(String name) {
    _loadedName = name;
  }

  /// Called by [ModelManager] on unload.
  void onModelUnloaded() {
    _cancelled = true;
    _loadedName = null;
    _activeSessionId = null;
  }

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> cancel() async {
    _cancelled = true;
    final int? sessionId = _activeSessionId;
    if (sessionId != null) {
      final Result<bool> r = await _engine.cancelGenerate(sessionId);
      if (r.isErr) {
        _log.warn('cancel failed: ${r.failureOrNull}');
      }
    }
  }

  @override
  Stream<LlmEvent> generate(LlmRequest request) {
    _cancelled = false;
    final StreamController<LlmEvent> controller = StreamController<LlmEvent>(
      onCancel: () {
        // Consumer went away — stop the engine too, never leak a
        // generating session.
        _cancelled = true;
      },
    );
    unawaited(_run(request, controller));
    return controller.stream;
  }

  Future<void> _run(
    LlmRequest request,
    StreamController<LlmEvent> controller,
  ) async {
    StreamSubscription<AiEngineEvent>? subscription;
    Timer? poller;
    final Stopwatch watch = Stopwatch()..start();
    String emitted = '';
    bool terminal = false;

    final Result<int> session = await _engine.createSession(
      temperature: request.temperature,
      topK: request.topK,
    );
    if (session.isErr) {
      controller.add(LlmError(_asModelFailure(session.failureOrNull!)));
      await controller.close();
      return;
    }
    final int sessionId = session.valueOrNull!;
    _activeSessionId = sessionId;

    Future<void> cleanup() async {
      terminal = true;
      await subscription?.cancel();
      poller?.cancel();
      if (_activeSessionId == sessionId) {
        _activeSessionId = null;
      }
      unawaited(_engine.closeSession(sessionId));
    }

    final String prompt = _format(request);
    final Result<bool> started = request.imagePath == null
        ? await _engine.generate(sessionId: sessionId, prompt: prompt)
        : await _engine.generateVision(
            sessionId: sessionId,
            prompt: prompt,
            imagePath: request.imagePath!,
          );
    if (started.isErr) {
      controller.add(LlmError(_asModelFailure(started.failureOrNull!)));
      await cleanup();
      await controller.close();
      return;
    }

    void complete(LlmUsage usage) {
      final String trimmed = _trimStops(emitted);
      controller.add(
        LlmDone(
          LlmUsage(
            promptChars: prompt.length,
            outputChars: trimmed.length,
            elapsedMs:
                usage.elapsedMs > 0 ? usage.elapsedMs : watch.elapsedMilliseconds,
            cancelled: usage.cancelled,
          ),
        ),
      );
    }

    subscription = _engine.events.listen((AiEngineEvent event) {
      if (event.sessionId != sessionId || terminal) {
        return;
      }
      switch (event) {
        case AiEngineToken(:final String text):
          if (_cancelled) {
            return;
          }
          if (text.startsWith(emitted) && text.length >= emitted.length) {
            final String delta = text.substring(emitted.length);
            emitted = text;
            if (delta.isNotEmpty) {
              controller.add(LlmToken(delta));
            }
          } else if (text.isNotEmpty) {
            // Non-cumulative engine semantics — treat as a delta.
            emitted += text;
            controller.add(LlmToken(text));
          }
        case AiEngineDone(:final int elapsedMs):
          complete(
            LlmUsage(
              promptChars: 0,
              outputChars: 0,
              elapsedMs: elapsedMs,
              cancelled: _cancelled,
            ),
          );
          unawaited(_finish(controller, cleanup));
        case AiEngineError(:final String code, :final String message):
          _log.warn('engine error: $code: $message');
          controller.add(LlmError(ModelFailure(_mapCode(code, message))));
          unawaited(_finish(controller, cleanup));
      }
    });

    // Cancel watch: MediaPipe may stop calling back without a final
    // done — poll the flag and terminate honestly.
    poller = Timer.periodic(
      const Duration(milliseconds: _cancelPollMs),
      (Timer timer) {
        if (_cancelled && !terminal) {
          complete(
            LlmUsage(
              promptChars: 0,
              outputChars: 0,
              elapsedMs: watch.elapsedMilliseconds,
              cancelled: true,
            ),
          );
          unawaited(_finish(controller, cleanup));
        }
      },
    );
  }

  /// Result failure is the sealed family's root; the runtime speaks
  /// the ModelFailure subtype to the loop.
  static ModelFailure _asModelFailure(Failure f) =>
      f is ModelFailure ? f : ModelFailure(f.message);

  static Future<void> _finish(
    StreamController<LlmEvent> controller,
    Future<void> Function() cleanup,
  ) async {
    await cleanup();
    await controller.close();
  }

  /// Gemma IT chat scaffolding. The system prompt rides the first
  /// user turn (Gemma has no dedicated system role in the 2/3 IT
  /// template).
  String _format(LlmRequest request) {
    final StringBuffer buffer = StringBuffer();
    if (request.systemPrompt.isNotEmpty) {
      buffer.write('<start_of_turn>user\n');
      buffer.write(request.systemPrompt);
      buffer.write('<end_of_turn>\n');
    }
    for (final LlmMessage message in request.history) {
      final String role = message.role == LlmRole.model ? 'model' : 'user';
      buffer.write('<start_of_turn>$role\n');
      buffer.write(message.content);
      buffer.write('<end_of_turn>\n');
    }
    buffer.write('<start_of_turn>user\n');
    buffer.write(request.prompt);
    buffer.write('<end_of_turn>\n<start_of_turn>model\n');
    return buffer.toString();
  }

  static String _trimStops(String text) {
    for (final String marker in _stopMarkers) {
      final int index = text.indexOf(marker);
      if (index >= 0) {
        return text.substring(0, index).trimRight();
      }
    }
    return text.trimRight();
  }

  static String _mapCode(String code, String message) {
    switch (code) {
      case 'oom':
        return 'ai-oom';
      case 'generation-error':
        return 'ai-generation-error';
      case 'invalid-model':
        return 'ai-load-failed';
    }
    return 'ai-$code ($message)';
  }
}
