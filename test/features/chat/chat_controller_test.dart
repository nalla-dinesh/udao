// phase-06
// ChatController: the full seam on a real DB — streaming, tool
// chips, guardrail on final answers, roast intent routing, history
// persistence, stop, clear-all, persona/stress bootstrap.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/repos/query_repos.dart';
import 'package:udao/features/ai/agent/agent_loop.dart';
import 'package:udao/features/ai/persona/guardrail.dart';
import 'package:udao/features/ai/persona/persona.dart';
import 'package:udao/features/ai/persona/persona_router.dart';
import 'package:udao/features/ai/persona/stress_detector.dart';
import 'package:udao/features/ai/roast/roast_engine.dart';
import 'package:udao/features/ai/runtime/llm_events.dart';
import 'package:udao/features/chat/chat_controller.dart';
import 'package:udao/features/chat/chat_history_store.dart';
import 'package:udao/features/chat/chat_models.dart';

import '../../data/db/test_db.dart' as helper;
import '../ai/fake_llm_runtime.dart';

const LlmUsage _u = LlmUsage(promptChars: 30, outputChars: 20, elapsedMs: 8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UdaoDatabase db;
  late KvDao kv;
  late ScriptedRuntime rt;
  late ChatController controller;
  late List<ChatState> states;

  setUp(() async {
    db = await helper.createTestDb();
    kv = KvDao(db.db);
    rt = ScriptedRuntime(const <List<LlmEvent>>[]);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    states = <ChatState>[];
  });
  tearDown(() async {
    controller.dispose();
    rt.dispose();
    await helper.disposeTestDb(db);
  });

  Future<ChatController> boot({bool templateOnly = false}) async {
    final ChatController c = ChatController(
      agentLoop: AgentLoop(
        runtime: rt,
        tools: const [],
        buildContext: (Persona p) async => 'CTX',
      ),
      roastEngine: RoastEngine(
        runtime: rt,
        roasts: RoastRepo(db),
        kv: kv,
        guardrail: Guardrail(),
      ),
      personaRouter: PersonaRouter(kv: kv),
      guardrail: Guardrail(),
      history: ChatHistoryStore(kv: kv),
      templateOnly: templateOnly,
      stressGatherer: StressInputGatherer(
        txns: TxnDao(db.db),
        budgets: BudgetRepo(db),
        kv: kv,
      ),
      stressDetector: const StressDetector(),
    );
    c.addListener((ChatState s) => states.add(s));
    // Let _bootstrap() settle (history + persona + stress check).
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller = c;
    return c;
  }

  test('bootstrap resolves the base persona, empty history', () async {
    final ChatController c = await boot();
    expect(c.state.messages, isEmpty);
    expect(c.state.persona.id, 'savage');
    expect(c.state.streaming, isFalse);
  });

  test('send streams tokens and lands a final message with history',
      () async {
    final ScriptedRuntime scripted = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('Pehle '),
        const LlmToken('tool chalata hoon'),
        const LlmDone(_u),
      ],
      <LlmEvent>[
        const LlmToken('Mahine ka '),
        const LlmToken('total Rs.2000 hai.'),
        const LlmDone(_u),
      ],
    ]);
    rt = scripted;
    final ChatController c = await boot();

    await c.send('mera kharcha batao');
    expect(c.state.messages, hasLength(2));
    expect(c.state.messages.first.role, ChatRole.user);
    expect(c.state.messages.first.text, 'mera kharcha batao');
    expect(c.state.messages.last.role, ChatRole.ai);
    expect(c.state.messages.last.text, contains('tool chalata hoon'));
    expect(c.state.streaming, isFalse);

    // History persisted.
    final List<ChatMessage> stored =
        (await ChatHistoryStore(kv: kv).load()).valueOrNull ??
            <ChatMessage>[];
    expect(stored, hasLength(2));
  });

  test('empty-send is ignored', () async {
    final ChatController c = await boot();
    await c.send('   ');
    expect(c.state.messages, isEmpty);
    expect(rt.calls, 0);
  });

  test('roast intent routes to the roast engine (no agent call)',
      () async {
    final ChatController c = await boot();
    await c.send('mujhe roast karo');
    expect(rt.calls, 0, reason: 'roast path uses RoastEngine, not the loop');
    expect(c.state.messages.last.role, ChatRole.ai);
    expect(c.state.messages.last.text, isNotEmpty);
  });

  test('clearHistory wipes messages and kv', () async {
    final ChatController c = await boot();
    await c.send('mujhe roast karo');
    expect(c.state.messages, isNotEmpty);
    await c.clearHistory();
    expect(c.state.messages, isEmpty);
    expect(
      (await ChatHistoryStore(kv: kv).load()).valueOrNull,
      isEmpty,
    );
  });

  test('model-absent surfaces the honest banner code', () async {
    rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[const LlmError(ModelFailure('model-absent'))],
    ]);
    final ChatController c = await boot(templateOnly: true);
    await c.send('budget batao');
    expect(c.state.messages.last.text, contains('model-absent'));
    expect(c.state.templateOnly, isTrue);
  });
}
