// phase-04
// Hinglish amount + intent parsing for the Bolo (voice) tab — and
// anything else that gets a human sentence. Pure text → structured
// draft; the USER confirms, always.
//
// Coverage (the 60-case test table hangs off this):
//   digits        `60`, `60 rupaye`, `1.2k`, `2 lakh 50`, `₹125`
//   Hindi words   `ek..das`, 11–19 (gyaarah…unnees), tens (bees,
//                 pachees, battis, paintis, chalis, pachaas, saath,
//                 sattar, assi, nabbe), `sau`, `hazaar/hazar`,
//                 `lakh`, `karod`
//   English       `one..nineteen`, tens `twenty..ninety`, `hundred`,
//                 `thousand`, `eleven hundred`
//   fractions     `sawa`/`derh`/`paune` adjust the FOLLOWING group by
//                 ± a quarter/half of that group's UNIT (sawa sau =
//                 125, paune do sau = 175, derh sau = 150); `adha`
//                 halves the group (`adha sau` = 50, `adha` alone =
//                 50)
//   composition   `do sau pachaas` = 250 · `sau pachaas` = 150 ·
//                 `do sau` = 200 · `2 lakh 50` = 250000
//   direction     default debit; `mila/milaya/refund/paisa aaya/
//                 aaye the` → credit
//   merchant      first token that maps to a Categorizer alias
//                 (`auto`, `chai`, `milk`, `petrol`, …)
//
// Unknown words are NOT errors — they become `unknownTail` and the
// UI asks "Kya ye sahi hai?" with chips. Paise only; doubles banned.
import 'package:udao/data/parsers/amount_extractor.dart';
import 'package:udao/features/capture/pipeline/categorizer.dart';

class HinglishDraft {
  const HinglishDraft({
    required this.amountPaise,
    required this.credit,
    required this.merchantHint,
    required this.categoryId,
    required this.unknownTail,
    required this.confidence,
  });

  /// Parsed amount, null when nothing numeric was understood.
  final int? amountPaise;

  /// true = money came IN (`mila`, `milaya`, refund…).
  final bool credit;

  /// The merchant-ish word as spoken (`auto`), if any.
  final String? merchantHint;

  final String? categoryId;

  /// Words the parser could not consume — shown as confirm chips.
  final List<String> unknownTail;

  /// 1.0 when amount + merchant both landed cleanly; every unknown
  /// tail word shaves it (drives the "Kya ye sahi hai?" emphasis).
  final double confidence;
}

abstract final class HinglishAmountParser {
  // ---- vocabulary ---------------------------------------------------

  static const Map<String, int> _units = <String, int>{
    'ek': 1, 'do': 2, 'teen': 3, 'char': 4, 'chaar': 4, 'panch': 5,
    'chhah': 6, 'chhe': 6, 'chah': 6, 'saat': 7, 'aath': 8, 'nau': 9,
    'das': 10,
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
    'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14,
    'fifteen': 15, 'sixteen': 16, 'seventeen': 17, 'eighteen': 18,
    'nineteen': 19,
    'gyaarah': 11, 'gyarah': 11, 'baarah': 12, 'barah': 12,
    'terah': 13, 'chaudah': 14, 'pandrah': 15, 'solah': 16,
    'satrah': 17, 'atharah': 18, 'unnees': 19,
  };

  static const Map<String, int> _tens = <String, int>{
    'bees': 20, 'pachees': 25, 'battis': 30, 'paintis': 35,
    'chalis': 40, 'pintalis': 45, 'pachaas': 50, 'pachpan': 55,
    'saath': 60, 'sattar': 70, 'assi': 80, 'nabbe': 90,
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };

  static const Map<String, int> _scales = <String, int>{
    'sau': 100, 'hundred': 100,
    'hazaar': 1000, 'hazar': 1000, 'thousand': 1000,
    'lakh': 100000, 'lac': 100000,
    'karod': 10000000, 'crore': 10000000,
    // `1.2k` / `2k` suffix (also stands alone after a numeral).
    'k': 1000,
  };

  /// Fraction prefix words — handled positionally, not as factors
  /// (see flushGroup for the ±unit semantics).
  static const Set<String> _fractions = <String>{
    'sawa', 'derh', 'dedh', 'paune', 'adha', 'aadha',
  };

  /// Words that mean money arrived.
  static const List<String> _creditWords = <String>[
    'mila', 'mile', 'milaya', 'milaye', 'refund', 'wapas', 'aaya',
    'aaye',
  ];

  /// Currency noise never treated as merchant or amount.
  static const Set<String> _noise = <String>{
    'rupaye', 'rupees', 'rupee', 'rs', 'inr', 'ka', 'ki', 'ke',
    'the', 'tha', 'hai', 'pe', 'par', 'se', 'ne', 'bhara',
    'diya', 'lenaa', 'kharida', 'liya', 'gaya', 'abhi', 'just',
    'now', 'today', 'aaj', 'kal',
  };

