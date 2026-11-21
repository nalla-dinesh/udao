// phase-02
// Punjab National Bank debit/credit SMS.
//
// `Rs.148.00 debited from your A/c 1234567890 on 26-10-26 UPI Ref
//  412345678901 SWIGGY.`
import 'package:udao/data/parsers/bank_parser_base.dart';

final class PnbParser extends BankSmsParser {
  @override
  String get id => 'pnb';

  @override
  List<String> get senderTags => <String>['PNB', 'PNBIND'];

  @override
  RegExp get probe =>
      RegExp(r'punjab national bank|pnb', caseSensitive: false);

  @override
  RegExp get refPattern => RegExp(r'Ref[:\s]*(\d{6,})');

  @override
  List<RegExp> get merchantPatterns => <RegExp>[
        RegExp(
          r'\bRef[:\s]*\d{6,}\s+([A-Za-z][\w .&/\-]*?)'
          r'(?=\s*\.\s|\s*\.?\s*$|\s+Avl\b|\s+Available\b)',
        ),
        RegExp(r'\bto\s+([A-Za-z][\w .&/\-]+?)\s*(?:\.|$)'),
      ];
}
