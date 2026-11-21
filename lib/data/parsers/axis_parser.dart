// phase-02
// Axis Bank debit/credit SMS.
//
// `Rs.148.00 debited from A/c 1234 on 26-10-26 UPI Ref 412345678901
//  SWIGGY.`
import 'package:udao/data/parsers/bank_parser_base.dart';

final class AxisParser extends BankSmsParser {
  @override
  String get id => 'axis';

  @override
  List<String> get senderTags => <String>['AXISBK', 'AXISB', 'AXIS'];

  @override
  RegExp get probe => RegExp(r'axis bank', caseSensitive: false);

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
