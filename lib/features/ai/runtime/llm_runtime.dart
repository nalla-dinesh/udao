// phase-06
// The one interface every caller talks to. Features never import an
// engine; they resolve whichever implementation the model manager
// currently backs (Gemma when loaded, template-only otherwise).
import 'llm_events.dart';

abstract class LlmRuntime {
  String? get modelName;

  bool get isLoaded;

  /// Stream a generation. Implementations MUST emit either
  /// [LlmDone] or [LlmError] as the terminal event, then close.
  Stream<LlmEvent> generate(LlmRequest request);

  /// Best-effort stop of the in-flight generation (if any).
  Future<void> cancel();

  /// Optional warm-up (preload the weights); default: no-op.
  Future<void> warmUp() async {}
}
