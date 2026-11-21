// phase-06
// The model leg of the receipt ensemble: image → Gemma-3n vision
// (via the MediaPipe seam) → structured JSON → [ParsedReceipt].
// Fails CLOSED with Err('model-absent') whenever no model is
// loaded — the ensemble then shows the human-confirm form with
// whatever the rules leg found (receipts are always human-confirmed
// anyway; the spec).
//
// TODO-VERIFY(local): actual model behavior against a real
// gemma-3n .task file (JSON discipline of the model, vision
// quality). The wiring, prompts, validation and fallbacks are
// complete and tested.
import 'dart:convert';

import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';
import '../../../core/utils/money.dart';
import '../../ai/runtime/llm_events.dart';
import '../../ai/runtime/llm_runtime.dart';
import 'receipt_parsed.dart';
import 'receipt_parser.dart';

class GemmaVisionParser implements ReceiptModelParser {
  GemmaVisionParser({required LlmRuntime runtime}) : _runtime = runtime;

  final LlmRuntime _runtime;

  static const String _prompt = 'This is a shop receipt. Extract: '
      'merchant name, grand total (rupees), date (YYYY-MM-DD), and '
      'up to 3 line items with prices. Reply ONLY as JSON: '
      '{"merchant":string|null,"total":number|null,'
      '"date":string|null,'
      '"items":[{"name":string,"price":number}]}. '
      'Use null for anything you cannot read.';

  @override
  Future<Result<ParsedReceipt>> parseImage(String imagePath) async {
    if (!_runtime.isLoaded) {
      return const Err<ParsedReceipt>(ModelFailure('model-absent'));
    }
    final StringBuffer buffer = StringBuffer();
    LlmError? error;
    await for (final LlmEvent event in _runtime.generate(
      LlmRequest(
        prompt: _prompt,
        temperature: 0.1,
        topK: 10,
        imagePath: imagePath,
      ),
    )) {
      if (event is LlmToken) {
        buffer.write(event.delta);
      } else if (event is LlmError) {
        error = event;
      }
    }
    if (error != null) {
      return Err<ParsedReceipt>(error.failure);
    }
    return _decode(buffer.toString());
  }

  /// Package-visible for tests (deterministic decoding, no model).
  Result<ParsedReceipt> decodeText(String text) => _decode(text);

  Result<ParsedReceipt> _decode(String text) {
    final String? json = _firstJsonObject(text);
    if (json == null) {
      return const Err<ParsedReceipt>(ModelFailure('ai-invalid-output'));
    }
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const Err<ParsedReceipt>(ModelFailure('ai-invalid-output'));
    }
    if (decoded is! Map) {
      return const Err<ParsedReceipt>(ModelFailure('ai-invalid-output'));
    }
    final String? merchant = decoded['merchant']?.toString();
    final num? total = decoded['total'] is num ? decoded['total']! as num : null;
    final String? dateStr = decoded['date']?.toString();
    final DateTime? date = dateStr == null ? null : DateTime.tryParse(dateStr);
    final List<ReceiptLineItem> items = <ReceiptLineItem>[];
    final Object? rawItems = decoded['items'];
    if (rawItems is List) {
      for (final Object? item in rawItems.take(3)) {
        if (item is Map) {
          final String? name = item['name']?.toString();
          final num? price = item['price'] is num ? item['price']! as num : null;
          if (name != null && name.isNotEmpty && price != null) {
            items.add(
              ReceiptLineItem(name, Money((price * 100).round())),
            );
          }
        }
      }
    }
    return Ok<ParsedReceipt>(
      ParsedReceipt(
        rawText: text,
        // Honest model confidence: the ensemble still escalates to
        // human-confirm; this only ranks against the rules leg.
        confidence: 0.75,
        merchant: merchant,
        total: total == null ? null : Money((total * 100).round()),
        date: date == null ? null : DateTime(date.year, date.month, date.day, 12),
        items: items,
      ),
    );
  }

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
