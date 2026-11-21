// phase-06
// The agent loop: context → generate → parse tool-call JSON →
// (validate → invoke → observe → loop) | final answer. Hard cap of
// 5 iterations, one repair retry for malformed JSON, full
// cancellation, per-iteration telemetry that NEVER carries message
// content (privacy: prompts and answers stay out of the logs).
import 'dart:async';
import 'dart:convert';

import '../../../core/log/udao_logger.dart';
import '../../../core/utils/list_take_last.dart';
import '../persona/persona.dart';
import '../runtime/llm_events.dart';
import '../runtime/llm_runtime.dart';
import '../telemetry/ai_telemetry.dart';
import 'agent_tool.dart';
import 'tool_prompt.dart';

/// Context seam — the real provider wires [ContextBuilder.build];
/// tests wire a deterministic closure.
typedef ContextProvider = Future<String> Function(Persona persona);

/// Events the chat UI renders (streaming text, tool chips, done).
sealed class AgentEvent {
  const AgentEvent();
}

class AgentTokenEvent extends AgentEvent {
  const AgentTokenEvent(this.text);

  final String text;
}

class AgentToolEvent extends AgentEvent {
  const AgentToolEvent({
    required this.name,
    required this.args,
    required this.elapsedMs,
    required this.ok,
  });

  final String name;
  final Map<String, Object?> args;
  final int elapsedMs;
  final bool ok;
}

class AgentDoneEvent extends AgentEvent {
  const AgentDoneEvent({
    required this.text,
    required this.usage,
    required this.iterations,
    this.capped = false,
  });

  final String text;
  final LlmUsage usage;
  final int iterations;

  /// True when the 5-iteration cap ended the loop (the UI then says
  /// so honestly instead of pretending the answer is complete).
  final bool capped;
}

class AgentErrorEvent extends AgentEvent {
  const AgentErrorEvent(this.message);

  final String message;
}

/// A parsed tool call.
class ToolCall {
  const ToolCall({required this.name, required this.args});

  final String name;
  final Map<String, Object?> args;
}

class AgentLoop {
  AgentLoop({
    required LlmRuntime runtime,
    required List<AgentTool> tools,
    required ContextProvider buildContext,
    AiTelemetry? telemetry,
  })  : _runtime = runtime,
        _tools = tools,
        _buildContext = buildContext,
        _telemetry = telemetry,
        _log = udaoLog.child('agent');

  final LlmRuntime _runtime;
  final List<AgentTool> _tools;
  final ContextProvider _buildContext;
  final AiTelemetry? _telemetry;
  final UdaoLogger _log;

  /// The hard iteration cap (never raised — spec).
  static const int maxIterations = ToolPrompt.maxToolRounds;

  bool _cancelled = false;

  Future<void> cancel() async {
    _cancelled = true;
    await _runtime.cancel();
  }

  /// One full agent turn. [history] carries the visible chat turns
  /// (user/model), NOT the tool observations (those live inside this
  /// call's internal transcript).
  Stream<AgentEvent> send(
    String userMessage, {
    required Persona persona,
    String? templateTag,
    List<LlmMessage> history = const <LlmMessage>[],
  }) {
    _cancelled = false;
    final StreamController<AgentEvent> controller =
        StreamController<AgentEvent>(
      onCancel: () {
        _cancelled = true;
      },
    );
    unawaited(
      _run(
        controller,
        userMessage: userMessage,
        persona: persona,
        templateTag: templateTag,
        history: history,
      ),
    );
    return controller.stream;
  }

