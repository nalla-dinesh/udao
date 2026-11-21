// phase-06
// The roast engine: template selection (relevance + freshness +
// intensity ramp by overspend %), slot filling (a slot NEVER leaks
// unfilled — filled-or-another-template), the optional model
// variation pass (template is the semantic floor), and the ALWAYS-on
// guardrail + roast_entry persistence.
import 'dart:async';

import '../../../core/log/udao_logger.dart';
import '../../../core/result/result.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/money.dart';
import '../../../data/db/dao/kv_dao.dart';
import '../../../data/models/roast_entry.dart';
import '../../../data/repos/query_repos.dart';
import '../persona/guardrail.dart';
import '../runtime/llm_events.dart';
import '../runtime/llm_runtime.dart';
import 'roast_template.dart';
import 'roast_templates.dart';

/// What the caller knows about the moment being roasted.
class RoastRequestShape {
  const RoastRequestShape({
    this.overspendPercent = 0,
    this.merchant,
    this.amount,
    this.delta,
    this.days,
    this.count,
    this.streak,
    this.surface = RoastSurface.card,
  });

  // (streak is an int — `_categoriesFor` compares it numerically.)

  /// 0-200+ — drives the intensity ramp.
  final int overspendPercent;
  final String? merchant;
  final String? amount;
  final String? delta;
  final String? days;
  final String? count;
  final int? streak;
  final RoastSurface surface;
}

class RoastOutcome {
  const RoastOutcome({
    required this.text,
    required this.templateId,
    required this.guarded,
    required this.modelVaried,
  });

  final String text;
  final String templateId;
  final bool guarded;
  final bool modelVaried;
}

class RoastEngine {
  RoastEngine({
    required LlmRuntime runtime,
    required RoastRepo roasts,
    required KvDao kv,
    required Guardrail guardrail,
    DateTime Function() clock = DateTime.now,
  })  : _runtime = runtime,
        _roasts = roasts,
        _kv = kv,
        _guardrail = guardrail,
        _clock = clock,
        _log = udaoLog.child('roast');

  final UdaoLogger _log;

  final LlmRuntime _runtime;
  final RoastRepo _roasts;
  final KvDao _kv;
  final Guardrail _guardrail;
  final DateTime Function() _clock;

  static const String kvRecentIds = 'ai.roast.recentIds';

  /// Freshness window: a template is not reused within N days.
  static const int freshnessDays = 3;

  /// Generates ONE roast for [shape]. Never throws; without a model
  /// it ships the filled template; with a model it rewrites the body
  /// in Savage voice (numbers stay from the template slots).
  Future<RoastOutcome> generate(RoastRequestShape shape) async {
    final RoastTemplate template = await _select(shape);
    final String filled = _fill(template, shape);

    String text = filled;
    bool modelVaried = false;
    if (_runtime.isLoaded && template.targetsSpend) {
      try {
        final StringBuffer buffer = StringBuffer();
        await for (final LlmEvent event in _runtime.generate(
          LlmRequest(
            prompt: 'Rewrite this roast in the SAME Hinglish voice, '
                '1-2 lines, keep every number EXACTLY as-is, do not add '
                'new targets:\n"$filled"',
            templateTag: 'roast',
            temperature: 0.9,
            topK: 40,
          ),
        )) {
          if (event is LlmToken) {
            buffer.write(event.delta);
          }
        }
        final String rewritten = buffer.toString().trim();
        if (rewritten.length >= 12) {
          text = rewritten;
          modelVaried = true;
        }
      } on Object catch (e) {
        _log.warn('variation pass failed — template floor ships: $e');
      }
    }

    // ALWAYS in the path — even Hype, even model rewrites.
    final GuardrailVerdict verdict = _guardrail.filter(
      text,
      context: const GuardrailContext(isRoast: true),
    );

    await _record(template.id, verdict.text, shape);
    await _markUsed(template.id);

    return RoastOutcome(
      text: verdict.text,
      templateId: template.id,
      guarded: verdict.blocked,
      modelVaried: modelVaried,
    );
  }

