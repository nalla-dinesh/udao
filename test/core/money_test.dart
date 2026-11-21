import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/money.dart';

void main() {
  group('construction', () {
    test('zero', () {
      expect(const Money.zero().paise, 0);
      expect(const Money.zero().isZero, isTrue);
    });

    test('fromRupees', () {
      expect(Money.fromRupees(10).paise, 1000);
      expect(Money.fromRupees(10, paise: 50).paise, 1050);
      expect(Money.fromRupees(0, paise: 5).paise, 5);
    });

    test('negative values are legal (refunds/credits)', () {
      expect(const Money(-150).isNegative, isTrue);
      expect(const Money(-150).formatPlain(), '-₹1.50');
    });
  });

  group('tryParse', () {
    test('plain integers', () {
      expect(Money.tryParse('1234'), const Money(123400));
      expect(Money.tryParse('0'), const Money(0));
    });

    test('rupee symbol and spaces', () {
      expect(Money.tryParse('₹1,23,456.78'), const Money(12345678));
      expect(Money.tryParse('₹ 99'), const Money(9900));
      expect(Money.tryParse(' 12 '), const Money(1200));
    });

    test('western grouping also accepted', () {
      expect(Money.tryParse('1,000,000'), Money.fromRupees(1000000));
    });

    test('decimals pad to paise', () {
      expect(Money.tryParse('12.5'), const Money(1250));
      expect(Money.tryParse('0.05'), const Money(5));
      expect(Money.tryParse('-50.25'), const Money(-5025));
    });

    test('negative', () {
      expect(Money.tryParse('-99'), const Money(-9900));
    });

    test('rejects garbage', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('₹'), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1.234'), isNull); // 3 decimals
      expect(Money.tryParse('1.2.3'), isNull);
      expect(Money.tryParse('--5'), isNull);
      expect(Money.tryParse('₹12.'), isNull);
      expect(Money.tryParse('9999999999'), isNull); // 10 digits
      expect(Money.tryParse('12a'), isNull);
    });
  });

  group('arithmetic', () {
    test('add / subtract', () {
      expect(const Money(100) + const Money(50), const Money(150));
      expect(const Money(50) - const Money(100), const Money(-50));
    });

    test('negate and abs', () {
      expect(-const Money(250), const Money(-250));
      expect(const Money(-250).abs(), const Money(250));
    });

    test('integer scaling', () {
      expect(const Money(333) * 3, const Money(999));
    });

    test('comparisons', () {
      expect(const Money(1) < const Money(2), isTrue);
      expect(const Money(2) <= const Money(2), isTrue);
      expect(const Money(3) > const Money(2), isTrue);
      expect(const Money(2) >= const Money(2), isTrue);
      expect(const Money(-1) < const Money(0), isTrue);
    });

    test('compareTo orders like paise', () {
      final list = <Money>[const Money(300), const Money(100), const Money(200)];
      list.sort();
      expect(list.map((Money m) => m.paise).toList(), <int>[100, 200, 300]);
    });

    test('equality and hashCode are paise-based', () {
      expect(const Money(1050), Money.fromRupees(10, paise: 50));
      expect(const Money(1050).hashCode, const Money(1050).hashCode);
      expect(const Money(1) == const Money(2), isFalse);
    });

    test('accessors', () {
      expect(const Money(12345).wholeRupees, 123);
      expect(const Money(12345).fractionalPaise, 45);
      expect(const Money(-150).wholeRupees, -1); // truncated toward zero
      expect(const Money(-150).fractionalPaise, 50);
    });
  });

  group('formatPlain', () {
    test('exact two-decimal form', () {
      expect(const Money(0).formatPlain(), '₹0.00');
      expect(const Money(1050).formatPlain(), '₹10.50');
      expect(const Money(5).formatPlain(), '₹0.05');
      expect(const Money(-123450).formatPlain(), '-₹1,234.50');
    });

    test('Indian digit grouping', () {
      expect(Money.fromRupees(12345678).formatPlain(), '₹1,23,45,678.00');
      expect(Money.fromRupees(1000).formatPlain(), '₹1,000.00');
      expect(Money.fromRupees(999).formatPlain(), '₹999.00');
    });
  });

  group('formatHi', () {
    test('sub-rupee reads as paise', () {
      expect(const Money(50).formatHi(), '50p');
      expect(const Money(-50).formatHi(), '-50p');
    });

    test('small rupees keep decimals', () {
      expect(const Money(1050).formatHi(), '₹10.50');
      expect(const Money(1000).formatHi(), '₹10');
    });

    test('thousands to just-below-lakh use grouping', () {
      expect(Money.fromRupees(1234).formatHi(), '₹1,234');
      expect(Money.fromRupees(99999).formatHi(), '₹99,999');
    });

    test('lakh band', () {
      expect(Money.fromRupees(100000).formatHi(), '₹1 lakh');
      expect(Money.fromRupees(120000).formatHi(), '₹1.2 lakh'); // spec example
      expect(Money.fromRupees(123456).formatHi(), '₹1.23 lakh');
      expect(Money.fromRupees(-120000).formatHi(), '-₹1.2 lakh');
    });

    test('crore band', () {
      expect(Money.fromRupees(10000000).formatHi(), '₹1 crore'); // 1 crore = 10^7 rupees
      expect(Money.fromRupees(12345678).formatHi(), '₹1.23 crore'); // 1,23,45,678 = 1.2345678 crore
      expect(Money.fromRupees(1000000000).formatHi(), '₹100 crore');
    });

    test('zero', () {
      expect(const Money(0).formatHi(), '₹0');
    });
  });

  group('json round-trip', () {
    test('toJson/fromJson', () {
      for (final paise in <int>[0, 1, -50, 999999999, -12345]) {
        final money = Money(paise);
        expect(Money.fromJson(money.toJson()), money);
      }
    });

    test('fromJson rejects non-int paise', () {
      expect(
        () => Money.fromJson(<String, Object?>{'paise': '100'}),
        throwsFormatException,
      );
      expect(
        () => Money.fromJson(<String, Object?>{}),
        throwsFormatException,
      );
    });
  });

  test('toString uses exact format', () {
    expect(const Money(1050).toString(), 'Money(₹10.50)');
  });
}
