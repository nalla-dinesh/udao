// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/data/parsers/filters.dart';
import 'package:udao/data/parsers/parser_types.dart';

ParserInput _sms(String text, {String? sender}) =>
    ParserInput(text: text, receivedAt: DateTime(2026, 10, 27), sender: sender);

void main() {
  group('OtpFilter', () {
    final OtpFilter f = OtpFilter();

    test('drops OTP with code', () {
      expect(f.check(_sms('Your OTP is 4832. Do not share.')).isDrop, isTrue);
      expect(
        f.check(_sms('Your OTP is 4832.')).dropReason,
        'otp_security',
      );
    });

    test('drops one-time password phrasing', () {
      expect(
        f.check(_sms('123456 is your One Time Password (OTP)'))
            .dropReason,
        'otp_security',
      );
    });

    test('drops verification code phrasing', () {
      expect(
        f.check(_sms('Use verification code 998877 to login')).dropReason,
        'otp_security',
      );
    });

    test('drops CVV security-code warnings', () {
      expect(
        f.check(_sms('Never share CVV. Security code 4321 alert.'))
            .dropReason,
        'otp_security',
      );
    });

    test('passes real txn text mentioning money', () {
      expect(
        f.check(_sms('Rs.250 debited from A/c XX11 REF 512345678 SWIGGY.'))
            .isDrop,
        isFalse,
      );
    });

    test('passes text with digits but no OTP words', () {
      expect(f.check(_sms('Order 12345 shipped')).isDrop, isFalse);
    });

    test('passes OTP word without a code-like number', () {
      expect(f.check(_sms('Your OTP will arrive shortly')).isDrop, isFalse);
    });
  });

  group('PromoFilter', () {
    final PromoFilter f = PromoFilter();

    test('drops flat-off offers', () {
      expect(
        f.check(_sms('FLAT 50% OFF on orders above Rs.500!')).dropReason,
        'promo_marketing',
      );
    });

    test('drops percentage-off offers', () {
      expect(
        f.check(_sms('Get 30% off on your next order')).dropReason,
        'promo_marketing',
      );
    });

    test('drops prize spam', () {
      expect(
        f.check(_sms('Congratulations! You have won a Rs.10000 prize'))
            .dropReason,
        'promo_marketing',
      );
    });

    test('drops unsubscribe footers', () {
      expect(
        f.check(_sms('Reply STOP to unsubscribe from offers')).dropReason,
        'promo_marketing',
      );
    });

    test('drops marketing-sender + shop text', () {
      expect(
        f.check(
          _sms('New arrivals in our shop!', sender: 'JM-MYSHOP'),
        ).dropReason,
        'promo_marketing',
      );
    });

    test('passes transactional debits', () {
      expect(
        f.check(
          _sms('Rs.99 debited on 27-10-26', sender: 'VM-HDFCBK'),
        ).isDrop,
        isFalse,
      );
    });

    test('sender alone never drops a clean body', () {
      expect(
        f.check(_sms('Your order is out for delivery', sender: 'JM-SHIP'))
            .isDrop,
        isFalse,
      );
    });
  });
}