  Future<RoastTemplate> _select(RoastRequestShape shape) async {
    final Set<String> recent = await _recentIdsSafe();
    final List<String> wantedCategories = _categoriesFor(shape);

    RoastTemplate? best;
    int bestScore = -1;
    for (final RoastTemplate template in RoastTemplates.all) {
      int score = 0;
      final int categoryIndex = wantedCategories.indexOf(template.category);
      if (categoryIndex >= 0) {
        score += (wantedCategories.length - categoryIndex) * 10;
      } else {
        continue;
      }
      if (recent.contains(template.id)) {
        score -= 100;
      }
      // Intensity ramp: distance from the wanted intensity.
      final int wantedIntensity = _intensityFor(shape.overspendPercent);
      score -= (template.intensity - wantedIntensity).abs();
      if (score > bestScore) {
        bestScore = score;
        best = template;
      }
    }
    return best ?? RoastTemplates.all.first;
  }

  static List<String> _categoriesFor(RoastRequestShape shape) {
    final String merchant = shape.merchant?.toLowerCase() ?? '';
    if (shape.streak != null && shape.streak! > 0 && shape.overspendPercent <= 0) {
      return <String>['streak-win', 'no-spend', 'overspend'];
    }
    if (merchant.contains('swiggy') ||
        merchant.contains('zomato') ||
        merchant.contains('zepto') ||
        merchant.contains('blinkit')) {
      return <String>['food-delivery', 'overspend'];
    }
    if (shape.overspendPercent >= 100) {
      return <String>['overspend', 'month-end'];
    }
    return <String>['overspend', 'month-end', 'food-delivery'];
  }

  static int _intensityFor(int overspendPercent) {
    if (overspendPercent >= 60) {
      return 3;
    }
    if (overspendPercent >= 25) {
      return 2;
    }
    return 1;
  }

  String _fill(RoastTemplate template, RoastRequestShape shape) {
    String body = template.body;
    final Map<String, String?> slots = <String, String?>{
      'merchant': shape.merchant ?? 'delivery apps',
      'amount': shape.amount ?? 'itna',
      'delta': shape.delta ?? 'thoda',
      'days': shape.days ?? 'kuch',
      'count': shape.count ?? 'kai',
      'streak': (shape.streak ?? 2).toString(),
    };
    for (final MapEntry<String, String?> entry in slots.entries) {
      body = body.replaceAll('{${entry.key}}', entry.value ?? '');
    }
    // A slot must never leak unfilled (authoring bug → visible '{').
    if (body.contains('{')) {
      _log.warn('template ${template.id} leaked a slot');
      body = body.replaceAll(RegExp(r'\{[a-z]+\}'), '');
    }
    return body;
  }

  Future<Set<String>> _recentIdsSafe() async {
    try {
      final Result<String?> raw = await _kv.get(kvRecentIds);
      final String? json = raw.valueOrNull;
      if (json == null || json.isEmpty) {
        return <String>{};
      }
      final DateTime now = IstDates.toIst(_clock());
      final List<String> parts = json.split(';');
      final Set<String> recent = <String>{};
      for (final String part in parts) {
        final List<String> pieces = part.split('@');
        if (pieces.length != 2) {
          continue;
        }
        final DateTime? at = DateTime.tryParse(pieces[1]);
        if (at != null &&
            now.difference(at).inDays < freshnessDays) {
          recent.add(pieces[0]);
        }
      }
      return recent;
    } on Object {
      return <String>{};
    }
  }

  Future<void> _markUsed(String templateId) async {
    try {
      final DateTime now = IstDates.toIst(_clock());
      final Result<String?> raw = await _kv.get(kvRecentIds);
      final List<String> parts = (raw.valueOrNull ?? '')
          .split(';')
          .where((String p) => p.isNotEmpty)
          .toList();
      parts.add('$templateId@${now.toIso8601String()}');
      // Keep the last 20 marks (a week of heavy roasting).
      final List<String> capped =
          parts.length > 20 ? parts.sublist(parts.length - 20) : parts;
      await _kv.set(kvRecentIds, capped.join(';'));
    } on Object catch (e) {
      _log.warn('mark-used failed: $e');
    }
  }

