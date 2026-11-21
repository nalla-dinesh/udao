// phase-04
// 15 synthetic OCR-text fixtures through the rules parser — the
// shapes ML Kit actually returns from Indian shop receipts (block
// text, mixed currency marks, GSTIN headers, item lines).
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/capture/receipt/receipt_parsed.dart';
import 'package:udao/features/capture/receipt/receipt_rules_parser.dart';

typedef _Checks = void Function(ParsedReceipt p);

void main() {
  final List<(String, _Checks)> cases = <(String, _Checks)>[
    (
      'SWIGGY LIMITED\nOrder #1234\nDate: 12/06/2026\nTOTAL ₹349.00\n',
      (ParsedReceipt p) {
        expect(p.merchant, 'Swiggy');
        expect(p.total!.paise, 34900);
        expect(p.date!.day, 12);
      },
    ),
    (
      'RELIANCE SMART\nB-14, Sector 18, Noida\nGSTIN 09AABCR5928L1ZP\n'
          'Basmati Rice 5kg    450.00\nSunflower Oil 1L    210.00\n'
          'SUB TOTAL    660.00\nTOTAL AMOUNT    ₹660.00\n'
          '12-06-2026 18:42\n',
      (ParsedReceipt p) {
        expect(p.merchant, 'Reliance Smart');
        expect(p.total!.paise, 66000);
        expect(p.items.length, 2);
        expect(p.date!.month, 6);
      },
    ),
    (
      'CHAI POINT\nGurgaon\nInsta Chai    40\nCroissant    85\n'
          'Grand Total Rs. 125\n',
      (ParsedReceipt p) {
        expect(p.merchant, 'Chai Point');
        expect(p.total!.paise, 12500);
      },
    ),
    (
      'third wave coffee\nBengaluru\nDate: 2026-06-12\n'
          'Cappuccino    ₹280.00\nNet Payable    ₹280.00\n',
      (ParsedReceipt p) {
        expect(p.merchant, 'Third Wave Coffee');
        expect(p.total!.paise, 28000);
      },
    ),
    (
      'DMART READY\n\nTOTAL    1,234.56\n',
      (ParsedReceipt p) {
        expect(p.total!.paise, 123456);
      },
    ),
    (
      'AMAZON PAY INDIA\nRecharge\nBill Amount INR 299\n',
      (ParsedReceipt p) {
        expect(p.total!.paise, 29900);
      },
    ),
    (
      '12/06/2026\nIRCTC\nTATKAL CHARGES 250.00\nTOTAL 250.00\n',
      (ParsedReceipt p) {
        expect(p.merchant, 'IRCTC');
        expect(p.total!.paise, 25000);
        expect(p.date!.year, 2026);
      },
    ),
    (
      'UPI/QR MERCHANT\npayment of ₹99 received\n',
      (ParsedReceipt p) {
        expect(p.total!.paise, 9900);
      },
    ),
    (
      'no merchant line at all\n₹25.00\n₹75.00\nTOTAL ₹75.00\n',
      (ParsedReceipt p) {
        // Largest amount ON a total line wins over the larger bare
        // number above it.
        expect(p.total!.paise, 7500);
      },
    ),
    (
      'KIRANA STORE\nGSTIN 27AAECS1234F1Z5\nSugar 2kg    90.00\n'
          'TOTAL    90.00\nDate: 12 Jun 2026\n',
      (ParsedReceipt p) {
        // GSTIN line: merchant is the line ABOVE it. The cleaner
        // strips the 'Store' noise tail — that is its contract.
        expect(p.merchant, 'Kirana');
        expect(p.total!.paise, 9000);
        expect(p.date!.day, 12);
      },
    ),
    (
      'PETROL PUMP HP\nDiesel 2.5L    265.50\nTOTAL 265.50\n'
          'DATE 12-06-26\n',
      (ParsedReceipt p) {
        expect(p.total!.paise, 26550);
      },
    ),
    (
      '₹500 CASH\n₹1200 CARD\nTOTAL ₹1,200.00\n',
      (ParsedReceipt p) {
        expect(p.total!.paise, 120000);
      },
    ),
    (
      'SALON\nHaircut    300\nBeard    100\nTotal    400.00\n',
      (ParsedReceipt p) {
        expect(p.total!.paise, 40000);
        expect(p.items.length, 2);
      },
    ),
    (
      'garbled ocr\nn0 real am0unt here\n',
      (ParsedReceipt p) {
        expect(p.total, isNull);
        expect(
          p.confidence,
          lessThan(0.7),
          reason: 'no total → ensemble escalates',
        );
      },
    ),
    (
      'PHARMACY EASY\nGSTIN 29AAGCE1234M1Z7\nTablet Azithro    120.00\n'
          'Total    ₹120.00\n14/06/2026\n',
      (ParsedReceipt p) {
        expect(p.merchant, 'Pharmacy Easy');
        expect(p.total!.paise, 12000);
        expect(p.date!.day, 14);
      },
    ),
  ];

  for (int i = 0; i < cases.length; i++) {
    test('fixture ${i + 1}: ${cases[i].$1.split('\n').first}', () {
      final ParsedReceipt parsed = ReceiptRulesParser.parse(cases[i].$1);
      cases[i].$2(parsed);
    });
  }

  test('clean receipt confidence clears the 0.7 ensemble bar', () {
    final ParsedReceipt p = ReceiptRulesParser.parse(
      'SWIGGY LIMITED\nDate: 12/06/2026\nTOTAL ₹349.00\n',
    );
    expect(p.confidence, greaterThanOrEqualTo(0.7));
  });
}
