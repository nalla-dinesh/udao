// phase-06
// Riverpod wiring for the AI stack. Same rule as capture: nothing
// below the UI touches platform channels except
// [PlatformAiInferenceEngine] behind the engine seam, so everything
// runs on fakes in tests without a device.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../data/csv/csv_service.dart';
import '../../data/db/dao/txn_dao.dart';
import '../../data/repos/providers.dart';
import '../capture/capture_providers.dart' show dbProvider, kvDaoProvider;
import 'agent/agent_loop.dart';
import 'agent/agent_tool.dart';
import 'agent/agent_tools.dart';
import 'agent/context_builder.dart';
import 'model/model_file_store.dart';
import 'model/model_manager.dart';
import 'parser_fallback/learned_pattern.dart';
import 'parser_fallback/llm_parser.dart';
import 'persona/guardrail.dart';
import 'persona/persona.dart';
import 'persona/persona_router.dart';
import 'roast/roast_engine.dart' as roast;
import 'runtime/ai_engine.dart';
import 'runtime/gemma_runtime.dart';
import 'runtime/llm_runtime.dart';
import 'runtime/template_only_runtime.dart';
import 'telemetry/ai_telemetry.dart';

// ── engine + manager ────────────────────────────────────────────

final Provider<AiInferenceEngine> aiEngineProvider =
    Provider<AiInferenceEngine>((Ref ref) => const PlatformAiInferenceEngine());

/// Total device RAM (MB) via our own `udao/platform` channel — the
/// same read-only surface the survival stack uses (deliberately NOT
/// device_info_plus, whose RAM field names drift between majors).
final FutureProvider<int> deviceRamMbProvider = FutureProvider<int>(
  (Ref ref) async {
    try {
      final Object? facts = await const MethodChannel(
        AppConstants.platformChannelName,
      ).invokeMethod<Object?>(AppConstants.platformDeviceInfoMethod);
      if (facts is Map) {
        final num? mb = facts['totalRamMb'] as num?;
        if (mb != null) {
          return mb.toInt();
        }
      }
    } on Object {
      // Channel down / old host — 0 = "unknown", tiering then picks
      // the conservative floor. Honest, never a guess.
    }
    return 0;
  },
);

/// ChangeNotifier-backed so the runtime selection (and the chat's
/// template-only banner) re-resolve the moment a model loads or
/// unloads.
final ChangeNotifierProvider<ModelManager> modelManagerProvider =
    ChangeNotifierProvider<ModelManager>(
  (Ref ref) => ModelManager(
    store: IoModelFileStore(
      documentsDir: () async =>
          (await getApplicationDocumentsDirectory()).path,
    ),
    kv: ref.watch(kvDaoProvider),
    engine: ref.watch(aiEngineProvider),
    totalRamMb: () => ref.watch(deviceRamMbProvider.future),
  ),
);

// ── runtimes ─────────────────────────────────────────────────────

final Provider<GemmaRuntime> gemmaRuntimeProvider = Provider<GemmaRuntime>(
  (Ref ref) => GemmaRuntime(engine: ref.watch(aiEngineProvider)),
);

/// The no-model roast floor (selection + fill + guardrail, no model
/// pass) — registered under 'roast' so a roast-shaped request NEVER
/// dies for want of a model.
final Provider<roast.RoastFloor> roastFloorProvider =
    Provider<roast.RoastFloor>(
  (Ref ref) => roast.RoastFloor(
    roasts: ref.watch(roastRepoProvider),
    kv: ref.watch(kvDaoProvider),
    guardrail: ref.watch(guardrailProvider),
  ),
);

final Provider<TemplateOnlyRuntime> templateOnlyRuntimeProvider =
    Provider<TemplateOnlyRuntime>((Ref ref) {
  final roast.RoastFloor floor = ref.watch(roastFloorProvider);
  return TemplateOnlyRuntime(
    responders: <String, TemplateResponder>{
      'roast': floor.roastResponder,
    },
  );
});

