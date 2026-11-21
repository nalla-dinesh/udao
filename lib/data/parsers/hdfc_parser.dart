// phase-02
// HDFC Bank debit/credit SMS.
//
// `Rs.148.00 debited from A/c No. XX1234 on 26-10-26 REF 512345678901
//  SWIGGY INDIA PVT LTD.`
import 'package:udao/data/parsers/bank_parser_base.dart';

final class HdfcParser extends BankSmsParser {
  @override
  String get id => 'hdfc';

  @override
  List<String> get senderTags => <String>['HDFCBK', 'HDFC'];

  @override
  RegExp get probe =>
      RegExp(r'hdfc bank', caseSensitive: false);

  @override
  RegExp get refPattern => RegExp(r'\bREF\s*:?\s*(\d{6,})');

  @override
  List<RegExp> get merchantPatterns => <RegExp>[
        RegExp(
          r'\bREF\s*:?\s*\d{6,}\s*([A-Za-z][\w .&/\-]*?)'
          r'(?=\s*\.\s|\s*\.?\s*$|\s+Avl\b|\s+Available\b)',
        ),
        RegExp(r'\bat\s+([A-Za-z][\w .&/\-]+?)\s+on\s'),
      ];
}
