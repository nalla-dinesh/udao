// phase-02
// Shared machinery for bank SMS parsers. Each subclass supplies its
// sender tags + ref/merchant regexes; direction, amount, date and
// confidence handling live here once.
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/amount_extractor.dart';
import 'package:udao/data/parsers/date_hints.dart';
import 'package:udao/data/parsers/merchant_cleaner.dart';
import 'package:udao/data/parsers/parser_types.dart';

abstract base class BankSmsParser implements TxnParser {
  /// Sender-address tags (`HDFCBK`, `SBI`, …). Matched as prefixes on
  /// the alphanumeric sender, so `VM-HDFCBK` and `JD-HDFCBK` both hit.
  List<String> get senderTags;

  /// Body probe used when the sender is missing (notification import,
  /// forward) — the bank's own name in the text.
  RegExp get probe;

  /// Reference-number regex; group 1 = digits.
  RegExp get refPattern;

  /// Merchant-extraction attempts, tried in order; group 1 = name.
  List<RegExp> get merchantPatterns;

  // "Dr from A/C" / "Cr to A/C" banking shorthand (BoB-style:
  // "Rs.5.00 Dr from A/C XXXXXX1521 and Cr to vpa@okicici") — the
  // debit form is anchored to an account word so a beneficiary
  // "Cr to <vpa>" in a DEBIT sms never flips the direction.
  static final RegExp _debitWord =
      RegExp(r'\b(?:debited|spent|paid)\b|dr\.?\s+from\s+(?:a/?c\b|acct\b|account\b)', caseSensitive: false);
  static final RegExp _creditWord =
      RegExp(r'\b(?:credited|received)\b|cr\.?\s+to\s+(?:a/?c\b|acct\b|account\b)', caseSensitive: false);

  @override
  bool matches(ParserInput input) {
    final String? sender = input.sender;
    if (sender != null) {
      final String flat = sender.toUpperCase();
      for (final String tag in senderTags) {
        if (flat.contains(tag)) {
          return true;
        }
      }
    }
    return probe.hasMatch(input.text);
  }

  @override
  Result<ParsedTxn> parse(ParserInput input) {
    final String text = input.text;
    final bool isDebit = _debitWord.hasMatch(text);
    final bool isCredit = _creditWord.hasMatch(text);
    if (!isDebit && !isCredit) {
      return const Err(noParserMatch);
    }
    final int? paise = AmountExtractor.extractPaise(text);
    if (paise == null) {
      return const Err(noParserMatch);
    }
    final String? refNo = refPattern.firstMatch(text)?.group(1);
    String? merchantRaw;
    for (final RegExp pattern in merchantPatterns) {
      final RegExpMatch? m = pattern.firstMatch(text);
      if (m != null && m.group(1)!.trim().isNotEmpty) {
        merchantRaw = m.group(1)!.trim();
        break;
      }
    }

    final bool full = merchantRaw != null;
    return Ok(
      ParsedTxn(
        amount: Money(paise),
        direction: isDebit ? TxnDirection.debit : TxnDirection.credit,
        merchantRaw: merchantRaw ?? 'Unknown',
        merchantClean: MerchantCleaner.clean(merchantRaw ?? 'Unknown'),
        bankOrApp: id,
        occurredAt: DateHints.resolve(text, input.receivedAt),
        confidence: full ? 0.85 : 0.7,
        parserId: id,
        refNo: refNo,
      ),
    );
  }
}
