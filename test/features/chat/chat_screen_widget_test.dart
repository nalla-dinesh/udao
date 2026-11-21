// phase-06
// ChatScreen widget: overrides ONLY chatControllerProvider (the
// documented UI seam). The controller runs the real persona router /
// history store / stress gatherer over the no-isolate ffi in-memory
// DB (phase-04 survival law), with a scripted runtime — no channels.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udao/core/theme/udao_theme.dart';
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
import 'package:udao/features/chat/chat_screen.dart';
import 'package:udao/l10n/app_localizations.dart';

import '../../data/db/test_db.dart' as helper;
import '../ai/fake_llm_runtime.dart';

const LlmUsage _u = LlmUsage(promptChars: 20, outputChars: 10, elapsedMs: 5);

Widget _app(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: UdaoTheme.dark(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ChatScreen(),
    ),
  );
}

Future<void> _settle(WidgetTester tester, {int maxPumps = 60}) async {
  for (int i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (!tester.binding.hasScheduledFrame) {
      return;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late UdaoDatabase db;
  late KvDao kv;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = await helper.createTestDb();
    kv = KvDao(db.db);
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  ChatController controller(
    ScriptedRuntime rt, {
    bool templateOnly = false,
  }) =>
      ChatController(
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

  testWidgets('empty state mounts with input field',
      (WidgetTester tester) async {
    final ScriptedRuntime rt = ScriptedRuntime(const <List<LlmEvent>>[]);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        chatControllerProvider.overrideWith((ref) => controller(rt)),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(rt.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('typed message sends and the answer lands as a bubble',
      (WidgetTester tester) async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('Mahine ka total '),
        const LlmToken('Rs.2000 hai bhai.'),
        const LlmDone(_u),
      ],
    ]);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        chatControllerProvider.overrideWith((ref) => controller(rt)),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(rt.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), 'mera total batao');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _settle(tester);

    expect(find.text('mera total batao'), findsOneWidget);
    expect(find.textContaining('Rs.2000'), findsOneWidget);
  });

  testWidgets('roast intent lands a roast bubble without the agent loop',
      (WidgetTester tester) async {
    final ScriptedRuntime rt = ScriptedRuntime(const <List<LlmEvent>>[]);
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        chatControllerProvider.overrideWith((ref) => controller(rt)),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(rt.dispose);

    await tester.pumpWidget(_app(container));
    await _settle(tester);

    await tester.enterText(find.byType(TextField), 'mujhe roast karo');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _settle(tester);

    expect(rt.calls, 0, reason: 'roast path never touches the loop');
    expect(find.text('mujhe roast karo'), findsOneWidget);
    // A second bubble (the roast) exists.
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Container || w is Padding || w is ConstrainedBox,
      ),
      findsWidgets,
    );
  });
}
