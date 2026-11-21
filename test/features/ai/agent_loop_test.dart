// phase-06
// AgentLoop: the 5-round tool loop — happy path, schema repair,
// honest cap, cancellation, tool-error honesty, JSON extraction.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/ai/agent/agent_loop.dart';
import 'package:udao/features/ai/agent/agent_tool.dart';
import 'package:udao/features/ai/persona/persona.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/features/ai/runtime/llm_events.dart';

import 'fake_llm_runtime.dart';

class _EchoTool extends AgentTool {
  @override
  String get name => 'get_budgets';

  @override
  String get description => 'wallet budgets';

  @override
  Map<String, Map<String, Object?>> get schema => <String, Map<String, Object?>>{
        'category': <String, Object?>{
          'type': 'string',
          'required': true,
        },
      };

  int calls = 0;

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async {
    calls++;
    return <String, Object?>{'ok': true, 'category': args['category']};
  }
}

class _FailingTool extends AgentTool {
  @override
  String get name => 'boom';

  @override
  String get description => 'always fails';

  @override
  Map<String, Map<String, Object?>> get schema => const <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>> invoke(Map<String, Object?> args) async =>
      <String, Object?>{'ok': false, 'error': 'db-locked'};
}

const LlmUsage _u = LlmUsage(promptChars: 10, outputChars: 5, elapsedMs: 1);

