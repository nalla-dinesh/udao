// phase-06
// The runtime vocabulary: requests, streaming events, usage. Every
// runtime (Gemma over MediaPipe, template-only) speaks exactly this
// — features never know which one is behind the seam.
import '../../../core/errors/failure.dart';

enum LlmRole { system, user, model }

class LlmMessage {
  const LlmMessage({required this.role, required this.content});

  final LlmRole role;
  final String content;
}

/// One generation request. [templateTag] lets the template-only
/// runtime answer roast-shaped requests (roast NEVER dies without a
/// model — resilience law); free-form tags stream an honest
/// `model-absent` error instead of pretending.
class LlmRequest {
  const LlmRequest({
    required this.prompt,
    this.systemPrompt = '',
    this.history = const <LlmMessage>[],
    this.temperature = 0.8,
    this.topK = 40,
    this.templateTag,
    this.imagePath,
  });

  final String prompt;
  final String systemPrompt;
  final List<LlmMessage> history;

  /// Per-persona sampling (Savage runs hot, Silent runs cold).
  final double temperature;
  final int topK;

  /// 'roast' | 'parser' | persona tag — routing hint, never shown.
  final String? templateTag;

  /// Vision input (receipt ensemble leg) — ignored by text-only
  /// runtimes.
  final String? imagePath;
}

/// Token/latency accounting. MediaPipe reports NO token usage, so
/// tokens are a chars/4 estimate — every surface that shows this
/// number labels it "estimated" (honesty law).
class LlmUsage {
  const LlmUsage({
    required this.promptChars,
    required this.outputChars,
    required this.elapsedMs,
    this.cancelled = false,
  });

  final int promptChars;
  final int outputChars;
  final int elapsedMs;
  final bool cancelled;

  int get estimatedTokens => (promptChars + outputChars) ~/ 4;
}

sealed class LlmEvent {
  const LlmEvent();
}

/// A DELTA of text (runtimes that receive cumulative text must diff
/// before emitting — see GemmaRuntime).
class LlmToken extends LlmEvent {
  const LlmToken(this.delta);

  final String delta;
}

class LlmDone extends LlmEvent {
  const LlmDone(this.usage);

  final LlmUsage usage;
}

class LlmError extends LlmEvent {
  const LlmError(this.failure);

  final ModelFailure failure;
}

/// Failure codes surfaced by the AI stack (stable strings — the
/// contract tests pin them).
abstract final class AiFailureCodes {
  static const String modelAbsent = 'model-absent';
  static const String notLoaded = 'ai-not-loaded';
  static const String loadFailed = 'ai-load-failed';
  static const String oom = 'ai-oom';
  static const String generationError = 'ai-generation-error';
  static const String busy = 'ai-busy';
  static const String noVision = 'ai-no-vision';
  static const String invalidOutput = 'ai-invalid-output';
}
