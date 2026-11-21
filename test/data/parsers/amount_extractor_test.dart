// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/data/parsers/amount_extractor.dart';

void main() {
  group('AmountExtractor.extractPaise', () {
    test('₹ symbol, whole rupees', () {
      expect(AmountExtractor.extractPaise('₹150 sent'), 15000);
    });

    test('₹ with decimals', () {
      expect(AmountExtractor.extractPaise('₹148.50 paid'), 14850);
    });

    test('₹ with comma grouping', () {
      expect(AmountExtractor.extractPaise('₹1,250 done'), 125000);
    });

    test('Indian lakh-style grouping', () {
      expect(AmountExtractor.extractPaise('₹1,2,34,567'), 123456700);
    });

    test('Rs. prefix', () {
      expect(AmountExtractor.extractPaise('Rs.500 debited'), 50000);
    });

    test('Rs without dot', () {
      expect(AmountExtractor.extractPaise('Rs 45 debited'), 4500);
    });

    test('INR prefix', () {
      expect(AmountExtractor.extractPaise('INR 350 debited'), 35000);
    });

    test('case-insensitive rs/inr', () {
      expect(AmountExtractor.extractPaise('rs.99 paid'), 9900);
      expect(AmountExtractor.extractPaise('inr 12 paid'), 1200);
    });

    test('sub-rupee amounts', () {
      expect(AmountExtractor.extractPaise('₹0.50 sent'), 50);
    });

    test('single paise digit rounds to tens', () {
      expect(AmountExtractor.extractPaise('₹2.5'), 250);
    });

    test('Devanagari digits normalize', () {
      expect(AmountExtractor.extractPaise('₹१५० भेजा'), 15000);
    });

    test('skips balance amounts in context', () {
      expect(
        AmountExtractor.extractPaise(
          'Rs.250 debited. Avl Bal Rs.12,345.67.',
        ),
        25000,
      );
    });

    test('balance-first text still finds the txn amount', () {
      expect(
        AmountExtractor.extractPaise(
          'Avl Bal Rs.45,000. Rs.250 debited from A/c XX11.',
        ),
        25000,
      );
    });

    test('skips "available balance" wording', () {
      expect(
        AmountExtractor.extractPaise(
          'Your available balance is Rs.9,999. Rs.30 spent.',
        ),
        3000,
      );
    });

    test('no marker means no amount', () {
      expect(AmountExtractor.extractPaise('salary will come on 1st'), isNull);
    });

    test('rs inside a word does not count', () {
      expect(AmountExtractor.extractPaise('years 500 passed'), isNull);
    });

    test('empty and junk inputs are null', () {
      expect(AmountExtractor.extractPaise(''), isNull);
      expect(AmountExtractor.extractPaise('no numbers here'), isNull);
    });

    test('normalizeDigits maps Devanagari and Arabic-Indic', () {
      expect(AmountExtractor.normalizeDigits('१२३'), '123');
      expect(AmountExtractor.normalizeDigits('٤٥٦'), '456');
      expect(AmountExtractor.normalizeDigits('abc'), 'abc');
    });
  });
}
