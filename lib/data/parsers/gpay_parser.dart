// phase-02
// Google Pay India notifications (`com.google.android.apps.nbu.paysa`).
//
// Phase-03 errata: this shipped keyed on the corpus' fake id
// `com.google.android.apps.nobu` — a production GPay notification
// would NEVER have matched (caught by the phase-03 40-event e2e
// local run). The corpus + gen_corpus.py were corrected with it.
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/amount_extractor.dart';
import 'package:udao/data/parsers/merchant_cleaner.dart';
import 'package:udao/data/parsers/parser_types.dart';

class GPayParser implements TxnParser {
  static const String packageKey = 'com.google.android.apps.nbu.paysa';

  static final RegExp _debitVerbFirst = RegExp(
    r'(?:sent|paid)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:to|for)\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _debitAmountFirst = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:sent|paid)\s*(?:to|for)\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _creditVerbFirst = RegExp(
    r'(?:received|got)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:from)\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _creditAmountFirst = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:received|got)\s*(?:from)\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _vpa = RegExp(
    r'\b[\w.\-]{2,}@(?:ok[a-z]+|ybl|yapl|paytm|upi|ibl|axl)\b',
    caseSensitive: false,
  );
  /// App-name probe only — `via UPI` alone belongs to GenericUpi.
  static final RegExp _probe = RegExp('google pay|gpay', caseSensitive: false);

  @override
  String get id => 'gpay';

  @override
  bool matches(ParserInput input) =>
      input.packageKey == packageKey || _probe.hasMatch(input.text);

  @override
  Result<ParsedTxn> parse(ParserInput input) {
    final RegExpMatch? debit = _debitVerbFirst.firstMatch(input.text) ??
        _debitAmountFirst.firstMatch(input.text);
    final RegExpMatch? credit = _creditVerbFirst.firstMatch(input.text) ??
        _creditAmountFirst.firstMatch(input.text);
    final RegExpMatch? m = debit ?? credit;
    final int? paise = AmountExtractor.extractPaise(input.text);

    if (m == null && paise == null) {
      return const Err(noParserMatch);
    }
    if (paise == null) {
      return const Err(noParserMatch);
    }

    if (m != null) {
      final bool isDebit = debit != null;
      final String merchantRaw =
          MerchantCleaner.stripChannelNoise(m.group(2)!);
      final String? vpa = _vpa.firstMatch(input.text)?.group(0);
      return Ok(
        ParsedTxn(
          amount: Money(paise),
          direction: isDebit ? TxnDirection.debit : TxnDirection.credit,
          merchantRaw: merchantRaw,
          merchantClean: MerchantCleaner.clean(merchantRaw),
          bankOrApp: 'gpay',
          occurredAt: input.receivedAt,
          confidence: 0.95,
          parserId: id,
          vpa: vpa,
        ),
      );
    }

    // Package matched + amount present, but phrasing unknown →
    // partial: park it for review.
    return Ok(
      ParsedTxn(
        amount: Money(paise),
        direction: TxnDirection.debit,
        merchantRaw: 'Unknown',
        merchantClean: 'Unknown',
        bankOrApp: 'gpay',
        occurredAt: input.receivedAt,
        confidence: 0.7,
        parserId: id,
      ),
    );
  }

}
