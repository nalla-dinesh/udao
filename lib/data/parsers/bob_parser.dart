// phase-02
// Bank of Baroda debit/credit SMS.
//
// `Rs.148.00 debited from A/c 1234567890 on 26-10-26 (UPI Ref:
//  412345678901) SWIGGY.`
import 'package:udao/data/parsers/bank_parser_base.dart';

final class BobParser extends BankSmsParser {
  @override
  String get id => 'bob';

  @override
  // 'BOBSMS' is the live TRAI route tag (seen as JD-BOBSMS-S /
  // JX-BOBSMS-S on real devices, Nov 2026); the others are the
  // registered long forms.
  List<String> get senderTags => <String>[
        'BOBSMS',
        'BARDBKB',
        'BANKOFBARODA',
        'BOBIND',
      ];

  @override
  RegExp get probe => RegExp(
    'bank of baroda|baroda|dr\\.?\\s+from\\s+a/?c\\b',
    caseSensitive: false,
  );

  @override
  RegExp get refPattern => RegExp(r'Ref[:\s]*(\d{6,})');

  @override
  List<RegExp> get merchantPatterns => <RegExp>[
        // UPI beneficiary VPA: "... and Cr to name@okicici. Ref: ..."
        RegExp(
          r'\bcr\.?\s+to\s+([\w.\-]+@[a-zA-Z]{2,})',
          caseSensitive: false,
        ),
        RegExp(
          r'\)\s*([A-Za-z][\w .&/\-]*?)'
          r'(?=\s*\.\s|\s*\.?\s*$|\s+Avl\b|\s+Available\b)',
        ),
        RegExp(r'\bto\s+([A-Za-z][\w .&/\-]+?)\s*(?:\.|$)'),
      ];
}
