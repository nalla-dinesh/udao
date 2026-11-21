// phase-06
// Chat orchestration: roast intents route to the roast engine
// (works with AND without a model), everything else to the agent
// loop; the guardrail filters EVERY ai line before display; history
// persists capped; stress check runs on open (auto-Sensei window).
import 'dart:async';

import '../../core/utils/list_take_last.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/roast_entry.dart';
import '../../core/log/udao_logger.dart';
import '../../core/result/result.dart';
import '../ai/agent/agent_loop.dart';
import '../ai/persona/guardrail.dart';
import '../ai/persona/persona.dart';
import '../ai/persona/persona_router.dart';
import '../ai/persona/stress_detector.dart';
import '../ai/roast/roast_engine.dart';
import '../ai/runtime/llm_events.dart';
import 'chat_history_store.dart';
import 'chat_models.dart';

/// The UI's whole truth about a chat turn.
class ChatState {
  const ChatState({
    required this.messages,
    this.streaming = false,
    this.streamingText = '',
    this.persona = Personas.savage,
    this.templateOnly = true,
    this.stressNotice = false,
    this.pendingToolChips = const <ToolCallTrace>[],
  });

  final List<ChatMessage> messages;
  final bool streaming;
  final String streamingText;
  final Persona persona;
  final bool templateOnly;

  /// True while the Sensei override window is active.
  final bool stressNotice;
  final List<ToolCallTrace> pendingToolChips;

  static const ChatState initial = ChatState(messages: <ChatMessage>[]);

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? streaming,
    String? streamingText,
    Persona? persona,
    bool? templateOnly,
    bool? stressNotice,
    List<ToolCallTrace>? pendingToolChips,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        streaming: streaming ?? this.streaming,
        streamingText: streamingText ?? this.streamingText,
        persona: persona ?? this.persona,
        templateOnly: templateOnly ?? this.templateOnly,
        stressNotice: stressNotice ?? this.stressNotice,
        pendingToolChips: pendingToolChips ?? this.pendingToolChips,
      );
}

class ChatController extends StateNotifier<ChatState> {
  ChatController({
    required AgentLoop agentLoop,
    required RoastEngine roastEngine,
    required PersonaRouter personaRouter,
    required Guardrail guardrail,
    required ChatHistoryStore history,
    required bool templateOnly,
    required StressInputGatherer stressGatherer,
    required StressDetector stressDetector,
  })  : _agentLoop = agentLoop,
        _roastEngine = roastEngine,
        _personaRouter = personaRouter,
        _guardrail = guardrail,
        _history = history,
        _stressGatherer = stressGatherer,
        _stressDetector = stressDetector,
        _log = udaoLog.child('chat'),
        super(ChatState.initial.copyWith(templateOnly: templateOnly)) {
    _bootstrap();
  }

  final AgentLoop _agentLoop;
  final RoastEngine _roastEngine;
  final PersonaRouter _personaRouter;
  final Guardrail _guardrail;
  final ChatHistoryStore _history;
  final StressInputGatherer _stressGatherer;
  final StressDetector _stressDetector;
  final UdaoLogger _log;

  bool _disposed = false;
  int _idCounter = 0;

  Future<void> _bootstrap() async {
    await _loadHistory();
    await _resolvePersona();
    await _maybeStressCheck();
  }

  Future<void> _loadHistory() async {
    final Result<List<ChatMessage>> loaded = await _history.load();
    if (_disposed) {
      return;
    }
    state = state.copyWith(messages: loaded.valueOrNull ?? <ChatMessage>[]);
  }

  Future<void> _resolvePersona() async {
    final ResolvedPersona resolved = await _personaRouter.resolve();
    if (_disposed) {
      return;
    }
    state = state.copyWith(
      persona: resolved.persona,
      stressNotice: resolved.stressOverride,
    );
  }

  Future<void> _maybeStressCheck() async {
    try {
      final StressSignals signals = await _stressGatherer.gather();
      final StressVerdict verdict = _stressDetector.evaluate(signals);
      if (verdict.detected) {
        await _personaRouter.onStressDetected();
        await _resolvePersona();
        _log.info('stress detected — sensei window armed');
      }
    } on Object catch (e) {
      _log.warn('stress check failed: $e');
    }
  }

  /// The user taps a suggested prompt or types a message.
  Future<void> send(String text) async {
    final String message = text.trim();
    if (message.isEmpty || state.streaming) {
      return;
    }
    final ChatMessage userMessage = ChatMessage(
      id: _nextId(),
      role: ChatRole.user,
      text: message,
      atMs: DateTime.now().millisecondsSinceEpoch,
    );
    state = state.copyWith(
      messages: <ChatMessage>[...state.messages, userMessage],
      streaming: true,
      streamingText: '',
      pendingToolChips: <ToolCallTrace>[],
    );

    if (_isRoastIntent(message)) {
      await _runRoast(message);
      return;
    }
    await _runAgent(message);
  }