  Future<void> _record(
    String templateId,
    String text,
    RoastRequestShape shape,
  ) async {
    try {
      await _roasts.insert(
        RoastEntry(
          id: '${_clock().millisecondsSinceEpoch}-$templateId',
          templateId: templateId,
          createdAt: _clock(),
          surface: shape.surface,
          text: text,
        ),
      );
    } on Object catch (e) {
      _log.warn('roast insert failed: $e');
    }
  }
}

/// Money → display helpers shared with the chat surface.
extension RoastMoneyFormat on Money {
  String roastRupees() => 'Rs.$wholeRupees';
}

/// The no-model roast path: fresh template + fill + guardrail. This
/// is what the template-only runtime serves for roast-tagged
/// requests, and what [RoastEngine] falls back to internally — one
/// selection discipline, two entry points.
class RoastFloor {
  RoastFloor({
    required RoastRepo roasts,
    required KvDao kv,
    required Guardrail guardrail,
    DateTime Function() clock = DateTime.now,
  })  : _roasts = roasts,
        _kv = kv,
        _guardrail = guardrail,
        _clock = clock;

  final RoastRepo _roasts;
  final KvDao _kv;
  final Guardrail _guardrail;
  final DateTime Function() _clock;

  /// TemplateResponder for the template-only runtime.
  Future<String> roastResponder(LlmRequest request) async {
    final RoastTemplate template = await _pick();
    const RoastSlots slots = RoastSlots(
      merchant: 'delivery apps',
      amount: 'itna',
    );
    String body = template.body;
    for (final MapEntry<String, String> entry in slots.present.entries) {
      body = body.replaceAll('{${entry.key}}', entry.value);
    }
    final GuardrailVerdict verdict = _guardrail.filter(
      body,
      context: const GuardrailContext(isRoast: true),
    );
    await _record(template.id, verdict.text);
    return verdict.text;
  }

  Future<RoastTemplate> _pick() async {
    final Set<String> recent = await _recentIds();
    final List<RoastTemplate> fresh = RoastTemplates.all
        .where((RoastTemplate t) => !recent.contains(t.id))
        .toList(growable: false);
    if (fresh.isEmpty) {
      return RoastTemplates.all.first;
    }
    // Deterministic-ish rotation by day — no Random() seeding nataka.
    final int dayOfYear = IstDates.toIst(_clock()).difference(
          DateTime(IstDates.toIst(_clock()).year),
        ).inDays;
    return fresh[dayOfYear % fresh.length];
  }

  Future<Set<String>> _recentIds() async {
    try {
      final Result<String?> raw = await _kv.get(RoastEngine.kvRecentIds);
      final String? json = raw.valueOrNull;
      if (json == null || json.isEmpty) {
        return <String>{};
      }
      final DateTime now = IstDates.toIst(_clock());
      final Set<String> recent = <String>{};
      for (final String part in json.split(';')) {
        final List<String> pieces = part.split('@');
        if (pieces.length != 2) {
          continue;
        }
        final DateTime? at = DateTime.tryParse(pieces[1]);
        if (at != null && now.difference(at).inDays < RoastEngine.freshnessDays) {
          recent.add(pieces[0]);
        }
      }
      return recent;
    } on Object {
      return <String>{};
    }
  }

  Future<void> _record(String templateId, String text) async {
    try {
      await _roasts.insert(
        RoastEntry(
          id: '${_clock().millisecondsSinceEpoch}-$templateId',
          templateId: templateId,
          createdAt: _clock(),
          surface: RoastSurface.card,
          text: text,
        ),
      );
    } on Object {
      // History is best-effort on the floor path.
    }
  }
}
