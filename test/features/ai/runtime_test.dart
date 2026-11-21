// phase-06
// TemplateOnlyRuntime + GemmaRuntime: the two LlmRuntime legs.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/ai/runtime/ai_engine.dart';
import 'package:udao/features/ai/runtime/gemma_runtime.dart';
import 'package:udao/features/ai/runtime/llm_events.dart';
import 'package:udao/features/ai/runtime/template_only_runtime.dart';

import 'fake_ai_engine.dart';

void main() {
  group('TemplateOnlyRuntime', () {
    test('roast-tagged request streams responder text word-by-word',
        () async {
      final TemplateOnlyRuntime rt = TemplateOnlyRuntime(
        responders: <String, TemplateResponder>{
          'roast': (LlmRequest r) async =>
              'Wallet ka break chahiye bhai — kal se sambhalte hain.',
        },
      );
      final List<LlmEvent> events = await rt
          .generate(const LlmRequest(prompt: 'jalao', templateTag: 'roast'))
          .toList();

      final String joined = events
          .whereType<LlmToken>()
          .map((LlmToken t) => t.delta)
          .join();
      expect(joined, 'Wallet ka break chahiye bhai — kal se sambhalte hain.');
      expect(
        events.whereType<LlmToken>().length,
        greaterThan(3),
        reason: 'word-chunked streaming path',
      );
      final LlmDone done = events.last as LlmDone;
      expect(done.usage.promptChars, 'jalao'.length);
      expect(done.usage.outputChars, joined.length);
    });

    test('free-form ask streams honest model-absent', () async {
      final TemplateOnlyRuntime rt = TemplateOnlyRuntime();
      final List<LlmEvent> events = await rt
          .generate(const LlmRequest(prompt: 'mera budget batao'))
          .toList();
      expect(events, hasLength(1));
      expect(
        (events.single as LlmError).failure.message,
        'model-absent',
      );
    });

    test('isLoaded is always false; cancel is a no-op', () async {
      final TemplateOnlyRuntime rt = TemplateOnlyRuntime();
      expect(rt.isLoaded, isFalse);
      expect(rt.modelName, isNull);
      await rt.cancel();
    });
  });

  group('GemmaRuntime (FakeAiInferenceEngine)', () {
    test('cumulative partials are diffed into deltas', () async {
      final FakeAiInferenceEngine engine = FakeAiInferenceEngine();
      final GemmaRuntime rt = GemmaRuntime(engine: engine);
      rt.onModelLoaded('gemma-3n-e2b');
      expect(rt.isLoaded, isTrue);
      expect(rt.modelName, 'gemma-3n-e2b');

      // Session 1 will emit cumulative text.
      final Future<List<LlmEvent>> collected = rt
          .generate(const LlmRequest(prompt: 'budget?'))
          .toList();
      // Script for the session the engine just handed out (id 1).
      await Future<void>.delayed(Duration.zero);
      final int sid = engine.createdSessions.single;
      final Future<void> pump = Future<void>.delayed(Duration.zero);
      engine.emit(AiEngineToken(sessionId: sid, text: 'Khana'));
      engine.emit(AiEngineToken(sessionId: sid, text: 'Khana: Rs.'));
      engine.emit(AiEngineToken(sessionId: sid, text: 'Khana: Rs.2000'));
      engine.emit(AiEngineDone(sessionId: sid, elapsedMs: 42, totalChars: 16));
      await pump;
      final List<LlmEvent> events = await collected;

      final List<String> deltas =
          events.whereType<LlmToken>().map((LlmToken t) => t.delta).toList();
      expect(deltas.join(''), 'Khana: Rs.2000');
      expect(deltas, <String>['Khana', ': Rs.', '2000']);
      final LlmDone done = events.last as LlmDone;
      expect(done.usage.elapsedMs, 42);
      expect(done.usage.outputChars, 'Khana: Rs.2000'.length);
      engine.dispose();
    });

    test('non-cumulative tokens pass through as deltas', () async {
      final FakeAiInferenceEngine engine = FakeAiInferenceEngine();
      final GemmaRuntime rt = GemmaRuntime(engine: engine);
      final Future<List<LlmEvent>> collected =
          rt.generate(const LlmRequest(prompt: 'hi')).toList();
      await Future<void>.delayed(Duration.zero);
      final int sid = engine.createdSessions.single;
      engine.emit(AiEngineToken(sessionId: sid, text: 'alpha'));
      engine.emit(AiEngineToken(sessionId: sid, text: 'beta'));
      engine.emit(AiEngineDone(sessionId: sid, elapsedMs: 5, totalChars: 9));
      final List<LlmEvent> events = await collected;
      expect(
        events.whereType<LlmToken>().map((LlmToken t) => t.delta).join(),
        'alphabeta',
      );
      engine.dispose();
    });

    test('engine error maps to LlmError and closes the session',
        () async {
      final FakeAiInferenceEngine engine = FakeAiInferenceEngine();
      final GemmaRuntime rt = GemmaRuntime(engine: engine);
      final Future<List<LlmEvent>> collected =
          rt.generate(const LlmRequest(prompt: 'hi')).toList();
      await Future<void>.delayed(Duration.zero);
      final int sid = engine.createdSessions.single;
      engine.emit(
        AiEngineError(
          sessionId: sid,
          code: 'oom',
          message: 'out of memory',
        ),
      );
      final List<LlmEvent> events = await collected;
      final LlmError err = events.last as LlmError;
      expect(err.failure.message, isNotNull);
      expect(engine.createdSessions, hasLength(1));
      engine.dispose();
    });

    test('stop markers are trimmed from the final text', () async {
      final FakeAiInferenceEngine engine = FakeAiInferenceEngine();
      final GemmaRuntime rt = GemmaRuntime(engine: engine);
      final Future<List<LlmEvent>> collected =
          rt.generate(const LlmRequest(prompt: 'hi')).toList();
      await Future<void>.delayed(Duration.zero);
      final int sid = engine.createdSessions.single;
      engine.emit(AiEngineToken(sessionId: sid, text: 'Done<end_of_turn>'));
      engine.emit(AiEngineDone(sessionId: sid, elapsedMs: 7, totalChars: 15));
      final List<LlmEvent> events = await collected;
      final LlmDone done = events.last as LlmDone;
      expect(done.usage.outputChars, 'Done'.length);
      engine.dispose();
    });

    test('prompt carries Gemma turn scaffolding + system prompt',
        () async {
      final FakeAiInferenceEngine engine = FakeAiInferenceEngine();
      final GemmaRuntime rt = GemmaRuntime(engine: engine);
      final Future<List<LlmEvent>> collected = rt
          .generate(const LlmRequest(
            prompt: 'budget?',
            systemPrompt: 'SYS',
            history: <LlmMessage>[
              LlmMessage(role: LlmRole.user, content: 'earlier'),
              LlmMessage(role: LlmRole.model, content: 'answer'),
            ],
          ),)
          .toList();
      await Future<void>.delayed(Duration.zero);
      final int sid = engine.createdSessions.single;
      engine.emit(AiEngineDone(sessionId: sid, elapsedMs: 3, totalChars: 0));
      await collected;

      final String prompt = engine.promptsBySession[sid]!;
      expect(prompt, contains('<start_of_turn>user'));
      expect(prompt, contains('SYS'));
      expect(prompt, contains('<end_of_turn>'));
      expect(prompt, contains('earlier'));
      expect(prompt, contains('model'));
      expect(prompt, contains('budget?'));
      engine.dispose();
    });
  });
}
