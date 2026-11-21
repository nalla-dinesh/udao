// phase-06
// The LLM-fallback parser for unknown bank formats. Strict-JSON
// prompt with 5 few-shot corpus examples, confidence floor 0.65,
// and two honesty laws:
//   * it NEVER auto-inserts — output goes to the pending-review
//     queue (human approves);
//   * it proposes a learned-regex that the human must approve
//     before it ever parses anything.
import 'dart:convert';

import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';
import '../../../core/utils/money.dart';
import '../../../data/models/pending_review_entry.dart';
import '../../../data/models/txn.dart';
import '../../../data/repos/pending_review_repo.dart';
import '../runtime/llm_events.dart';
import '../runtime/llm_runtime.dart';
import 'learned_pattern.dart';

class LlmParseResult {
  const LlmParseResult({
    required this.direction,
    required this.amount,
    required this.merchant,
    required this.confidence,
    this.refNo,
  });

  final TxnDirection direction;
  final Money amount;
  final String merchant;
  final String? refNo;
  final double confidence;
}

class LlmFallbackParser {
  LlmFallbackParser({required LlmRuntime runtime})
      : _runtime = runtime;

  final LlmRuntime _runtime;

  static const double confidenceFloor = 0.65;

  /// Few-shot examples — REAL shapes from the phase-02 corpus, not
  /// invented ones (the phase-03 lesson: never feed fake ids/texts).
  static const List<String> fewShots = <String>[
    'Rs.450.00 debited from A/C XX4412 on 04-11-26 Ref 506711234 ATM WDL => '
        '{"direction":"debit","amount":450.00,"merchant":"ATM WDL","refNo":"506711234","confidence":0.95}',
    'Your Acct XX9987 credited Rs.12000.00 on 05-11-26 by NEFT-SALARY INFOTECH => '
        '{"direction":"credit","amount":12000.00,"merchant":"NEFT-SALARY INFOTECH","confidence":0.95}',
    'UPI/372045678901/Payment to Swiggy/Rs.289.50/Debited => '
        '{"direction":"debit","amount":289.50,"merchant":"Swiggy","refNo":"372045678901","confidence":0.9}',
    'Rs 1,250 spent on ICICI Card xx8891 at BIG BASKET on 03/11/26 => '
        '{"direction":"debit","amount":1250.00,"merchant":"BIG BASKET","confidence":0.9}',
    'Alert: You have made a Debit Card purchase of Rs.75.20 at DOMINOS in MUMBAI => '
        '{"direction":"debit","amount":75.20,"merchant":"DOMINOS","confidence":0.9}',
  ];

  /// Parses [rawText]. Err only for hard failures (model absent,
  /// invalid output, below confidence floor — the caller then keeps
  /// the existing pending-review behaviour, honestly).
  Future<Result<LlmParseResult>> parse(String rawText) async {
    if (!_runtime.isLoaded) {
      return const Err<LlmParseResult>(ModelFailure('model-absent'));
    }
    final StringBuffer buffer = StringBuffer();
    LlmError? error;
    await for (final LlmEvent event in _runtime.generate(
      LlmRequest(
        systemPrompt: _systemPrompt,
        prompt: rawText,
        temperature: 0.1,
        topK: 10,
        templateTag: 'parser',
      ),
    )) {
      if (event is LlmToken) {
        buffer.write(event.delta);
      } else if (event is LlmError) {
        error = event;
      }
    }
    if (error != null) {
      return Err<LlmParseResult>(error.failure);
    }
    final String? text = _firstJsonObject(buffer.toString());
    if (text == null) {
      return const Err<LlmParseResult>(ModelFailure('ai-invalid-output'));
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return const Err<LlmParseResult>(ModelFailure('ai-invalid-output'));
    }
    if (decoded is! Map<String, Object?>) {
      return const Err<LlmParseResult>(ModelFailure('ai-invalid-output'));
    }
    final num? amountNum = decoded['amount'] as num?;
    final String? merchant = decoded['merchant'] as String?;
    final String? direction = decoded['direction'] as String?;
    final double confidence = (decoded['confidence'] as num?)?.toDouble() ?? 0;
    if (amountNum == null || merchant == null || direction == null) {
      return const Err<LlmParseResult>(ModelFailure('ai-invalid-output'));
    }
    if (confidence < confidenceFloor) {
      return const Err<LlmParseResult>(ModelFailure('ai-low-confidence'));
    }
    return Ok<LlmParseResult>(
      LlmParseResult(
        direction: direction == 'credit'
            ? TxnDirection.credit
            : TxnDirection.debit,
        amount: Money((amountNum * 100).round()),
        merchant: merchant,
        refNo: decoded['refNo'] as String?,
        confidence: confidence,
      ),
    );
  }

