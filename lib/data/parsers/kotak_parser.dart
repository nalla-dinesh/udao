// phase-02
// Kotak Mahindra Bank debit/credit SMS.
//
// `Rs.148.00 debited from your CR A/c 123456 on 26-10-26 towards
//  SWIGGY. Ref 512345678901.`
import 'package:udao/data/parsers/bank_parser_base.dart';

final class KotakParser extends BankSmsParser {
  @override
  String get id => 'kotak';

  @override
  List<String> get senderTags => <String>['KOTAKB', 'KOTAK'];

  @override
  RegExp get probe =>
      RegExp(r'kotak mahindra bank|kotak', caseSensitive: false);

  @override
  RegExp get refPattern => RegExp(r'Ref[:\s]*(\d{6,})');

  @override
  List<RegExp> get merchantPatterns => <RegExp>[
        RegExp(
          r'\btowards\s+([A-Za-z][\w .&/\-]*?)'
          r'(?=\s*\.\s|\s*\.?\s*$|\s+Ref\b|\s+Avl\b|\s+Available\b)',
        ),
        RegExp(r'\bto\s+([A-Za-z][\w .&/\-]+?)\s*(?:\.|$)'),
      ];
}
