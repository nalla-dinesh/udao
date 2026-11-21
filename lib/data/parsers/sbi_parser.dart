// phase-02
// State Bank of India debit/credit SMS.
//
// `Your A/c XX1234 debited on 26-10-26 for Rs.148.00 by SWIGGY
//  (UPI Ref No 412345678901).`
import 'package:udao/data/parsers/bank_parser_base.dart';

final class SbiParser extends BankSmsParser {
  @override
  String get id => 'sbi';

  @override
  List<String> get senderTags => <String>['SBI', 'SBIBNK', 'SBIIN'];

  @override
  RegExp get probe =>
      RegExp(r'state bank of india|sbi', caseSensitive: false);

  @override
  RegExp get refPattern =>
      RegExp(r'(?:UPI\s*)?Ref(?:\.\s*|\s*No\.?|\s*:)?:?\s*(\d{6,})');

  @override
  List<RegExp> get merchantPatterns => <RegExp>[
        RegExp(
          r'\bby\s+([A-Za-z][\w .&/\-]*?)(?=\s*\(|\s*\(?UPI|\s+Ref\b|\s*$)',
        ),
        RegExp(r'\bfor\s+([A-Za-z][\w .&/\-]+?)(?=\s+on\s|\s*$)'),
      ];
}