  static String get _systemPrompt {
    final String examples = fewShots.join('\n');
    return 'You are a bank-SMS/notification parser. For each message '
        'reply with ONLY a JSON object: '
        '{"direction":"debit|credit","amount":number,'
        '"merchant":string,"refNo":string|null,"confidence":0.0-1.0}. '
        'Amount is in rupees (no currency symbols). Merchant is the '
        'counterparty. If you cannot parse the message, reply '
        '{"error":"unparseable"}.\nExamples:\n'
        '$examples';
  }

  /// First balanced JSON object in [text] (same discipline as the
  /// agent loop's extractor).
  static String? _firstJsonObject(String text) {
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
      if (ch == '\\' && inString) {
        escaped = true;
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
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }
}

/// One full fallback attempt: parse → (optionally) pending-queue
/// write + learned-regex proposal. Used by the AI-settings drain
/// and covered end-to-end in tests.
class FallbackParseService {
  FallbackParseService({
    required LlmFallbackParser parser,
    required PendingReviewRepo reviews,
    required LearnedPatternStore patterns,
  })  : _parser = parser,
        _reviews = reviews,
        _patterns = patterns;

  final LlmFallbackParser _parser;
  final PendingReviewRepo _reviews;
  final LearnedPatternStore _patterns;

  /// Attempts one pending entry. Returns the parse when it passed
  /// the floor; the entry is UPDATED (still pending — never
  /// auto-inserted) and a learned-regex is proposed.
  Future<Result<LlmParseResult>> tryEntry(
    PendingReviewEntry entry, {
    required DateTime now,
  }) async {
    final Result<LlmParseResult> parsed =
        await _parser.parse(entry.rawText);
    final LlmParseResult? result = parsed.valueOrNull;
    if (result == null) {
      return parsed;
    }

    // Update the pending entry with the model's read — a human still
    // approves it in review.
    final PendingReviewEntry updated = PendingReviewEntry(
      id: entry.id,
      source: entry.source,
      receivedAt: entry.receivedAt,
      rawText: entry.rawText,
      confidence: result.confidence,
      amount: result.amount,
      direction: result.direction,
      merchantRaw: result.merchant,
      merchantClean: result.merchant,
      bankOrApp: entry.bankOrApp,
      refNo: result.refNo,
      vpa: entry.vpa,
      parserId: 'llm-fallback',
      dedupKey: entry.dedupKey,
    );
    final Result<String> wrote = await _reviews.updateEntry(updated);
    if (wrote.isErr) {
      return Err<LlmParseResult>(wrote.failureOrNull!);
    }

    // Propose the learned regex (human approves in Settings).
    final String proposal = LearnedPattern.build(
      sample: entry.rawText,
      amount: _amountLiteral(entry.rawText, result.amount),
      merchant: result.merchant,
      refNo: result.refNo,
    );
    await _patterns.propose(pattern: proposal, sample: entry.rawText, now: now);

    return parsed;
  }

  /// Best-effort amount literal for pattern building: the rupees
  /// text as it appears in the raw message.
  static String? _amountLiteral(String rawText, Money amount) {
    final String whole = amount.wholeRupees.toString();
    if (rawText.contains(whole)) {
      return whole;
    }
    return null;
  }

  /// AI-settings drain: up to [limit] low-confidence pending entries
  /// per open (battery honesty — the model is not a free tap).
  Future<int> drainPending({int limit = 3}) async {
    if (!_parserWorks) {
      return 0;
    }
    final Result<List<PendingReviewEntry>> pending =
        await _reviews.pending(limit: 50);
    final List<PendingReviewEntry> candidates = (pending.valueOrNull ??
            const <PendingReviewEntry>[])
        .where((PendingReviewEntry e) => e.amount == null)
        .take(limit)
        .toList(growable: false);
    int done = 0;
    for (final PendingReviewEntry entry in candidates) {
      final Result<LlmParseResult> r = await tryEntry(
        entry,
        now: DateTime.now(),
      );
      if (r.isOk) {
        done++;
      }
    }
    return done;
  }

  bool get _parserWorks => true;
}
