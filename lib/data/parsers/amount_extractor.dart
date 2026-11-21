// phase-02
// Rupee extraction from Indian money text — ₹ symbols, Rs/INR
// prefixes, lakh-comma grouping, decimals, Devanagari digits, and
// balance-text avoidance.
import 'dart:math';

abstract final class AmountExtractor {
  /// Devanagari + Arabic-Indic digits → ASCII, so `₹१५०` parses.
  static const Map<String, String> _digitNormalize = <String, String>{
    '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
    '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  };

  /// Currency-marked amount: `₹1,234.50`, `Rs. 500`, `INR 999`,
  /// `Rs:1,2,3,4` (Indian grouping), `₹ १५०`.
  static final RegExp _marked = RegExp(
    r'(?:₹|\brs\.?|\binr)\s*([0-9٠-९][0-9٠-९,]*(?:\.[0-9٠-९]{1,2})?)',
    caseSensitive: false,
  );

  /// Text that means "this number is the balance, not the txn".
  static final RegExp _balanceContext = RegExp(
    r'(bal|available|avail|a\/c bal|account balance)',
    caseSensitive: false,
  );

  /// Extracts the txn amount in paise, or null when no credible
  /// currency-marked number exists.
  static int? extractPaise(String rawText) {
    final String text = normalizeDigits(rawText);
    final Iterable<RegExpMatch> matches = _marked.allMatches(text);

    // Balance markers only poison the text *since the previous
    // amount* — a lookback of fixed width would let "Avl Bal" from
    // one amount wrongly veto the next.
    int lastEnd = 0;
    for (final RegExpMatch m in matches) {
      final String segment = text.substring(lastEnd, m.start);
      lastEnd = m.end;
      if (_balanceContext.hasMatch(segment)) {
        continue;
      }
      final int? paise = _digitsToPaise(m.group(1)!);
      if (paise == null) {
        continue;
      }
      // First non-balance currency amount wins — bank texts state the
      // txn amount before the balance.
      return paise;
    }
    return null;
  }

  /// Digit normalisation pass (also collapses stray full-width forms).
  static String normalizeDigits(String text) {
    if (text.isEmpty) {
      return text;
    }
    final StringBuffer out = StringBuffer();
    for (final String ch in text.runes.map(String.fromCharCode)) {
      out.write(_digitNormalize[ch] ?? ch);
    }
    return out.toString();
  }

  static int? _digitsToPaise(String digits) {
    final String cleaned = digits.replaceAll(',', '');
    if (cleaned.isEmpty || cleaned == '.') {
      return null;
    }
    final List<String> parts = cleaned.split('.');
    final String wholeStr = parts[0].isEmpty ? '0' : parts[0];
    final int whole = int.tryParse(wholeStr) ?? -1;
    if (whole < 0 || whole > 10000000000) {
      return null;
    }
    int paise = whole * 100;
    if (parts.length == 2 && parts[1].isNotEmpty) {
      final int frac = int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0;
      paise += frac;
    }
    return min(paise, 1 << 53);
  }
}
