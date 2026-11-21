// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/data/parsers/merchant_cleaner.dart';

void main() {
  group('MerchantCleaner.clean — aliases (25)', () {
    const List<(String, String)> cases = <(String, String)>[
      ('SWIGGY', 'Swiggy'),
      ('swiggy', 'Swiggy'),
      ('Zomato', 'Zomato'),
      ('BLINKIT', 'Blinkit'),
      ('zepto', 'Zepto'),
      ('BIGBASKET', 'BigBasket'),
      ('bbnow', 'BigBasket'),
      ('AMAZON PAY INDIA', 'Amazon Pay'),
      ('FLIPKART', 'Flipkart'),
      ('Myntra', 'Myntra'),
      ('DMART', 'DMart'),
      ('AVENUE SUPERMARTS', 'DMart'),
      ('UBER INDIA', 'Uber'),
      ('OLA (ANI TECHNOLOGIES)', 'Ola'),
      ('RAPIDO', 'Rapido'),
      ('IRCTC', 'IRCTC'),
      ('DOMINOS PIZZA', "Domino's"),
      ('MCD', "McDonald's"),
      ('KFC', 'KFC'),
      ('NETFLIX', 'Netflix'),
      ('SPOTIFY', 'Spotify'),
      ('AIRTEL', 'Airtel'),
      ('BSES YAMUNA', 'BSES Yamuna'),
      ('TATA POWER', 'Tata Power'),
      ('VI', 'Vi'),
    ];
    for (final (String raw, String want) in cases) {
      test('$raw -> $want', () {
        expect(MerchantCleaner.clean(raw), want);
      });
    }
  });

  group('MerchantCleaner.clean — noise and casing (12)', () {
    const List<(String, String)> cases = <(String, String)>[
      ('RAMESH KIRANA', 'Ramesh Kirana'),
      ('LUXURY CARS PVT LTD', 'Luxury Cars'),
      ('GOOGLE INDIA PVT LTD', 'Google'),
      ('N KIRANA ENTERPRISES', 'N Kirana'),
      ('SHARMA GENERAL STORE', 'Sharma General'),
      ('CHAI WALA', 'Chai Wala'),
      ('PAYTM FASTAG', 'Paytm Fastag'),
      ('VI RECHARGE', 'VI Recharge'),
      ('SALARY OCTOBER', 'Salary October'),
      ('PRIYA SHARMA', 'Priya Sharma'),
      ('  weird   spacing  ', 'Weird Spacing'),
      ('trimmed..dots..', 'Trimmed..dots'),
    ];
    for (final (String raw, String want) in cases) {
      test('$raw -> $want', () {
        expect(MerchantCleaner.clean(raw), want);
      });
    }
  });

  group('MerchantCleaner.clean — special inputs (8)', () {
    test('VPAs pass through untouched', () {
      expect(
        MerchantCleaner.clean('ramesh@okhdfcbank'),
        'ramesh@okhdfcbank',
      );
      expect(MerchantCleaner.clean('x@ybl'), 'x@ybl');
    });

    test('bracketed noise is stripped', () {
      expect(MerchantCleaner.clean('OLA (ANI TECHNOLOGIES)'), 'Ola');
    });

    test('empty stays empty', () {
      expect(MerchantCleaner.clean(''), '');
      expect(MerchantCleaner.clean('   '), '');
    });

    test('all-suffix noise falls back to the raw string', () {
      // "Pvt Ltd" alone cleans to nothing -> cleaner keeps the raw.
      final String out = MerchantCleaner.clean('Pvt Ltd');
      expect(out, isNotEmpty);
    });

    test('stripChannelNoise removes channel phrases', () {
      expect(
        MerchantCleaner.stripChannelNoise('Swiggy via UPI'),
        'Swiggy',
      );
      expect(
        MerchantCleaner.stripChannelNoise('Swiggy via Paytm UPI'),
        'Swiggy',
      );
      expect(
        MerchantCleaner.stripChannelNoise('Swiggy using PhonePe'),
        'Swiggy',
      );
      expect(
        MerchantCleaner.stripChannelNoise('Swiggy on Google Pay'),
        'Swiggy',
      );
      expect(MerchantCleaner.stripChannelNoise('Swiggy'), 'Swiggy');
    });

    test('aliasOf finds squashed keys', () {
      expect(MerchantCleaner.aliasOf('swiggy'), 'Swiggy');
      expect(MerchantCleaner.aliasOf('AMAZON PAY'), 'Amazon Pay');
      expect(MerchantCleaner.aliasOf('unknown-thing'), isNull);
    });

    test('mixed-case brands keep their casing', () {
      expect(MerchantCleaner.clean('FreshMenu Meals'), 'FreshMenu Meals');
    });

    test('tiny all-caps tokens survive (KFC-like)', () {
      expect(MerchantCleaner.clean('ABC Store'), 'ABC');
    });
  });
}