final Provider<roast.RoastEngine> roastEngineProvider =
    Provider<roast.RoastEngine>(
  (Ref ref) => roast.RoastEngine(
    runtime: ref.watch(llmRuntimeProvider),
    roasts: ref.watch(roastRepoProvider),
    kv: ref.watch(kvDaoProvider),
    guardrail: ref.watch(guardrailProvider),
  ),
);

/// The ACTIVE runtime: Gemma when a model is loaded, template-only
/// otherwise. The chat banner watches the model manager, not this.
final Provider<LlmRuntime> llmRuntimeProvider = Provider<LlmRuntime>(
  (Ref ref) {
    final ModelManager manager = ref.watch(modelManagerProvider);
    final GemmaRuntime gemma = ref.watch(gemmaRuntimeProvider);
    if (manager.isLoaded) {
      gemma.onModelLoaded(manager.state.candidate?.fileName ?? 'model');
      return gemma;
    }
    gemma.onModelUnloaded();
    return ref.watch(templateOnlyRuntimeProvider);
  },
);

// ── guardrail / telemetry / persona ──────────────────────────────

final Provider<Guardrail> guardrailProvider = Provider<Guardrail>(
  (Ref ref) => Guardrail(kv: ref.watch(kvDaoProvider)),
);

final Provider<AiTelemetry> aiTelemetryProvider = Provider<AiTelemetry>(
  (Ref ref) => AiTelemetry(kv: ref.watch(kvDaoProvider)),
);

final Provider<PersonaRouter> personaRouterProvider = Provider<PersonaRouter>(
  (Ref ref) => PersonaRouter(kv: ref.watch(kvDaoProvider)),
);

// ── agent ────────────────────────────────────────────────────────

final Provider<ToolContext> toolContextProvider = Provider<ToolContext>(
  (Ref ref) => ToolContext(
    txns: TxnDao(ref.watch(dbProvider).db),
    categories: ref.watch(categoryRepoProvider),
    budgets: ref.watch(budgetRepoProvider),
    subscriptions: ref.watch(subscriptionRepoProvider),
    streaks: ref.watch(streakRepoProvider),
    csv: CsvService(ref.watch(udaoDatabaseProvider)),
  ),
);

final Provider<List<AgentTool>> agentToolsProvider =
    Provider<List<AgentTool>>(
  (Ref ref) => buildAgentTools(ref.watch(toolContextProvider)),
);

final Provider<ContextBuilder> contextBuilderProvider =
    Provider<ContextBuilder>(
  (Ref ref) => ContextBuilder(
    txns: TxnDao(ref.watch(dbProvider).db),
    budgets: ref.watch(budgetRepoProvider),
    subscriptions: ref.watch(subscriptionRepoProvider),
    streaks: ref.watch(streakRepoProvider),
    roasts: ref.watch(roastRepoProvider),
    categories: ref.watch(categoryRepoProvider),
  ),
);

final Provider<AgentLoop> agentLoopProvider = Provider<AgentLoop>(
  (Ref ref) => AgentLoop(
    runtime: ref.watch(llmRuntimeProvider),
    tools: ref.watch(agentToolsProvider),
    buildContext: (Persona persona) =>
        ref.watch(contextBuilderProvider).build(persona: persona),
    telemetry: ref.watch(aiTelemetryProvider),
  ),
);

// ── LLM-fallback parser ──────────────────────────────────────────

final Provider<LlmFallbackParser> llmParserProvider =
    Provider<LlmFallbackParser>(
  (Ref ref) => LlmFallbackParser(runtime: ref.watch(llmRuntimeProvider)),
);

final Provider<LearnedPatternStore> learnedPatternStoreProvider =
    Provider<LearnedPatternStore>(
  (Ref ref) => LearnedPatternStore(kv: ref.watch(kvDaoProvider)),
);

final Provider<FallbackParseService> fallbackParseServiceProvider =
    Provider<FallbackParseService>(
  (Ref ref) => FallbackParseService(
    parser: ref.watch(llmParserProvider),
    reviews: ref.watch(pendingReviewRepoProvider),
    patterns: ref.watch(learnedPatternStoreProvider),
  ),
);
