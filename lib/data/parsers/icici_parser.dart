// phase-02
// ICICI Bank debit/credit SMS.
//
// `Your A/c XX1234 debited for Rs.148.00 on 26-10-26. Info: SWIGGY.
//  UPI:512345678901.`
import 'package:udao/data/parsers/bank_parser_base.dart';

final class IciciParser extends BankSmsParser {
  @override
  String get id => 'icici';

  @override
  List<String> get senderTags => <String>['ICICIB', 'ICICI'];

  @override
  RegExp get probe =>
      RegExp(r'icici bank', caseSensitive: false);

  @override
  RegExp get refPattern => RegExp(r'\bUPI[:/]\s*(\d{6,})');

  @override
  List<RegExp> get merchantPatterns => <RegExp>[
        RegExp(
          r'\bInfo[:\s]+([A-Za-z][\w .&/\-]*?)(?=\s*\.\s|\s*\.?\s*$)',
        ),
        RegExp(r'\bto\s+([A-Za-z][\w .&/\-]+?)\s*(?:\.|$)'),
      ];
}
