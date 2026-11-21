// Money — UDAO's monetary value type.
//
// EVERY monetary value in UDAO is an integer number of **paise**
// (1 rupee = 100 paise). **Doubles are banned in monetary code**:
// binary floating point cannot represent `0.10` exactly and silently
// corrupts sums. All arithmetic here is 64-bit integer math.
//
// Negative values are allowed (refunds, credits, adjustments).
class Money implements Comparable<Money> {
  const Money(this.paise);

  /// ₹0.00.
  const Money.zero() : this(0);

  static const int paisePerRupee = 100;

  /// Whole rupees + optional leftover paise.
  factory Money.fromRupees(int rupees, {int paise = 0}) =>
      Money(rupees * paisePerRupee + paise);

  /// Parses common user/bank formats: `₹1,23,456.78`, `1,234.5`,
  /// `₹ 99`, `-50.25`, `0`. Indian and western comma grouping are both
  /// accepted (commas are stripped). At most two decimals; at most nine
  /// integer digits (int64 overflow guard). Returns `null` on mismatch.
  static Money? tryParse(String input) {
    final cleaned = input
        .replaceAll('₹', '')
        .replaceAll(',', '')
        .replaceAll(' ', '');
    if (cleaned.isEmpty) {
      return null;
    }
    final match = RegExp(r'^-?\d{1,9}(\.\d{1,2})?$').firstMatch(cleaned);
    if (match == null) {
      return null;
    }
    final negative = cleaned.startsWith('-');
    final unsigned = negative ? cleaned.substring(1) : cleaned;
    final dot = unsigned.indexOf('.');
    final rupeesPart = dot == -1 ? unsigned : unsigned.substring(0, dot);
    final paisePart = dot == -1 ? '' : unsigned.substring(dot + 1);
    final rupees = int.tryParse(rupeesPart);
    if (rupees == null) {
      return null;
    }
    final paiseOnly = dot == -1 ? 0 : int.tryParse(paisePart.padRight(2, '0'));
    if (paiseOnly == null) {
      return null;
    }
    final value = rupees * paisePerRupee + paiseOnly;
    return Money(negative ? -value : value);
  }

  /// Parses machine JSON produced by [toJson].
  factory Money.fromJson(Map<String, Object?> json) {
    final raw = json['paise'];
    if (raw is int) {
      return Money(raw);
    }
    throw FormatException('Money.fromJson: "paise" must be int, got `$raw`');
  }

  /// The paise amount — the single source of truth.
  final int paise;

  Money operator +(Money other) => Money(paise + other.paise);

  Money operator -(Money other) => Money(paise - other.paise);

  Money operator -() => Money(-paise);

  /// Integer scaling (multiply BEFORE any division — splits divide).
  Money operator *(int factor) => Money(paise * factor);

  bool operator <(Money other) => paise < other.paise;

  bool operator <=(Money other) => paise <= other.paise;

  bool operator >(Money other) => paise > other.paise;

  bool operator >=(Money other) => paise >= other.paise;

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise;

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  bool get isZero => paise == 0;

  bool get isNegative => paise < 0;

  Money abs() => Money(paise.abs());

  /// Whole rupees, truncated toward zero (pure integer math).
  int get wholeRupees => paise.sign * (paise.abs() ~/ paisePerRupee);

  /// The paise fraction of the absolute value (0–99).
  int get fractionalPaise => paise.abs() % paisePerRupee;

  /// `₹1,234.50` — exact, always two decimals, Indian digit grouping.
  String formatPlain() {
    final sign = isNegative ? '-' : '';
    final a = paise.abs();
    final r = a ~/ paisePerRupee;
    final p = a % paisePerRupee;
    return '$sign₹${_groupIndian(r)}.${p.toString().padLeft(2, '0')}';
  }

  /// Desi short format: `50p`, `₹10.50`, `₹1,234`, `₹1.2 lakh`,
  /// `₹3.45 crore`. Values ≥ ₹1,000 display whole rupees only (paise
  /// drop from the *display*, never from the stored value).
  String formatHi() {
    final sign = isNegative ? '-' : '';
    final a = paise.abs();
    if (a == 0) {
      return '₹0';
    }
    if (a < paisePerRupee) {
      return '$sign${a}p';
    }
    final r = a ~/ paisePerRupee;
    final p = a % paisePerRupee;
    if (r < 1000) {
      return p == 0 ? '$sign₹$r' : '$sign₹$r.${p.toString().padLeft(2, '0')}';
    }
    if (r < 100000) {
      return '$sign₹${_groupIndian(r)}';
    }
    if (r < 10000000) {
      return '$sign₹${_scaled(r, 100000)} lakh';
    }
    return '$sign₹${_scaled(r, 10000000)} crore';
  }

  /// `r` scaled by `unit` with two integer-computed decimals and
  /// trailing zeros trimmed — no floating point anywhere.
  static String _scaled(int r, int unit) {
    final whole = r ~/ unit;
    final hundredths = ((r % unit) * 100) ~/ unit;
    if (hundredths == 0) {
      return whole.toString();
    }
    var text = hundredths.toString().padLeft(2, '0');
    if (text.endsWith('0')) {
      text = text.substring(0, 1);
    }
    return '$whole.$text';
  }

  /// Indian digit grouping: `12,34,567`.
  static String _groupIndian(int n) {
    final String s = n.toString();
    if (s.length <= 3) {
      return s;
    }
    final String head = s.substring(0, s.length - 3);
    final String tail = s.substring(s.length - 3);
    // Groups of two from the right of `head`, collected front-first.
    final List<String> groups = <String>[
      for (int i = head.length; i > 0; i -= 2)
        head.substring(i - 2 > 0 ? i - 2 : 0, i),
    ];
    return '${groups.reversed.join(',')},$tail';
  }

  Map<String, Object?> toJson() => <String, Object?>{'paise': paise};

  @override
  String toString() => 'Money(${formatPlain()})';
}