void main() {
  tearDown(() async {});

  test('happy path: tool call then plain answer', () async {
    final _EchoTool tool = _EchoTool();
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('Sure — {"tool": "get_budgets", "args": '
            '{"category": "food"}} done'),
        const LlmDone(_u),
      ],
      <LlmEvent>[
        const LlmToken('Khana: Rs.2000'),
        const LlmDone(_u),
      ],
    ]);
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: <AgentTool>[tool],
      buildContext: (Persona p) async => 'CTX',
    );

    final List<AgentEvent> events =
        await loop.send('budget batao', persona: Personas.savage).toList();

    expect(events, hasLength(3));
    expect(events[0], isA<AgentToolEvent>());
    final AgentToolEvent toolEvent = events[0] as AgentToolEvent;
    expect(toolEvent.name, 'get_budgets');
    expect(toolEvent.args['category'], 'food');
    expect(toolEvent.ok, isTrue);
    expect(tool.calls, 1);
    expect(events[1], isA<AgentTokenEvent>());
    expect((events[1] as AgentTokenEvent).text, 'Khana: Rs.2000');
    final AgentDoneEvent done = events.last as AgentDoneEvent;
    expect(done.text, 'Khana: Rs.2000');
    expect(done.iterations, 2);
    expect(done.capped, isFalse);
    expect(done.usage.promptChars, 20);
    // The user message rides in `prompt`; the built context (with
    // the tools + persona) rides in `systemPrompt` — assert both.
    expect(rt.prompts.first, 'budget batao');
    expect(rt.requests.first.systemPrompt, contains('CTX'));
    rt.dispose();
  });

  test('schema issue repaired once, second attempt valid', () async {
    final _EchoTool tool = _EchoTool();
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('{"tool": "get_budgets", "args": {}}'),
        const LlmDone(_u),
      ],
      <LlmEvent>[
        const LlmToken('{"tool": "get_budgets", "args": '
            '{"category": "shopping"}}'),
        const LlmDone(_u),
      ],
      <LlmEvent>[
        const LlmToken('Shopping: Rs.1500'),
        const LlmDone(_u),
      ],
    ]);
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: <AgentTool>[tool],
      buildContext: (Persona p) async => 'CTX',
    );

    final List<AgentEvent> events =
        await loop.send('budget?', persona: Personas.sensei).toList();

    // Repair prompt must have reached the transcript (request history).
    expect(rt.requests[1].history, isNotEmpty);
    expect(rt.requests[1].history.last.content, contains('category'));
    final AgentDoneEvent done = events.last as AgentDoneEvent;
    expect(done.text, 'Shopping: Rs.1500');
    expect(done.iterations, 3);
    expect(tool.calls, 1);
    rt.dispose();
  });

  test('unknown tool: repair once, then honest failure answer', () async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('{"tool": "nope_tool", "args": {}}'),
        const LlmDone(_u),
      ],
      <LlmEvent>[
        const LlmToken('{"tool": "nope_tool", "args": {}}'),
        const LlmDone(_u),
      ],
    ]);
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: <AgentTool>[_EchoTool()],
      buildContext: (Persona p) async => 'CTX',
    );

    final List<AgentEvent> events =
        await loop.send('x', persona: Personas.savage).toList();

    final AgentDoneEvent done = events.last as AgentDoneEvent;
    expect(done.text, contains('Tool call theek se nahi bana'));
    expect(done.iterations, 2);
    rt.dispose();
  });

  test('5-iteration cap ends with capped honest answer', () async {
    final ScriptedRuntime rt = ScriptedRuntime(
      List<List<LlmEvent>>.generate(
        6,
        (int i) => <LlmEvent>[
          const LlmToken('{"tool": "get_budgets", "args": '
              '{"category": "food"}}'),
          const LlmDone(_u),
        ],
      ),
    );
    final _EchoTool tool = _EchoTool();
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: <AgentTool>[tool],
      buildContext: (Persona p) async => 'CTX',
    );

    final List<AgentEvent> events =
        await loop.send('go', persona: Personas.savage).toList();

    expect(tool.calls, 5);
    final AgentDoneEvent done = events.last as AgentDoneEvent;
    expect(done.capped, isTrue);
    expect(done.iterations, AgentLoop.maxIterations);
    expect(done.iterations, 5);
    expect(done.text, contains('5 tool rounds'));
    expect(events.whereType<AgentToolEvent>(), hasLength(5));
    rt.dispose();
  });

  test('tool error is reported honestly and loop continues', () async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('{"tool": "boom", "args": {}}'),
        const LlmDone(_u),
      ],
      <LlmEvent>[
        const LlmToken('Ab bata doon — thoda issue tha.'),
        const LlmDone(_u),
      ],
    ]);
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: <AgentTool>[_FailingTool()],
      buildContext: (Persona p) async => 'CTX',
    );

    final List<AgentEvent> events =
        await loop.send('x', persona: Personas.savage).toList();

    final AgentToolEvent toolEvent = events.first as AgentToolEvent;
    expect(toolEvent.ok, isFalse);
    // TOOL_RESULT observation carries the honest error.
    expect(rt.requests[1].history.last.content, contains('db-locked'));
    final AgentDoneEvent done = events.last as AgentDoneEvent;
    expect(done.text, contains('issue'));
    rt.dispose();
  });

  test('cancel before start yields cancelled error', () async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[const LlmDone(_u)],
    ]);
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: <AgentTool>[_EchoTool()],
      buildContext: (Persona p) async => 'CTX',
    );

    final Stream<AgentEvent> stream =
        loop.send('x', persona: Personas.savage);
    await loop.cancel();
    final List<AgentEvent> events = await stream.toList();

    expect(events.whereType<AgentErrorEvent>(), isNotEmpty);
    expect(events.first as AgentErrorEvent, isA<AgentErrorEvent>());
    expect((events.first as AgentErrorEvent).message, 'cancelled');
    expect(rt.cancelCalls, 1);
    rt.dispose();
  });

  test('runtime error surfaces as friendly AgentError', () async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[const LlmError(ModelFailure('ai-oom'))],
    ]);
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: const <AgentTool>[],
      buildContext: (Persona p) async => 'CTX',
    );

    final List<AgentEvent> events =
        await loop.send('x', persona: Personas.savage).toList();

    final AgentErrorEvent err = events.last as AgentErrorEvent;
    expect(err.message, 'memory');
    rt.dispose();
  });

  test('empty model answer surfaces ai-empty-answer', () async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[const LlmDone(_u)],
    ]);
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: const <AgentTool>[],
      buildContext: (Persona p) async => 'CTX',
    );

    final List<AgentEvent> events =
        await loop.send('x', persona: Personas.savage).toList();

    expect(events, hasLength(1));
    expect((events.single as AgentErrorEvent).message, 'ai-empty-answer');
    rt.dispose();
  });

  test('balanced-JSON extractor ignores prose and nested braces', () async {
    // Indirectly: model wraps the call in chatter + nested object.
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('Pehle data nikalta hoon. '
            '{"tool": "get_budgets", "args": {"category": "food", '
            '"extra": {"deep": 1}}} baad me batata hoon'),
        const LlmDone(_u),
      ],
      <LlmEvent>[
        const LlmToken('Done'),
        const LlmDone(_u),
      ],
    ]);
    final _EchoTool tool = _EchoTool();
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: <AgentTool>[tool],
      buildContext: (Persona p) async => 'CTX',
    );

    final List<AgentEvent> events =
        await loop.send('x', persona: Personas.savage).toList();

    expect(tool.calls, 1);
    final AgentToolEvent toolEvent = events.first as AgentToolEvent;
    expect(toolEvent.name, 'get_budgets');
    rt.dispose();
  });

  test('history is capped to the last 6 messages', () async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('Theek.'),
        const LlmDone(_u),
      ],
    ]);
    final AgentLoop loop = AgentLoop(
      runtime: rt,
      tools: const <AgentTool>[],
      buildContext: (Persona p) async => 'CTX',
    );

    final List<LlmMessage> long = List<LlmMessage>.generate(
      10,
      (int i) => LlmMessage(
        role: i.isEven ? LlmRole.user : LlmRole.model,
        content: 'm$i',
      ),
    );
    await loop
        .send('x', persona: Personas.savage, history: long)
        .toList();

    expect(rt.requests.single.history.length, 6);
    expect(rt.requests.single.history.first.content, 'm4');
    rt.dispose();
  });
}
