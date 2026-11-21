// phase-06
// RoastEngine: relevance/freshness/intensity selection, slot fill,
// model-variation pass, guardrail-in-path, history recording; and
// the RoastFloor day-rotation used by the template-only runtime.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/roast_entry.dart';
import 'package:udao/data/repos/query_repos.dart';
import 'package:udao/features/ai/persona/guardrail.dart';
import 'package:udao/features/ai/roast/roast_engine.dart';
import 'package:udao/features/ai/roast/roast_template.dart';
import 'package:udao/features/ai/roast/roast_templates.dart';
import 'package:udao/features/ai/runtime/llm_events.dart';

import '../../data/db/test_db.dart' as helper;
import 'fake_llm_runtime.dart';

void main() {
  late UdaoDatabase db;
  final DateTime now = DateTime(2026, 10, 30, 11);

  setUp(() async {
    db = await helper.createTestDb();
  });
  tearDown(() async {
    await helper.disposeTestDb(db);
  });

  RoastEngine engineOf(ScriptedRuntime? rt) => RoastEngine(
        runtime: rt ?? ScriptedRuntime(const <List<LlmEvent>>[]),
        roasts: RoastRepo(db),
        kv: KvDao(db.db),
        guardrail: Guardrail(),
        clock: () => now,
      );

  test('food merchant selects a food-delivery template, slots filled',
      () async {
    final RoastOutcome out = await engineOf(null).generate(
      const RoastRequestShape(
        overspendPercent: 30,
        merchant: 'Swiggy',
        amount: 'Rs.640',
        delta: 'Rs.300',
        surface: RoastSurface.full,
      ),
    );
    expect(out.templateId, startsWith('food-'));
    expect(out.text, contains('Rs.640'));
    expect(out.text, isNot(contains('{')));
    expect(out.modelVaried, isFalse, reason: 'runtime not loaded');
    expect(out.guarded, isFalse);
  });

  test('big overspend prefers overspend templates', () async {
    final RoastOutcome out = await engineOf(null).generate(
      const RoastRequestShape(overspendPercent: 150, amount: 'Rs.9000'),
    );
    expect(out.templateId, startsWith('overspend-'));
  });

  test('win moment (streak, no overspend) selects a win template',
      () async {
    final RoastOutcome out = await engineOf(null).generate(
      const RoastRequestShape(streak: 12, overspendPercent: 0),
    );
    final RoastTemplate chosen = RoastTemplates.all
        .firstWhere((RoastTemplate t) => t.id == out.templateId);
    expect(
      <String>['streak-win', 'no-spend'],
      contains(chosen.category),
    );
    expect(out.text, contains('12'));
  });

  test('freshness: the just-used template is not served again soon',
      () async {
    final RoastEngine engine = engineOf(null);
    final RoastOutcome first = await engine.generate(
      const RoastRequestShape(overspendPercent: 30, merchant: 'Swiggy'),
    );
    bool moved = false;
    for (int i = 0; i < 6; i++) {
      final RoastOutcome next = await engine.generate(
        const RoastRequestShape(overspendPercent: 30, merchant: 'Swiggy'),
      );
      if (next.templateId != first.templateId) {
        moved = true;
      }
    }
    expect(
      moved,
      isTrue,
      reason: '−100 freshness must rotate off the first pick',
    );
  });

  test('model-variation pass rewrites when a model is loaded',
      () async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('Arre Swiggy pe Rs.640? Bank ka bhi banta hai ab.'),
        const LlmDone(
          LlmUsage(promptChars: 20, outputChars: 40, elapsedMs: 12),
        ),
      ],
    ])
      ..loaded = true;
    final RoastOutcome out = await engineOf(rt).generate(
      const RoastRequestShape(
        overspendPercent: 30,
        merchant: 'Swiggy',
        amount: 'Rs.640',
      ),
    );
    expect(out.modelVaried, isTrue);
    expect(out.text, contains('Rs.640'));
    rt.dispose();
  });

  test('a too-short rewrite is rejected (template floor ships)',
      () async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('haan'),
        const LlmDone(
          LlmUsage(promptChars: 5, outputChars: 4, elapsedMs: 2),
        ),
      ],
    ])
      ..loaded = true;
    final RoastOutcome out = await engineOf(rt).generate(
      const RoastRequestShape(overspendPercent: 30, merchant: 'Swiggy'),
    );
    expect(out.modelVaried, isFalse);
    rt.dispose();
  });

  test('guardrail is ALWAYS in the path (blocked rewrite → safe text)',
      () async {
    final ScriptedRuntime rt = ScriptedRuntime(<List<LlmEvent>>[
      <LlmEvent>[
        const LlmToken('Tu barbaad hai — Swiggy pe Rs.640?'),
        const LlmDone(
          LlmUsage(promptChars: 20, outputChars: 30, elapsedMs: 9),
        ),
      ],
    ])
      ..loaded = true;
    final RoastOutcome out = await engineOf(rt).generate(
      const RoastRequestShape(
        overspendPercent: 30,
        merchant: 'Swiggy',
        amount: 'Rs.640',
      ),
    );
    expect(out.modelVaried, isTrue);
    expect(out.guarded, isTrue);
    expect(out.text, isNot(contains('barbaad')));
    rt.dispose();
  });

  test('every generate records a roast_entry + marks used', () async {
    await engineOf(null)
        .generate(const RoastRequestShape(merchant: 'Zomato'));
    final List<RoastEntry> recent =
        (await RoastRepo(db).recent(limit: 5)).valueOrNull ??
            <RoastEntry>[];
    expect(recent, isNotEmpty);
    expect(recent.first.templateId, startsWith('food-'));
    expect(recent.first.surface, RoastSurface.card);
  });

  test('RoastFloor serves guardrail-clean, slot-filled text', () async {
    final RoastFloor floor = RoastFloor(
      roasts: RoastRepo(db),
      kv: KvDao(db.db),
      guardrail: Guardrail(),
      clock: () => now,
    );
    final String text = await floor.roastResponder(
      const LlmRequest(prompt: 'roast me', templateTag: 'roast'),
    );
    expect(text, isNotEmpty);
    expect(text, isNot(contains('{')));
    expect(
      Guardrail()
          .filter(text, context: const GuardrailContext(isRoast: true))
          .blocked,
      isFalse,
    );
    final List<RoastEntry> recent =
        (await RoastRepo(db).recent(limit: 3)).valueOrNull ??
            <RoastEntry>[];
    expect(recent, isNotEmpty);
  });
}
