// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/gpay_parser.dart';
import 'package:udao/data/parsers/parser_types.dart';
import 'package:udao/data/parsers/paytm_parser.dart';
import 'package:udao/data/parsers/phonepe_parser.dart';

void main() {
  final DateTime at = DateTime(2026, 10, 27, 18, 45);

  ParserInput notif(String pkg, String text) =>
      ParserInput(text: text, receivedAt: at, packageKey: pkg);

  group('GPayParser', () {
    final GPayParser p = GPayParser();

    test('matches on package key', () {
      expect(p.matches(notif(GPayParser.packageKey, 'anything')), isTrue);
    });

    test('matches on "Google Pay" body text', () {
      expect(
        p.matches(
          ParserInput(
            text: 'Sent ₹500 to SWIGGY via Google Pay',
            receivedAt: at,
          ),
        ),
        isTrue,
      );
    });

    test('does not match bare UPI text', () {
      expect(
        p.matches(
          ParserInput(
            text: 'Paid Rs.120 via BHIM UPI',
            receivedAt: at,
          ),
        ),
        isFalse,
      );
    });

    test('verb-first debit: ₹150 sent to X', () {
      final Result<ParsedTxn> r = p.parse(
        notif(GPayParser.packageKey, 'You sent ₹150 to Swiggy'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 15000);
      expect(t.direction, TxnDirection.debit);
      expect(t.merchantClean, 'Swiggy');
      expect(t.bankOrApp, 'gpay');
      expect(t.confidence, 0.95);
    });

    test('amount-first debit: ₹X sent to Y', () {
      final Result<ParsedTxn> r = p.parse(
        notif(GPayParser.packageKey, '₹148 paid to ZEPTO via UPI'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 14800);
      expect(t.direction, TxnDirection.debit);
      expect(t.merchantClean, 'Zepto');
    });

    test('credit: received from X', () {
      final Result<ParsedTxn> r = p.parse(
        notif(GPayParser.packageKey, 'Received ₹1,234.56 from AMAZON PAY INDIA'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 123456);
      expect(t.direction, TxnDirection.credit);
      expect(t.merchantClean, 'Amazon Pay');
    });

    test('vpa counterparty and hasVpa', () {
      final Result<ParsedTxn> r = p.parse(
        notif(GPayParser.packageKey, 'You sent ₹150 to ramesh@okhdfcbank'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.merchantClean, 'ramesh@okhdfcbank');
      expect(t.vpa, 'ramesh@okhdfcbank');
    });

    test('unknown phrasing falls to review band', () {
      final Result<ParsedTxn> r = p.parse(
        notif(GPayParser.packageKey, 'Payment of ₹250 pending approval'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 25000);
      expect(t.confidence, 0.7);
      expect(t.merchantClean, 'Unknown');
    });

    test('no amount at all is no_parser_match', () {
      final Result<ParsedTxn> r = p.parse(
        notif(GPayParser.packageKey, 'Payment pending'),
      );
      expect(r.failureOrNull?.message, 'no_parser_match');
    });
  });

  group('PhonePeParser', () {
    final PhonePeParser p = PhonePeParser();

    test('matches on package key and body text', () {
      expect(p.matches(notif(PhonePeParser.packageKey, 'x')), isTrue);
      expect(
        p.matches(
          ParserInput(
            text: '₹25 paid to CHAI WALA using PhonePe',
            receivedAt: at,
          ),
        ),
        isTrue,
      );
    });

    test('verb-first debit with channel stripping', () {
      final Result<ParsedTxn> r = p.parse(
        notif(PhonePeParser.packageKey, 'Sent ₹250 to Swiggy on PhonePe'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 25000);
      expect(t.merchantClean, 'Swiggy');
      expect(t.bankOrApp, 'phonepe');
      expect(t.confidence, 0.95);
    });

    test('amount-first debit', () {
      final Result<ParsedTxn> r = p.parse(
        notif(PhonePeParser.packageKey, '₹1,499 paid to FLIPKART INDIA PVT LTD'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 149900);
      expect(t.merchantClean, 'Flipkart');
    });

    test('credit verb-first', () {
      final Result<ParsedTxn> r = p.parse(
        notif(PhonePeParser.packageKey, 'You received ₹5,000 from N KIRANA ENTERPRISES'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.direction, TxnDirection.credit);
      expect(t.merchantClean, 'N Kirana');
    });

    test('credited phrasing counts as credit', () {
      final Result<ParsedTxn> r = p.parse(
        notif(PhonePeParser.packageKey, '₹500 credited from REFUND CORP'),
      );
      expect(r.valueOrNull!.direction, TxnDirection.credit);
    });

    test('partial falls to review band', () {
      final Result<ParsedTxn> r = p.parse(
        notif(PhonePeParser.packageKey, 'Transaction ₹88 at CHAI POINT successful'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 8800);
      expect(t.confidence, 0.7);
      expect(t.merchantClean, 'Unknown');
    });
  });

  group('PaytmParser', () {
    final PaytmParser p = PaytmParser();

    test('matches on package key and body text', () {
      expect(p.matches(notif(PaytmParser.packageKey, 'x')), isTrue);
      expect(
        p.matches(
          ParserInput(
            text: 'Paid via Paytm UPI',
            receivedAt: at,
          ),
        ),
        isTrue,
      );
    });

    test('amount-first debit', () {
      final Result<ParsedTxn> r = p.parse(
        notif(PaytmParser.packageKey, '₹99 paid to DOMINOS PIZZA'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 9900);
      expect(t.merchantClean, "Domino's");
      expect(t.confidence, 0.90);
      expect(t.bankOrApp, 'paytm');
    });

    test('channel phrase stripped from merchant', () {
      final Result<ParsedTxn> r = p.parse(
        notif(PaytmParser.packageKey, '₹250 sent to Swiggy via Paytm UPI'),
      );
      expect(r.valueOrNull!.merchantClean, 'Swiggy');
    });

    test('vpa counterparty', () {
      final Result<ParsedTxn> r = p.parse(
        notif(PaytmParser.packageKey, 'Sent ₹75 to freshmilk@paytm'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.merchantClean, 'freshmilk@paytm');
      expect(t.vpa, 'freshmilk@paytm');
    });

    test('wallet-only deduction is review band', () {
      final Result<ParsedTxn> r = p.parse(
        notif(PaytmParser.packageKey, '₹1,000 deducted from wallet'),
      );
      final ParsedTxn t = r.valueOrNull!;
      expect(t.amount.paise, 100000);
      expect(t.confidence, 0.7);
    });
  });
}