  static bool _isRoastIntent(String message) {
    final String m = message.toLowerCase();
    return m.contains('roast') || m.contains('jalao') || m.contains('jala do');
  }

  Future<void> _runRoast(String message) async {
    try {
      final RoastOutcome outcome = await _roastEngine.generate(
        const RoastRequestShape(surface: RoastSurface.full),
      );
      if (_disposed) {
        return;
      }
      _appendAi(
        outcome.text,
        toolCalls: const <ToolCallTrace>[],
        guarded: outcome.guarded,
      );
    } on Object catch (e) {
      _log.warn('roast failed: $e');
      _appendAi('Roast engine thoda confuse ho gaya. Phir se try karo.');
    }
  }

  Future<void> _runAgent(String message) async {
    final List<ToolCallTrace> toolCalls = <ToolCallTrace>[];
    final StringBuffer buffer = StringBuffer();
    Object? terminal;

    final StreamSubscription<AgentEvent> sub = _agentLoop
        .send(
          message,
          persona: state.persona,
          history: _recentTurns(),
        )
        .listen((AgentEvent event) {
      switch (event) {
        case AgentTokenEvent(:final String text):
          buffer.write(text);
          if (!_disposed) {
            state = state.copyWith(streamingText: buffer.toString());
          }
        case AgentToolEvent():
          final ToolCallTrace trace = ToolCallTrace(
            name: event.name,
            args: event.args,
            elapsedMs: event.elapsedMs,
            ok: event.ok,
          );
          toolCalls.add(trace);
          if (!_disposed) {
            state = state.copyWith(
              pendingToolChips: List<ToolCallTrace>.of(toolCalls),
            );
          }
        case AgentDoneEvent():
          terminal = event;
        case AgentErrorEvent():
          terminal = event;
      }
    });

    await sub.asFuture<void>().catchError((Object e) {
      _log.warn('agent stream failed: $e');
    });
    if (_disposed) {
      return;
    }

    final Object? done = terminal;
    if (done is AgentDoneEvent) {
      // ALWAYS in the path — final answers too.
      final GuardrailVerdict verdict = _guardrail.filter(done.text);
      _appendAi(
        verdict.text,
        toolCalls: toolCalls,
        guarded: verdict.blocked,
        capped: done.capped,
      );
    } else if (done is AgentErrorEvent) {
      _appendAi(
        done.message == 'model-absent' ? 'model-absent' : 'ai-error',
        toolCalls: toolCalls,
        error: true,
      );
    } else {
      _appendAi('ai-error', toolCalls: toolCalls, error: true);
    }
  }

  List<LlmMessage> _recentTurns() {
    // Visible chat turns only (tool observations stay inside the
    // agent's internal transcript for the call's lifetime).
    final List<LlmMessage> turns = <LlmMessage>[];
    for (final ChatMessage m in state.messages.takeLast(6)) {
      if (m.text.isEmpty) {
        continue;
      }
      turns.add(
        LlmMessage(
          role: m.role == ChatRole.user ? LlmRole.user : LlmRole.model,
          content: m.text,
        ),
      );
    }
    return turns;
  }

  void _appendAi(
    String text, {
    List<ToolCallTrace> toolCalls = const <ToolCallTrace>[],
    bool guarded = false,
    bool capped = false,
    bool error = false,
  }) {
    final ChatMessage aiMessage = ChatMessage(
      id: _nextId(),
      role: ChatRole.ai,
      text: error ? '⚠ $text' : text,
      atMs: DateTime.now().millisecondsSinceEpoch,
      toolCalls: toolCalls,
      guarded: guarded,
      personaId: state.persona.id,
      capped: capped,
    );
    state = state.copyWith(
      messages: <ChatMessage>[...state.messages, aiMessage],
      streaming: false,
      streamingText: '',
      pendingToolChips: <ToolCallTrace>[],
    );
    unawaited(_persist());
  }

  Future<void> _persist() async {
    await _history.save(state.messages);
  }

  Future<void> stop() async {
    await _agentLoop.cancel();
  }

  Future<void> clearHistory() async {
    await _history.clearAll();
    if (!_disposed) {
      state = state.copyWith(messages: <ChatMessage>[]);
    }
  }

  /// "Wapas savage chahiye" — clears the stress window.
  Future<void> exitStressMode() async {
    await _personaRouter.clearStress();
    await _resolvePersona();
  }

  String _nextId() => 'msg-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

