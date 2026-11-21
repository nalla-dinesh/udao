// phase-04
// The full word-number table: 60 cases spanning digits, Hindi and
// English number words, fraction prefixes (sawa/derh/paune/adha),
// compositions, currency noise, direction words, merchant hints and
// honest unknown-tail reporting.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/capture/quick/hinglish_amount_parser.dart';

void main() {
  // (spoken, expectedPaise)
  const List<(String, int?)> amounts = <(String, int?)>[
    // -- digits --------------------------------------------------------
    ('60', 6000),
    ('60 rupaye', 6000),
    ('60 rupees', 6000),
    ('₹125', 12500),
    ('1.2k', 120000),
    ('2k', 200000),
    ('1.5k chai', 150000),
    ('125/-', 12500),
    ('250', 25000),
    ('999', 99900),
    ('1050', 105000),
    ('0.50', 50),
    ('12.50', 1250),
    // -- spec table ----------------------------------------------------
    ('sawa sau', 12500), // ₹125
    ('derh sau', 15000), // 150
    ('dedh sau', 15000),
    ('paune do sau', 17500), // 175
    ('paune sau', 7500),
    ('adha', 5000), // 50
    ('aadha', 5000),
    ('adha sau', 5000),
    ('do sau pachaas', 25000), // 250
    ('sau pachaas', 15000),
    ('do sau', 20000),
    ('teen sau', 30000),
    ('eleven hundred', 110000), // 1100
    ('2 lakh 50', 25000000), // 2,50,000
    ('ek lakh', 10000000),
    ('panch hazaar', 500000),
    ('das hazaar', 1000000),
    ('sawa hazaar', 125000), // ₹1,250
    ('derh hazaar', 150000), // ₹1,500
    // -- Hindi words ---------------------------------------------------
    ('ek', 100),
    ('do', 200),
    ('teen', 300),
    ('char', 400),
    ('panch', 500),
    ('das', 1000),
    ('gyaarah', 1100),
    ('pandrah', 1500),
    ('bees', 2000),
    ('pachees', 2500),
    ('chalis', 4000),
    ('pachaas', 5000),
    ('saath', 6000),
    ('nabbe', 9000),
    ('sau', 10000),
    ('do sau panch', 20500),
    ('sawa do sau', 22500),
    // -- English words -------------------------------------------------
    ('twenty', 2000),
    ('fifty', 5000),
    ('ninety', 9000),
    ('one hundred', 10000),
    ('five hundred', 50000),
    ('two thousand', 200000),
    ('three thousand five hundred', 350000),
    ('ten thousand', 1000000),
    // -- nothing understood ---------------------------------------------
    ('kuch nahi', null),
    ('', null),
  ];

  for (final (String spoken, int? paise) in amounts) {
    test('amount: "$spoken" -> $paise', () {
      final HinglishDraft d = HinglishAmountParser.parse(spoken);
      expect(d.amountPaise, paise, reason: '"$spoken"');
    });
  }

  test('merchant + category hints land', () {
    final HinglishDraft d = HinglishAmountParser.parse('sawa sau auto ka');
    expect(d.amountPaise, 12500);
    expect(d.merchantHint, 'auto');
    expect(d.categoryId, 'cat_transport');
    expect(d.credit, isFalse);
  });

  test('chai / milk / petrol hints map to their categories', () {
    expect(
      HinglishAmountParser.parse('bees rupaye chai').categoryId,
      'cat_chai',
    );
    expect(
      HinglishAmountParser.parse('sau milk ka').categoryId,
      'cat_groceries',
    );
    expect(
      HinglishAmountParser.parse('do sau petrol').categoryId,
      'cat_fuel',
    );
  });

  test('mila/milaya → credit', () {
    expect(HinglishAmountParser.parse('pachaas rupaye mile').credit, isTrue);
    expect(
        HinglishAmountParser.parse('sau rupaya milaya').credit,
        isTrue,
    );
    expect(HinglishAmountParser.parse('bees rupaye diye').credit, isFalse);
  });

  test('unknown tail words surface honestly and shave confidence', () {
    final HinglishDraft d = HinglishAmountParser.parse('sawa sau falflfal');
    expect(d.amountPaise, 12500);
    expect(d.unknownTail, <String>['falflfal']);
    expect(d.confidence, lessThan(1));
  });

  test('clean parse is fully confident', () {
    final HinglishDraft d = HinglishAmountParser.parse('sawa sau auto');
    expect(d.confidence, 1.0);
  });

  test('devanagari digits parse', () {
    final HinglishDraft d = HinglishAmountParser.parse('६० rupaye');
    expect(d.amountPaise, 6000);
  });
}
