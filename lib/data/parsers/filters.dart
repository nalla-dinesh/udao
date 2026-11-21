// phase-02
// Pre-parser guards: OTPs and marketing noise are dropped before any
// parser runs. Each has a stable drop code the repo persists on the
// capture_event row.
import 'package:udao/data/parsers/parser_types.dart';

/// What a filter decided: pass, or drop with a code.
class FilterVerdict {
  const FilterVerdict.pass() : dropReason = null;
  const FilterVerdict.drop(this.dropReason);
  final String? dropReason;

  bool get isDrop => dropReason != null;
}

/// No-transaction noise: OTPs, CVV warnings, password resets.
class OtpFilter {
  static final RegExp _otpWords = RegExp(
    r'\b(otp|one[\s-]?time (password|code)|verification code|cvv|secure ?code)\b',
    caseSensitive: false,
  );
  static final RegExp _codeNumber = RegExp(r'\b\d{4,8}\b');

  /// Drop only when OTP language AND a code-like number coexist.
  FilterVerdict check(ParserInput input) {
    if (_otpWords.hasMatch(input.text) && _codeNumber.hasMatch(input.text)) {
      return const FilterVerdict.drop('otp_security');
    }
    return const FilterVerdict.pass();
  }
}

/// Marketing noise: offers, sales, coupons, prize spam.
class PromoFilter {
  static final RegExp _promoWords = RegExp(
    r'\b(flat \d+ ?% ?off|\d+ ?% ?off|offer|offers|sale|coupon|discount|deal of the day|'
    r'prize|lucky draw|congratulations! you (won|have won)|unsubscribe|'
    r'click (here|now) to (win|claim)|cashback offer|reward points offer)\b',
    caseSensitive: false,
  );
  static final RegExp _marketingSender = RegExp(
    r'^(jm|jd|lm|ad|vm)-?[a-z0-9]{2,10}',
    caseSensitive: false,
  );

  FilterVerdict check(ParserInput input) {
    if (_promoWords.hasMatch(input.text)) {
      return const FilterVerdict.drop('promo_marketing');
    }
    final String? sender = input.sender;
    // Six-char transactional senders (VM-HDFCBK) are real; ad-channel
    // prefixes with marketing bodies are noise. Sender alone never
    // drops — bodies with offers already matched above.
    if (sender != null &&
        _marketingSender.hasMatch(sender) &&
        RegExp('shop|sale|offer', caseSensitive: false)
            .hasMatch(input.text)) {
      return const FilterVerdict.drop('promo_marketing');
    }
    return const FilterVerdict.pass();
  }
}
