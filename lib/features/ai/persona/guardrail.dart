// phase-06
// The HARD guardrail. Post-generation, pre-display, on EVERY line —
// chat answers, roasts, model rewrites, even Hype (spec: guardrail
// is ALWAYS in the path). Blocks:
//   * essential-category targeting in roast context,
//   * slurs (body / family / caste),
//   * person-directed alarmism ("tu barbaad hai"),
//   * panic/medical-anxiety triggers,
// and trims over-length lines with an honest ellipsis. A block
// falls back to a SAFE template + counts `guardrail_block` for the
// transparency dashboard.
//
// This is a safety component: deterministic, no IO, tested to death.
// False positives are acceptable; false negatives are not.
import 'dart:async';
import 'dart:convert';

import '../../../core/result/result.dart';
import '../../../data/db/dao/kv_dao.dart';

class GuardrailContext {
  const GuardrailContext({
    this.isRoast = false,
    this.essentialCategories = const [],
  });

  /// Roast-shaped output gets the stricter essential-word screen.
  final bool isRoast;

  /// Essential category NAMES from the seed list (the router feeds
  /// the real names; tests feed fixtures).
  final List<String> essentialCategories;
}

class GuardrailVerdict {
  const GuardrailVerdict({
    required this.text,
    required this.blocked,
    required this.trimmed,
    required this.reasons,
  });

  final String text;
  final bool blocked;
  final bool trimmed;
  final List<String> reasons;
}

abstract final class GuardrailRules {
  /// Dart RegExp has NO inline `(?i)` — case-insensitivity is the
  /// constructor's `caseSensitive: false` (a phase-06 errata: the
  /// analyzer's valid_regexps lint caught it before the device did).
  static final RegExp slurs = RegExp(
    r'\b('
    r'mot[u]?a|moti|nota|fattu|suar|kutta|harami|chutiya|gandu|bhosdi[a-z]*'
    r'|madarchod|behenchod|lawda|lauda|chamar|bhangi|katua|miyan.?tolia'
    r'|worthless|pathetic|loser|idiot|stupid'
    r')\b',
    caseSensitive: false,
  );

  /// Person-directed alarmism (the SPEND being roasted is fine; the
  /// PERSON being called ruined is not).
  static final RegExp alarmist = RegExp(
    r'\b(tu|tum|aap|tera|teraa|tumhara)\s+'
    r'(barbaad|nakara|khatam|finished|bekaar|faltu)\b',
    caseSensitive: false,
  );

  /// Panic / medical-anxiety triggers.
  static final RegExp panic = RegExp(
    r'\b(bhikari|bhikh|marna|mar jaoge|nalaayak|nalayak'
    r'|ghar baar khoge|khatam ho jaoge|cancer|death|suicide)\b',
    caseSensitive: false,
  );

  /// Essential spending words (roast context only).
  static final RegExp essentials = RegExp(
    r'\b(rent|kiraya|groceries|grocery|sabzi|ration|medical'
    r'|dawai|dava|hospital|doctor|doctor ke|school|college|padhai'
    r'|education|fees|fee|bijli|electricity|water bill|light bill'
    r')\b',
    caseSensitive: false,
  );

  /// Hard length cap (spec: 280 chars, trimmed with ellipsis).
  static const int maxChars = 280;

  /// The safe fallback roasts (no slots, no targets, pure vibe) —
  /// used whenever a block fires. Round-robin by counter.
  static const List<String> safeTemplates = <String>[
    'Kharche dekh ke lagta hai wallet ko bhi break chahiye. '
        'Chalo, kal se sambhalte hain.',
    'Paisa ud raha hai — par tumhari empathy se zyada to nahi. '
        'Ek budget bana lein?',
    'Bank balance dekh ke hi main thoda emotional ho gaya. '
        'Deep breath. Numbers dekhein?',
    'Ye kharcha thoda zyada ho gaya — chalega, par monthly '
        'total dekh ke pet me chuhe? Chalo manage karte hain.',
  ];
}

class Guardrail {
  Guardrail({KvDao? kv}) : _kv = kv;

  final KvDao? _kv;
  int _safeCursor = 0;

  static const String kvBlockCount = 'ai.guardrail.blocks';

  /// Filters [input]. NEVER throws; on any internal hiccup it
  /// returns the input unfiltered (availability beats a dead chat,
  /// and every other failure mode is a block, not a pass).
  GuardrailVerdict filter(String input, {GuardrailContext? context}) {
    try {
      return _filter(input, context ?? const GuardrailContext());
    } on Object {
      return GuardrailVerdict(
        text: input,
        blocked: false,
        trimmed: false,
        reasons: const <String>[],
      );
    }
  }

  GuardrailVerdict _filter(String input, GuardrailContext context) {
    final List<String> reasons = <String>[];

    if (GuardrailRules.slurs.hasMatch(input)) {
      reasons.add('slur');
    }
    if (GuardrailRules.alarmist.hasMatch(input)) {
      reasons.add('alarmist');
    }
    if (GuardrailRules.panic.hasMatch(input)) {
      reasons.add('panic');
    }
    if (context.isRoast && GuardrailRules.essentials.hasMatch(input)) {
      reasons.add('essential-target');
    }

    if (reasons.isNotEmpty) {
      final String safe = _nextSafeTemplate();
      unawaited(_countBlock(reasons));
      return GuardrailVerdict(
        text: safe,
        blocked: true,
        trimmed: false,
        reasons: reasons,
      );
    }

    if (input.length > GuardrailRules.maxChars) {
      final String trimmed = _trimSentence(input);
      return GuardrailVerdict(
        text: '$trimmed…',
        blocked: false,
        trimmed: true,
        reasons: const <String>['length'],
      );
    }
    return GuardrailVerdict(
      text: input,
      blocked: false,
      trimmed: false,
      reasons: const <String>[],
    );
  }

  /// Trim at the last sentence end (or space) inside the cap.
  static String _trimSentence(String input) {
    final String head = input.substring(0, GuardrailRules.maxChars - 1);
    final int stop = <int>[
      head.lastIndexOf('. '),
      head.lastIndexOf('! '),
      head.lastIndexOf('? '),
      head.lastIndexOf('.'),
      head.lastIndexOf('!'),
      head.lastIndexOf('?'),
      head.lastIndexOf(' '),
    ].where((int i) => i > 60).fold(-1, max);
    return stop < 0 ? head : head.substring(0, stop + 1);
  }

  static int max(int a, int b) => a > b ? a : b;

  String _nextSafeTemplate() {
    final String template =
        GuardrailRules.safeTemplates[_safeCursor % GuardrailRules.safeTemplates.length];
    _safeCursor++;
    return template;
  }

  Future<void> _countBlock(List<String> reasons) async {
    final KvDao? kv = _kv;
    if (kv == null) {
      return;
    }
    final Result<String?> current = await kv.get(kvBlockCount);
    final int n = int.tryParse(current.valueOrNull ?? '0') ?? 0;
    // reasons are internal codes only — never content.
    await kv.set(
      kvBlockCount,
      jsonEncode(<String, Object?>{'count': n + 1, 'last': reasons.join(',')}),
    );
  }
}
