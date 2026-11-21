// phase-02
// The ordered parser chain. **Order is policy:** specific apps first,
// specific banks next, generic UPI last (it would otherwise swallow
// everything). First `matches()` wins.
import 'package:udao/core/result/result.dart';
import 'package:udao/data/parsers/axis_parser.dart';
import 'package:udao/data/parsers/bob_parser.dart';
import 'package:udao/data/parsers/generic_upi_parser.dart';
import 'package:udao/data/parsers/gpay_parser.dart';
import 'package:udao/data/parsers/hdfc_parser.dart';
import 'package:udao/data/parsers/icici_parser.dart';
import 'package:udao/data/parsers/kotak_parser.dart';
import 'package:udao/data/parsers/parser_types.dart';
import 'package:udao/data/parsers/paytm_parser.dart';
import 'package:udao/data/parsers/phonepe_parser.dart';
import 'package:udao/data/parsers/pnb_parser.dart';
import 'package:udao/data/parsers/sbi_parser.dart';

/// 11 parsers in the chain (+ the filter pair that runs before it,
/// see `filters.dart`): **banks first** — sender tags are
/// authoritative, an HDFC SMS mentioning "Paytm" must stay an HDFC
/// txn; then the app parsers (notifications match on packageKey);
/// generic UPI last so it only catches the leftovers.
final List<TxnParser> kParserChain = <TxnParser>[
  HdfcParser(),
  SbiParser(),
  IciciParser(),
  AxisParser(),
  KotakParser(),
  PnbParser(),
  BobParser(),
  GPayParser(),
  PhonePeParser(),
  PaytmParser(),
  GenericUpiParser(),
];

/// Runs the chain: first matching parser parses. `no_parser_match`
/// when nothing claims the input.
Result<ParsedTxn> runParserChain(ParserInput input) {
  for (final TxnParser parser in kParserChain) {
    if (parser.matches(input)) {
      return parser.parse(input);
    }
  }
  return const Err(noParserMatch);
}
