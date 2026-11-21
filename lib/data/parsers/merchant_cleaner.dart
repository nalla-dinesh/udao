// phase-02
// Turns raw counterparty strings (`SWIGGY  BANGALORE`, `Zepto
// Technologies Pvt Ltd`) into display names (`Swiggy`, `Zepto`).
//
// Two-stage: strip corporate noise suffixes, then alias-table lookup
// on a squashed key; unmatched names get Title-cased as-is.
abstract final class MerchantCleaner {
  /// Corporate suffix/noise words stripped from the tail (iteratively
  /// — `Technologies Private Limited` takes three passes).
  static const List<String> _noiseTail = <String>[
    'private', 'pvt', 'ltd', 'limited', 'llp', 'india', 'pvt ltd',
    'technologies', 'technology', 'solutions', 'services', 'enterprises',
    'traders', 'trading', 'retail', 'stores', 'store', 'company', 'co',
    'and', 'the', 'shop', 'outlet', 'branch',
  ];

  /// Squashed-key → display form. Key = lowercase, only [a-z0-9].
  /// 60 curated Indian-consumer aliases.
  static const Map<String, String> aliases = <String, String>{
    'swiggy': 'Swiggy',
    'zomato': 'Zomato',
    'blinkit': 'Blinkit',
    'blinkitindia': 'Blinkit',
    'zepto': 'Zepto',
    'zeptoindia': 'Zepto',
    'bigbasket': 'BigBasket',
    'bbnow': 'BigBasket',
    'bbdaily': 'BB Daily',
    'instamart': 'Instamart',
    'swiggyinstamart': 'Instamart',
    'amazon': 'Amazon',
    'amzn': 'Amazon',
    'amazonpay': 'Amazon Pay',
    'flipkart': 'Flipkart',
    'myntra': 'Myntra',
    'ajio': 'AJIO',
    'meesho': 'Meesho',
    'jiomart': 'JioMart',
    'dmart': 'DMart',
    'avenuesupermarts': 'DMart',
    'reliancefresh': 'Reliance Fresh',
    'reliancesmart': 'Reliance Smart',
    'smartpoint': 'Smart Point',
    'uber': 'Uber',
    'uberindia': 'Uber',
    'ola': 'Ola',
    'olatechnologies': 'Ola',
    'anitechnologies': 'Ola',
    'rapido': 'Rapido',
    'nammayatri': 'Namma Yatri',
    'irctc': 'IRCTC',
    'dominos': "Domino's",
    'dominospizza': "Domino's",
    'jubilantfoodworks': "Domino's",
    'pizzahut': 'Pizza Hut',
    'kfc': 'KFC',
    'mcdonalds': "McDonald's",
    'mcd': "McDonald's",
    'starbucks': 'Starbucks',
    'tatastarbucks': 'Starbucks',
    'cafecoffeeday': 'CCD',
    'ccd': 'CCD',
    'chaipoint': 'Chai Point',
    'netflix': 'Netflix',
    'amazonprime': 'Amazon Prime',
    'primevideo': 'Amazon Prime',
    'hotstar': 'Hotstar',
    'disneyhotstar': 'Hotstar',
    'spotify': 'Spotify',
    'youtubepremium': 'YouTube Premium',
    'googleyoutube': 'YouTube Premium',
    'zee5': 'ZEE5',
    'sonyliv': 'SonyLIV',
    'airtel': 'Airtel',
    'bhartiairtel': 'Airtel',
    'jio': 'Jio',
    'reliancejio': 'Jio',
    'vodafoneidea': 'Vi',
    'vi': 'Vi',
    'bses': 'BSES',
    'bsesyamuna': 'BSES Yamuna',
    'bsesrajdhani': 'BSES Rajdhani',
    'tatapower': 'Tata Power',
    'adanielectricity': 'Adani Electricity',
    'indanegas': 'Indane Gas',
    'bharatgas': 'Bharat Gas',
    'hpgas': 'HP Gas',
    'paytm': 'Paytm',
    'one97': 'Paytm',
    'phonepe': 'PhonePe',
    'gpay': 'Google Pay',
    'googlepay': 'Google Pay',
    'paytmupi': 'Paytm',
    'paytmmoney': 'Paytm Money',
    'groww': 'Groww',
    'zerodha': 'Zerodha',
    'upstox': 'Upstox',
    'angelone': 'Angel One',
  };

  /// Trailing channel phrases: `via UPI`, `using PhonePe`,
  /// `on Google Pay`, `through BHIM UPI` …
  static final RegExp _channelNoise = RegExp(
    r'\s+(?:via|using|on|through)\s+'
    r'(?:upi|gpay|google pay|phonepe|paytm|bhim|imps|neft)'
    r'(?:\s+upi)?\s*$',
    caseSensitive: false,
  );

  /// Strips trailing channel phrases from a captured counterparty.
  static String stripChannelNoise(String s) =>
      s.replaceAll(_channelNoise, '').trim();

  /// Main entry: raw counterparty → clean display name.
  static String clean(String raw) {
    if (raw.trim().isEmpty) {
      return '';
    }
    // VPAs are identifiers, not names — pass through untouched.
    if (raw.contains('@')) {
      return raw.trim();
    }
    // 1. Collapse whitespace and strip bracketed/location noise.
    String s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '');
    s = _stripNoiseTail(s);

    // 2. Alias lookup on the squashed key.
    final String squashed = _squash(s);
    final String? aliased = aliases[squashed];
    if (aliased != null) {
      return aliased;
    }

    // 3. Fallback: strip punctuation edges, Title-case words.
    s = s.replaceAll(RegExp(r'^[\W_]+|[\W_]+$'), '');
    if (s.isEmpty) {
      return raw.trim();
    }
    return _titleCase(s);
  }

  /// Alias check without cleaning (subscription matcher uses this).
  static String? aliasOf(String raw) => aliases[_squash(raw)];

  static String _stripNoiseTail(String s) {
    bool changed = true;
    while (changed) {
      changed = false;
      final int lastSpace = s.lastIndexOf(' ');
      final String last =
          lastSpace < 0 ? s : s.substring(lastSpace + 1).trim();
      final String squashed = _squash(last);
      if (squashed.isNotEmpty && _noiseTail.contains(squashed)) {
        s = (lastSpace < 0 ? '' : s.substring(0, lastSpace)).trim();
        changed = true;
      }
      // Also drop trailing legal punctuation.
      final String trimmedPunct =
          s.replaceAll(RegExp(r'[\.,\-&]+$'), '').trim();
      if (trimmedPunct.length != s.length) {
        s = trimmedPunct;
        changed = true;
      }
      if (s.isEmpty) {
        return s;
      }
    }
    return s;
  }

  static String _squash(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _titleCase(String s) {
    return s.split(' ').map((String word) {
      if (word.isEmpty) {
        return word;
      }
      // Preserve tiny all-caps tokens (KFC-like, <=3 letters) and
      // genuinely mixed-case brands (DMart, iPhone). Everything else
      // ALL-CAPS is shouting, not a brand: "RAMESH" -> "Ramesh".
      // Real acronyms (IRCTC, BSES, ZEE5…) live in the alias table.
      final bool allUpper =
          word == word.toUpperCase() && word.length <= 3;
      final String rest = word.substring(1);
      final bool camelish = rest.contains(RegExp(r'[A-Z]')) &&
          rest.contains(RegExp(r'[a-z]'));
      if (allUpper || camelish) {
        return word;
      }
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
}
