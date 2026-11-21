// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/axis_parser.dart';
import 'package:udao/data/parsers/bob_parser.dart';
import 'package:udao/data/parsers/hdfc_parser.dart';
import 'package:udao/data/parsers/icici_parser.dart';
import 'package:udao/data/parsers/kotak_parser.dart';
import 'package:udao/data/parsers/parser_types.dart';
import 'package:udao/data/parsers/pnb_parser.dart';
import 'package:udao/data/parsers/sbi_parser.dart';

void main() {
  final DateTime at = DateTime(2026, 10, 27, 18, 45, 3);

  ParserInput sms(String sender, String text) =>
      ParserInput(text: text, receivedAt: at, sender: sender);

  group('HdfcParser', () {
    final HdfcParser p = HdfcParser();

    test('matches on sender tag variants', () {
      expect(p.matches(sms('VM-HDFCBK', 'x')), isTrue);
      expect(p.matches(sms('JD-HDFCBK', 'x')), isTrue);
      expect(p.matches(sms('BZ-HDFC', 'x')), isTrue);
    });

    test('matches on "HDFC Bank" body text', () {
      expect(
        p.matches(
          ParserInput(
            text: 'HDFC Bank: Rs.99 debited',
            receivedAt: at,
          ),
        ),
        isTrue,
      );
    });

    test('full debit parses with ref and merchant', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-HDFCBK',
          'Rs.148.00 debited from A/c No. XX1234 on 27-10-26 '
              'REF 512345678901 SWIGGY INDIA PVT LTD.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 14800);
      expect(t.direction, TxnDirection.debit);
      expect(t.merchantClean, 'Swiggy');
      expect(t.bankOrApp, 'hdfc');
      expect(t.refNo, '512345678901');
      expect(t.confidence, 0.85);
      expect(t.occurredAt, at); // same-day hint keeps receive clock
    });

    test('balance text after merchant does not leak into the name', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-HDFCBK',
          'Rs.999.99 debited from A/c **1234 on 27-10-26 REF 512345678901 '
              'MYNTRA. Avl Bal Rs.1,000.00.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 99999);
      expect(t.merchantClean, 'Myntra');
    });

    test('credit direction', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-HDFCBK',
          'Rs.15,000.00 credited to A/c XX5678 on 27-10-26 '
              'REF 512345678901 SALARY OCTOBER.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.direction, TxnDirection.credit);
      expect(t.merchantClean, 'Salary October');
    });

    test('missing merchant drops to review band', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-HDFCBK',
          'Rs.350 debited from A/c XX1234 on 27-10-26.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 35000);
      expect(t.merchantClean, 'Unknown');
      expect(t.confidence, 0.7);
    });

    test('no debit/credit wording is no_parser_match', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-HDFCBK',
          'Dear Customer, your KYC is pending.',
        ),
      );
      expect(r.failureOrNull?.message, 'no_parser_match');
    });
  });

  group('SbiParser', () {
    final SbiParser p = SbiParser();

    test('by-paren ref form', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-SBI',
          'Your A/c XX1234 debited on 27-10-26 for Rs.72.50 by UBER INDIA '
              '(UPI Ref No 412345678901).',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 7250);
      expect(t.merchantClean, 'Uber');
      expect(t.refNo, '412345678901');
    });

    test('inline UPI ref form with trailing balance', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-SBI',
          'Rs.250 debited from your A/c XX1234 on 27-10-26 by SWIGGY. '
              'UPI Ref 412345678901. Avl Bal: Rs.8,000.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 25000);
      expect(t.merchantClean, 'Swiggy');
    });
  });

  group('IciciParser', () {
    final IciciParser p = IciciParser();

    test('Info: form', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-ICICIB',
          'Your A/c XX1234 debited for Rs.399 on 27-10-26. '
              'Info: HOTSTAR. UPI:512345678901.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 39900);
      expect(t.merchantClean, 'Hotstar');
      expect(t.refNo, '512345678901');
    });

    test('Info with corporate suffix', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-ICICIB',
          'Your A/c XX1234 credited for Rs.25,000.00 on 27-10-26. '
              'Info: GOOGLE INDIA PVT LTD. UPI:512345678901.',
        ),
      );
      expect(r.valueOrNull!.merchantClean, 'Google');
    });
  });

  group('AxisParser', () {
    final AxisParser p = AxisParser();

    test('UPI Ref tail form', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-AXISBK',
          'Rs.75 debited from A/c 12345 on 27-10-26 UPI Ref 412345678901 '
              'NAMMA YATRI.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 7500);
      expect(t.merchantClean, 'Namma Yatri');
    });

    test('credit with tail merchant', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-AXISBK',
          'Rs.4,000 credited to A/c 12345 on 27-10-26 Ref 412345678901 '
              'AMAZON PAY INDIA.',
        ),
      );
      expect(r.valueOrNull!.direction, TxnDirection.credit);
      expect(r.valueOrNull!.merchantClean, 'Amazon Pay');
    });
  });

  group('KotakParser', () {
    final KotakParser p = KotakParser();

    test('towards form', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-KOTAKB',
          'Rs.55 debited from A/c 123456 on 27-10-26 towards CHAI POINT. '
              'Avl Bal Rs.4,321.00.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 5500);
      expect(t.merchantClean, 'Chai Point');
    });

    test('no-merchant credit is review band', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-KOTAKB',
          'Your CR A/c 123456 credited Rs.60 on 27-10-26. Ref 512345678901.',
        ),
      );
      expect(r.valueOrNull!.confidence, 0.7);
      expect(r.valueOrNull!.merchantClean, 'Unknown');
    });
  });

  group('PnbParser', () {
    final PnbParser p = PnbParser();

    test('long account + UPI ref tail', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-PNBIND',
          'Rs.2,500 debited from your A/c 1234567890 on 27-10-26 '
              'UPI Ref 412345678901 AVENUE SUPERMARTS LTD.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 250000);
      expect(t.merchantClean, 'DMart');
    });

    test('credit with VI brand', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-PNBIND',
          'Rs.900 credited to your A/c 1234567890 on 27-10-26 '
              'Ref 412345678901 VI RECHARGE.',
        ),
      );
      expect(r.valueOrNull!.direction, TxnDirection.credit);
      expect(r.valueOrNull!.merchantClean, 'VI Recharge');
    });
  });

  group('BobParser', () {
    final BobParser p = BobParser();

    test('parenthesised ref form', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-BARDBKB',
          'Rs.148.00 debited from A/c 1234567890 on 27-10-26 '
              '(UPI Ref: 412345678901) ZEPTO TECHNOLOGIES PVT LTD.',
        ),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 14800);
      expect(t.merchantClean, 'Zepto');
      expect(t.refNo, '412345678901');
    });

    test('merchant-less paren form is review band', () {
      final Result<ParsedTxn> r = p.parse(
        sms(
          'VM-BARDBKB',
          'Rs.350 debited from A/c 1234567890 on 27-10-26 '
              '(UPI Ref: 412345678901).',
        ),
      );
      expect(r.valueOrNull!.confidence, 0.7);
    });
  });

  group('cross-routing policy', () {
    test('bank sender outranks app-name in body', () {
      final HdfcParser hdfc = HdfcParser();
      final Result<ParsedTxn> r = hdfc.parse(
        sms(
          'VM-HDFCBK',
          'Rs.99 debited from A/c XX11 on 27-10-26 REF 512345678 '
              'PAYTM FASTAG.',
        ),
      );
      expect(r.valueOrNull!.bankOrApp, 'hdfc');
      expect(r.valueOrNull!.merchantClean, 'Paytm Fastag');
    });
  });
}
