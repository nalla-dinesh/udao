// phase-02
// The safety net: any UPI-flavoured money text the specific parsers
// didn't claim. Always low confidence → review queue, never silent
// ledger writes.
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/amount_extractor.dart';
import 'package:udao/data/parsers/merchant_cleaner.dart';
import 'package:udao/data/parsers/parser_types.dart';

class GenericUpiParser implements TxnParser {
  static final RegExp _probe = RegExp(
    r'\bupi\b|\b@[a-z]{2,}\b.*paid|\bBHIM\b',
    caseSensitive: false,
  );
  static final RegExp _debitVerbFirst = RegExp(
    r'(?:paid|sent|debited)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:to|towards)\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _debitAmountFirst = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:paid|sent|debited)\s*(?:to|towards)\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _creditVerbFirst = RegExp(
    r'(?:received|credited)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:from)\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _creditAmountFirst = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:received|credited)\s*(?:from)\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _vpa = RegExp(
    r'\b[\w.\-]{2,}@(?:ybl|yapl|paytm|ok[a-z]+|upi|ibl|axl)\b',
    caseSensitive: false,
  );

  @override
  String get id => 'generic_upi';

  @override
  bool matches(ParserInput input) => _probe.hasMatch(input.text);

  @override
  Result<ParsedTxn> parse(ParserInput input) {
    final String text = input.text;
    if (!_probe.hasMatch(text)) {
      return const Err(noParserMatch);
    }
    final int? paise = AmountExtractor.extractPaise(text);
    if (paise == null) {
      return const Err(noParserMatch);
    }
    final RegExpMatch? debit = _debitVerbFirst.firstMatch(text) ??
        _debitAmountFirst.firstMatch(text);
    final RegExpMatch? credit = _creditVerbFirst.firstMatch(text) ??
        _creditAmountFirst.firstMatch(text);
    final RegExpMatch? m = debit ?? credit;
    final String? vpa = _vpa.firstMatch(text)?.group(0);

    final String merchantRaw = m == null
        ? (vpa ?? 'Unknown')
        : MerchantCleaner.stripChannelNoise(m.group(2)!);
    return Ok(
      ParsedTxn(
        amount: Money(paise),
        // Unknown phrasing: assume a payment (dominant real-world case);
        // review band (0.65) means a human sees it either way.
        direction: debit != null || m == null
            ? TxnDirection.debit
            : TxnDirection.credit,
        merchantRaw: merchantRaw,
        merchantClean: MerchantCleaner.clean(merchantRaw),
        bankOrApp: 'upi',
        occurredAt: input.receivedAt,
        confidence: 0.65,
        parserId: id,
        vpa: vpa,
      ),
    );
  }
}