  Future<void> _run(
    StreamController<AgentEvent> controller, {
    required String userMessage,
    required Persona persona,
    required List<LlmMessage> history,
    String? templateTag,
  }) async {
    final String context = await _buildContext(persona);
    final String systemPrompt = ToolPrompt.build(
      tools: _tools,
      context: context,
      personaPrompt: persona.systemPrompt,
    );

    final List<LlmMessage> transcript =
        List<LlmMessage>.of(history.takeLast(6));
    LlmUsage totalUsage = const LlmUsage(
      promptChars: 0,
      outputChars: 0,
      elapsedMs: 0,
    );
    bool repaired = false;
    int iteration = 0;

    while (iteration < maxIterations) {
      if (_cancelled) {
        controller.add(const AgentErrorEvent('cancelled'));
        await controller.close();
        return;
      }
      iteration++;
      final Stopwatch watch = Stopwatch()..start();

      final StringBuffer answer = StringBuffer();
      LlmUsage iterUsage = const LlmUsage(
        promptChars: 0,
        outputChars: 0,
        elapsedMs: 0,
      );
      LlmError? error;
      await for (final LlmEvent event in _runtime.generate(
        LlmRequest(
          prompt: userMessage,
          systemPrompt: systemPrompt,
          history: transcript,
          temperature: persona.temperature,
          topK: persona.topK,
          templateTag: templateTag,
        ),
      )) {
        switch (event) {
          case LlmToken(:final String delta):
            // BUFFERED, never streamed live: an iteration's text may
            // turn out to be a tool call, and raw tool JSON must
            // never flash in the chat UI. The final answer ships as
            // one AgentTokenEvent right before its AgentDoneEvent.
            answer.write(delta);
          case LlmDone(:final LlmUsage usage):
            iterUsage = usage;
          case LlmError():
            error = event;
        }
      }
      if (_cancelled) {
        controller.add(const AgentErrorEvent('cancelled'));
        await controller.close();
        return;
      }
      totalUsage = LlmUsage(
        promptChars: totalUsage.promptChars + iterUsage.promptChars,
        outputChars: totalUsage.outputChars + iterUsage.outputChars,
        elapsedMs: totalUsage.elapsedMs + iterUsage.elapsedMs,
      );
      _log.info(
        'iter $iteration ms=${watch.elapsedMilliseconds} '
        'tokens~${iterUsage.estimatedTokens} err=${error != null}',
      );

      if (error != null) {
        final LlmError err = error;
        unawaited(_telemetry?.recordGeneration(err.failure));
        controller.add(AgentErrorEvent(_friendly(err.failure.message)));
        await controller.close();
        return;
      }

      final String text = answer.toString().trim();
      final ToolCall? call = _extractToolCall(text);

      if (call == null) {
        if (text.isEmpty) {
          controller.add(const AgentErrorEvent('ai-empty-answer'));
          await controller.close();
          return;
        }
        // Plain answer — the one token event the UI streams, then done.
        unawaited(_telemetry?.recordGeneration(null, usage: totalUsage));
        controller.add(AgentTokenEvent(text));
        controller.add(
          AgentDoneEvent(
            text: text,
            usage: totalUsage,
            iterations: iteration,
          ),
        );
        await controller.close();
        return;
      }

      final AgentTool? tool = _toolByName(call.name);
      final ToolSchemaIssue? issue =
          tool == null ? const ToolSchemaIssue('unknown tool') : _validate(tool, call);

      if (issue != null && !repaired) {
        // One repair retry, then the next text becomes the answer.
        repaired = true;
        transcript.add(LlmMessage(role: LlmRole.model, content: text));
        transcript.add(
          LlmMessage(
            role: LlmRole.user,
            content: ToolPrompt.repairPrompt(issue.message),
          ),
        );
        continue;
      }
      if (issue != null) {
        // Already retried — answer honestly with the failure.
        unawaited(_telemetry?.recordGeneration(null, usage: totalUsage));
        controller.add(
          AgentDoneEvent(
            text: 'Tool call theek se nahi bana: ${issue.message}',
            usage: totalUsage,
            iterations: iteration,
          ),
        );
        await controller.close();
        return;
      }

      // Invoke (measure + emit + observe).
      final Stopwatch toolWatch = Stopwatch()..start();
      Map<String, Object?> result;
      try {
        result = await tool!.invoke(call.args);
      } on Object catch (e) {
        result = <String, Object?>{'ok': false, 'error': e.toString()};
      }
      final int toolMs = toolWatch.elapsedMilliseconds;
      final bool ok = result['ok'] == true;
      unawaited(_telemetry?.recordToolCall(ok));
      _log.info(
        'tool ${call.name} ms=$toolMs ok=$ok',
      );
      controller.add(
        AgentToolEvent(
          name: call.name,
          args: call.args,
          elapsedMs: toolMs,
          ok: ok,
        ),
      );

      transcript.add(LlmMessage(role: LlmRole.model, content: text));
      transcript.add(
        LlmMessage(
          role: LlmRole.user,
          content: 'TOOL_RESULT ${_compact(result)}',
        ),
      );
    }

    // Cap reached — honest capped answer, never a fake final.
    unawaited(_telemetry?.recordGeneration(null, usage: totalUsage));
    controller.add(AgentDoneEvent(
        text: '5 tool rounds ho gaye — itna hi mila. '
            'Ek aur sawaal pooch lo.',
        usage: totalUsage,
        iterations: maxIterations,
        capped: true,
      ),
    );
    await controller.close();
  }

  ToolSchemaIssue? _validate(AgentTool tool, ToolCall call) {
    return ToolSchema.validate(tool, call.args);
  }

  AgentTool? _toolByName(String name) {
    for (final AgentTool tool in _tools) {
      if (tool.name == name) {
        return tool;
      }
    }
    return null;
  }

  /// Extracts the first BALANCED JSON object from [text]; returns
  /// null when there is no plausible tool call. Tolerates prose
  /// around the JSON and trailing garbage.
  static ToolCall? _extractToolCall(String text) {
    final int start = text.indexOf('{');
    if (start < 0) {
      return null;
    }
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < text.length; i++) {
      final String ch = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == '\\') {
        if (inString) {
          escaped = true;
        }
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          final String candidate = text.substring(start, i + 1);
          final ToolCall? call = _decodeCall(candidate);
          if (call != null) {
            return call;
          }
          // Valid JSON but not a call — treat as no call.
          return null;
        }
      }
    }
    return null;
  }

  static ToolCall? _decodeCall(String json) {
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is Map<String, Object?> &&
          decoded['tool'] is String &&
          decoded['args'] is Map) {
        return ToolCall(
          name: decoded['tool']! as String,
          args: Map<String, Object?>.from(decoded['args']! as Map),
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String _compact(Map<String, Object?> result) {
    String json = jsonEncode(result);
    if (json.length > 800) {
      json = '${json.substring(0, 799)}…';
    }
    return json;
  }

  static String _friendly(String code) => switch (code) {
        'model-absent' => 'model-absent',
        'ai-oom' => 'memory',
        _ => code,
      };
}