  static HinglishDraft parse(String spoken) {
    final String text = AmountExtractor.normalizeDigits(spoken)
        .toLowerCase()
        .replaceAll(RegExp(r'[₹,]'), ' ')
        .replaceAll(RegExp(r'[^0-9a-z. ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) {
      return const HinglishDraft(
        amountPaise: null,
        credit: false,
        merchantHint: null,
        categoryId: null,
        unknownTail: <String>[],
        confidence: 0,
      );
    }

    final List<String> tokens = text.split(' ');
    final List<String> unknown = <String>[];
    bool credit = false;
    String? merchant;
    String? categoryId;

    double total = 0; // rupee accumulator (fractions need the
    // double; the result is whole-paise verified before use)
    double pendingNumber = 0;
    String? pendingFraction;
    int? groupScale; // unit of the group's terminal scale word
    bool pendingFromNumeral = false;
    bool lastGroupWasBig = false; // previous flush was lakh/karod

    void flushGroup() {
      double group = pendingNumber;
      if (pendingFraction != null && group == 0) {
        // Bare fraction word (`adha`): assume a hundred.
        group = 100;
      }
      if (pendingFraction != null) {
        // ± quarter/half of the group's UNIT, not of the group —
        // `paune do sau` = 200 − 25 = 175.
        final double unit = (groupScale ?? 100).toDouble();
        switch (pendingFraction) {
          case 'sawa':
            group += unit / 4;
          case 'derh' || 'dedh':
            group += unit / 2;
          case 'paune':
            group -= unit / 4;
          case 'adha' || 'aadha':
            group /= 2;
        }
        pendingFraction = null;
      } else if (lastGroupWasBig &&
          groupScale == null &&
          group > 0 &&
          group < 100) {
        // The lakh idiom: `2 lakh 50` = 2,50,000 — a small bare
        // number right after a lakh/karod group is THOUSANDS.
        group *= 1000;
      }
      total += group;
      if (group > 0) {
        // Empty inter-group flushes must not clobber the idiom state.
        lastGroupWasBig =
            groupScale != null && groupScale! >= 100000;
      }
      pendingNumber = 0;
      groupScale = null;
      pendingFromNumeral = false;
    }

    for (int i = 0; i < tokens.length; i++) {
      final String t = tokens[i];

      // Numerals, with optional decimal and `k` suffix: `60`,
      // `1.2`, `1.2k`, `2K`.
      final RegExpMatch? num =
          RegExp(r'^(\d+(?:\.\d{1,3})?)(k)?$').firstMatch(t);
      if (num != null) {
        flushGroup();
        pendingNumber = double.parse(num.group(1)!) *
            (num.group(2) != null ? 1000 : 1);
        pendingFromNumeral = true;
        continue;
      }

      if (_fractions.contains(t)) {
        flushGroup();
        pendingFraction = t;
        continue;
      }

      if (_units.containsKey(t)) {
        // A unit after a completed scale group starts a new,
        // additive group (`sau pachaas` → 100 + 50).
        if (pendingFromNumeral || pendingNumber >= 100) {
          flushGroup();
        }
        pendingNumber += _units[t]!;
        continue;
      }

      if (_tens.containsKey(t)) {
        if (pendingFromNumeral || pendingNumber >= 100) {
          flushGroup();
        }
        pendingNumber += _tens[t]!;
        continue;
      }

      if (_scales.containsKey(t)) {
        final int scale = _scales[t]!;
        // `eleven hundred`: unit then scale multiplies. `do sau`:
        // 2 × 100. A scale with no pending number counts itself
        // (`sau` = 100; `k` after `1.2` = ×1000).
        final double base = pendingNumber == 0 ? 1 : pendingNumber;
        pendingNumber = base * scale;
        groupScale = scale;
        flushGroup();
        continue;
      }

      if (_noise.contains(t)) {
        continue;
      }

      if (!credit && _creditWords.contains(t)) {
        credit = true;
        continue;
      }

      // Merchant hint: first Categorizer-matching token.
      if (merchant == null) {
        final String? cat = Categorizer.assign(t);
        if (cat != null) {
          merchant = t;
          categoryId = cat;
          continue;
        }
      }

      unknown.add(t);
    }
    flushGroup();

    final int? paise = _toIntPaise(total);
    double confidence = 0;
    if (paise != null && paise > 0) {
      confidence = 1;
      if (merchant == null) {
        confidence -= 0.2;
      }
      confidence -= 0.1 * unknown.length;
    }
    if (confidence < 0) {
      confidence = 0;
    }

    return HinglishDraft(
      amountPaise: paise == null || paise <= 0 ? null : paise,
      credit: credit,
      merchantHint: merchant,
      categoryId: categoryId,
      unknownTail: unknown,
      confidence: confidence,
    );
  }

  /// Fraction math (`sawa sau` = 125.0) must land on a whole paise
  /// count; guard the round-off explicitly.
  static int? _toIntPaise(double total) {
    if (total <= 0) {
      return null;
    }
    final double rounded = (total * 100).roundToDouble() / 100;
    final int paise = (rounded * 100).round();
    return paise;
  }
}
