// phase-02
// PhonePe notifications (`com.phonepe.app`).
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/amount_extractor.dart';
import 'package:udao/data/parsers/merchant_cleaner.dart';
import 'package:udao/data/parsers/parser_types.dart';

class PhonePeParser implements TxnParser {
  static const String packageKey = 'com.phonepe.app';

  static final RegExp _debitVerbFirst = RegExp(
    r'(?:paid|sent)\s*(?:₹|rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:to|for)\s*([^\n]+)',
    caseSensitive: false,
  );
  static final RegExp _debitAmountFirst = RegExp(
    r'(?:₹|rs\.?|inr)\s*([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:paid|sent)\s*(?:to|for)\s*([^\n]+)',
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
    r'\b[\w.\-]{2,}@(?:ybl|yapl|ok[a-z]+|paytm|upi|ibl|axl)\b',
    caseSensitive: false,
  );
  static final RegExp _probe =
      RegExp('phonepe', caseSensitive: false);

  @override
  String get id => 'phonepe';

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
          bankOrApp: 'phonepe',
          occurredAt: input.receivedAt,
          confidence: 0.95,
          parserId: id,
          vpa: vpa,
        ),
      );
    }
    return Ok(
      ParsedTxn(
        amount: Money(paise),
        direction: TxnDirection.debit,
        merchantRaw: 'Unknown',
        merchantClean: 'Unknown',
        bankOrApp: 'phonepe',
        occurredAt: input.receivedAt,
        confidence: 0.7,
        parserId: id,
      ),
    );
  }
}
