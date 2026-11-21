// phase-02
// Shared parser vocabulary: what comes in, what goes out, and the
// contract every parser honours.
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/txn.dart' show TxnDirection;

/// A raw capture handed to the parser chain (notification or SMS).
class ParserInput {
  const ParserInput({
    required this.text,
    required this.receivedAt,
    this.packageKey,
    this.sender,
  });

  /// Notification body / SMS full text, verbatim.
  final String text;

  /// When the event landed on the device (IST clock).
  final DateTime receivedAt;

  /// Android package for notifications (`com.phonepe.app`, …) — null
  /// for SMS.
  final String? packageKey;

  /// SMS sender address (`VM-HDFCBK`, `JD-PAYTM`, …) — null for
  /// notifications.
  final String? sender;
}

/// The distilled transaction a parser extracted.
class ParsedTxn {
  const ParsedTxn({
    required this.amount,
    required this.direction,
    required this.merchantRaw,
    required this.merchantClean,
    required this.bankOrApp,
    required this.occurredAt,
    required this.confidence,
    required this.parserId,
    this.refNo,
    this.vpa,
  });

  final Money amount;
  final TxnDirection direction;

  /// Counterparty before/after cleaning (cleaning happens in-parser
  /// so the ledger only ever stores the display form).
  final String merchantRaw;
  final String merchantClean;
  final String bankOrApp;
  final DateTime occurredAt;
  final double confidence;
  final String parserId;
  final String? refNo;
  final String? vpa;
}

/// A parser in the chain. Pure: same input → same output, no IO.
abstract interface class TxnParser {
  /// Stable id (`gpay`, `hdfc`, …) persisted in capture_event.
  String get id;

  /// Cheap probe — can this parser claim [input]?
  bool matches(ParserInput input);

  /// Full extraction. `Err(ParseFailure('no_parser_match'))` when
  /// [matches] was true but the body regexes fail (partial formats).
  Result<ParsedTxn> parse(ParserInput input);
}

/// Shared no-match error.
const ParseFailure noParserMatch = ParseFailure('no_parser_match');

/// Confidence policy (see CONFIDENCE.md): at or above
/// [autoAcceptMin] the txn lands in the ledger silently; between
/// [reviewMin] and [autoAcceptMin] it queues for review; below
/// [reviewMin] parses are treated as too weak and dropped.
abstract final class ConfidencePolicy {
  static const double autoAcceptMin = 0.8;
  static const double reviewMin = 0.6;
}
