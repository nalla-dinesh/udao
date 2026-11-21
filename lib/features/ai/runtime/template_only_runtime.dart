// phase-06
// The runtime that is ALWAYS available. Free-form asks stream an
// honest `model-absent` error (the UI shows the template-only
// banner); roast-shaped requests (templateTag 'roast') stream a
// template-backed answer, so roasting NEVER dies for want of a
// model (resilience law).
import 'dart:async';

import '../../../core/errors/failure.dart';
import 'llm_events.dart';
import 'llm_runtime.dart';

/// Produces the fallback text for a tagged request (the roast
/// engine registers itself under 'roast').
typedef TemplateResponder = Future<String> Function(LlmRequest request);

class TemplateOnlyRuntime implements LlmRuntime {
  TemplateOnlyRuntime({Map<String, TemplateResponder> responders = const <String, TemplateResponder>{}})
      : _responders = responders;

  final Map<String, TemplateResponder> _responders;

  @override
  String? get modelName => null;

  @override
  bool get isLoaded => false;

  @override
  Future<void> cancel() async {}

  @override
  Future<void> warmUp() async {}

  @override
  Stream<LlmEvent> generate(LlmRequest request) async* {
    final String? tag = request.templateTag;
    if (tag != null && _responders.containsKey(tag)) {
      final Stopwatch watch = Stopwatch()..start();
      final String text = await _responders[tag]!(request);
      // Stream in word chunks so the UI exercises the same streaming
      // path a real model would.
      final List<String> words = text.split(' ');
      final StringBuffer emitted = StringBuffer();
      for (int i = 0; i < words.length; i++) {
        emitted.write(i == 0 ? words[i] : ' ${words[i]}');
        yield LlmToken(i == 0 ? words[i] : ' ${words[i]}');
      }
      yield LlmDone(
        LlmUsage(
          promptChars: request.prompt.length,
          outputChars: text.length,
          elapsedMs: watch.elapsedMilliseconds,
        ),
      );
      return;
    }
    yield const LlmError(ModelFailure('model-absent'));
  }
}
