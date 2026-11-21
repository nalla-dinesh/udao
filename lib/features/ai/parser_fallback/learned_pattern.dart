// phase-06
// Learned-regex proposals: when the LLM-fallback parser reads an
// unknown bank format, it proposes a regex that would have matched
// it structurally. Proposals live in kv behind a human-approve flag
// — nothing a model produced ever enters the parse chain silently.
import 'dart:convert';

import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';
import '../../../data/db/dao/kv_dao.dart';

abstract final class LearnedPattern {
  static const String kvStore = 'ai.learnedPatterns';

  /// Escapes every regex metacharacter in [literal].
  ///
  /// NOTE: Dart's `replaceAll` does NOT expand `\$0` in the
  /// replacement (that's Java/JS semantics) — group references need
  /// `replaceAllMapped`. The `r'\$0'` version shipped literal
  /// backslash-dollar-zero and silently broke every built pattern.
  static String escapeLiteral(String literal) =>
      literal.replaceAllMapped(
        RegExp(r'[.*+?^${}()|[\]\\]'),
        (Match m) => '\\${m[0]}',
      );

  /// Builds a candidate pattern from [sample] and the literals the
  /// model extracted. Fixed parts stay escaped literals; extracted
  /// parts become typed groups:
  ///   amount   → (?<amount>[\d,]+(?:\.\d{1,2})?)
  ///   merchant → (?<merchant>[A-Za-z0-9&. ]{2,40}?)
  ///   refNo    → (?<ref>[A-Z0-9]{6,20})
  static String build({
    required String sample,
    String? amount,
    String? merchant,
    String? refNo,
  }) {
    String pattern = escapeLiteral(sample);
    // replaceFirst: a literal appearing twice must not produce two
    // same-named groups (two (?<amount>...) would not compile).
    if (amount != null && sample.contains(amount)) {
      pattern = pattern.replaceFirst(
        escapeLiteral(amount),
        r'(?<amount>[\d,]+(?:\.\d{1,2})?)',
      );
    }
    if (merchant != null && merchant.isNotEmpty && sample.contains(merchant)) {
      pattern = pattern.replaceFirst(
        escapeLiteral(merchant),
        r'(?<merchant>[A-Za-z0-9&. ]{2,40}?)',
      );
    }
    if (refNo != null && refNo.isNotEmpty && sample.contains(refNo)) {
      pattern = pattern.replaceFirst(
        escapeLiteral(refNo),
        r'(?<ref>[A-Z0-9]{6,20})',
      );
    }
    // `.*$` stays RAW — a non-raw trailing `$` is a literal dollar
    // and would anchor the pattern to a `$` character (never matches).
    return '^.*$pattern' r'.*$';
  }

  /// Validates that a candidate actually compiles AND matches its
  /// own sample (the Settings test button runs exactly this).
  static bool testPattern(String pattern, String sample) {
    try {
      return RegExp(pattern).hasMatch(sample);
    } on FormatException {
      return false;
    }
  }
}

class LearnedPatternEntry {
  const LearnedPatternEntry({
    required this.id,
    required this.pattern,
    required this.sample,
    required this.createdAtMs,
    required this.approved,
  });

  final String id;
  final String pattern;

  /// The sample it was learned from (shown in the approval row —
  /// the human must see what they are approving).
  final String sample;
  final int createdAtMs;
  final bool approved;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'pattern': pattern,
        'sample': sample,
        'createdAtMs': createdAtMs,
        'approved': approved,
      };

  static LearnedPatternEntry fromJson(Map<Object?, Object?> json) =>
      LearnedPatternEntry(
        id: json['id'] as String? ?? '',
        pattern: json['pattern'] as String? ?? '',
        sample: json['sample'] as String? ?? '',
        createdAtMs: json['createdAtMs'] as int? ?? 0,
        approved: json['approved'] as bool? ?? false,
      );
}

class LearnedPatternStore {
  LearnedPatternStore({required KvDao kv}) : _kv = kv;

  final KvDao _kv;

  Future<Result<List<LearnedPatternEntry>>> all() async {
    final Result<String?> raw = await _kv.get(LearnedPattern.kvStore);
    final String? json = raw.valueOrNull;
    if (json == null || json.isEmpty) {
      return const Ok<List<LearnedPatternEntry>>(<LearnedPatternEntry>[]);
    }
    try {
      final List<Object?> decoded = jsonDecode(json) as List<Object?>;
      return Ok<List<LearnedPatternEntry>>(
        decoded
            .map((Object? e) => LearnedPatternEntry.fromJson(e! as Map))
            .toList(growable: false),
      );
    } on FormatException catch (e) {
      return Err<List<LearnedPatternEntry>>(
        ParseFailure('learned-patterns json', cause: e),
      );
    }
  }

  Future<Result<LearnedPatternEntry>> propose({
    required String pattern,
    required String sample,
    required DateTime now,
  }) async {
    final entry = LearnedPatternEntry(
      id: 'lp-${now.microsecondsSinceEpoch}',
      pattern: pattern,
      sample: sample,
      createdAtMs: now.millisecondsSinceEpoch,
      approved: false,
    );
    final Result<List<LearnedPatternEntry>> current = await all();
    final List<LearnedPatternEntry> list =
        List<LearnedPatternEntry>.of(current.valueOrNull ?? <LearnedPatternEntry>[]);
    // Same pattern twice → no duplicate row.
    if (list.any((LearnedPatternEntry e) => e.pattern == pattern)) {
      return Ok<LearnedPatternEntry>(entry);
    }
    list.add(entry);
    final Result<void> saved = await _save(list);
    return saved.isErr
        ? Err<LearnedPatternEntry>(saved.failureOrNull!)
        : Ok<LearnedPatternEntry>(entry);
  }

  Future<Result<void>> approve(String id) async =>
      _mutate(id, approved: true);

  Future<Result<void>> dismiss(String id) async {
    final Result<List<LearnedPatternEntry>> current = await all();
    final List<LearnedPatternEntry> list = (current.valueOrNull ?? <LearnedPatternEntry>[])
        .where((LearnedPatternEntry e) => e.id != id)
        .toList(growable: false);
    return _save(list);
  }

  Future<Result<void>> _mutate(String id, {required bool approved}) async {
    final Result<List<LearnedPatternEntry>> current = await all();
    final List<LearnedPatternEntry> list =
        (current.valueOrNull ?? <LearnedPatternEntry>[]).map(
      (LearnedPatternEntry e) =>
          e.id == id ? _copyWithApproved(e, approved) : e,
    ).toList(growable: false);
    return _save(list);
  }

  static LearnedPatternEntry _copyWithApproved(
    LearnedPatternEntry e,
    bool approved,
  ) =>
      LearnedPatternEntry(
        id: e.id,
        pattern: e.pattern,
        sample: e.sample,
        createdAtMs: e.createdAtMs,
        approved: approved,
      );

  Future<Result<void>> _save(List<LearnedPatternEntry> list) async {
    return _kv.set(
      LearnedPattern.kvStore,
      jsonEncode(list.map((LearnedPatternEntry e) => e.toJson()).toList()),
    );
  }
}
