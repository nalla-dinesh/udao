// phase-03
// Merchant -> category assignment. A pure alias map over the 16 seed
// categories (see kSeedCategories) — data, not intelligence; Phase 06
// replaces misses with the on-device classifier.
//
// Contract: [assign] returns a `cat_*` id or null. null = unknown ->
// the pipeline flags it (`cat_unknown` kv counter) and the txn stays
// un-categorised, which the UI renders as "Other".
abstract final class Categorizer {
  static const Map<String, String> _aliases = <String, String>{
    // Khaana
    'swiggy': 'cat_khaana',
    'zomato': 'cat_khaana',
    "domino's pizza": 'cat_khaana',
    "mcdonald's": 'cat_khaana',
    'kfc': 'cat_khaana',
    'box8': 'cat_khaana',
    'faasos': 'cat_khaana',
    'eatfit': 'cat_khaana',
    // Chai-Nashta
    'chai point': 'cat_chai',
    // phase-04: plain-word chai (voice)
    'chai': 'cat_chai',
    'chaha': 'cat_chai',
    'cutting': 'cat_chai',
    'starbucks': 'cat_chai',
    'third wave coffee': 'cat_chai',
    'tiffin': 'cat_chai',
    // Groceries
    'blinkit': 'cat_groceries',
    'zepto': 'cat_groceries',
    'bigbasket': 'cat_groceries',
    'bbnow': 'cat_groceries',
    'dmart': 'cat_groceries',
    'avenue supermarts': 'cat_groceries',
    'instamart': 'cat_groceries',
    'jiomart': 'cat_groceries',
    // phase-04: plain-word groceries (voice + statements)
    'milk': 'cat_groceries',
    'doodh': 'cat_groceries',
    'sabzi': 'cat_groceries',
    'sabziyan': 'cat_groceries',
    // Rent/Bill
    'rent': 'cat_rent_bill',
    'bses yamuna': 'cat_rent_bill',
    'bses rajdhani': 'cat_rent_bill',
    'tata power': 'cat_rent_bill',
    'adani electricity': 'cat_rent_bill',
    'mahanagar gas': 'cat_rent_bill',
    // Recharge
    'airtel': 'cat_recharge',
    'airtel thanks': 'cat_recharge',
    'jio': 'cat_recharge',
    'vi': 'cat_recharge',
    'vi recharge': 'cat_recharge',
    'bsnl': 'cat_recharge',
    // Transport
    'uber': 'cat_transport',
    'uber india': 'cat_transport',
    'ola': 'cat_transport',
    'rapido': 'cat_transport',
    'irctc': 'cat_transport',
    'namma metro': 'cat_transport',
    'delhi metro': 'cat_transport',
    'indigo': 'cat_transport',
    // phase-04: plain-word transport (voice + statements)
    'auto': 'cat_transport',
    'auto rickshaw': 'cat_transport',
    'rickshaw': 'cat_transport',
    'taxi': 'cat_transport',
    'kaali peeli': 'cat_transport',
    // Fuel
    'indian oil': 'cat_fuel',
    'iocl': 'cat_fuel',
    'hp petro': 'cat_fuel',
    'hpcl': 'cat_fuel',
    'bpcl': 'cat_fuel',
    'reliance petro': 'cat_fuel',
    // phase-04: plain-word fuel (voice + statements)
    'petrol': 'cat_fuel',
    'diesel': 'cat_fuel',
    'cng': 'cat_fuel',
    // Shopping
    'amazon': 'cat_shopping',
    'flipkart': 'cat_shopping',
    'myntra': 'cat_shopping',
    'ajio': 'cat_shopping',
    'meesho': 'cat_shopping',
    'nykaa': 'cat_shopping',
    'firstcry': 'cat_shopping',
    'croma': 'cat_shopping',
    'reliance digital': 'cat_shopping',
    'vijay sales': 'cat_shopping',
    // Subscriptions (recurring media; Phase 07 confirms recurrence)
    'netflix': 'cat_subscriptions',
    'spotify': 'cat_subscriptions',
    'hotstar': 'cat_subscriptions',
    'jio cinema': 'cat_subscriptions',
    'youtube premium': 'cat_subscriptions',
    'prime video': 'cat_subscriptions',
    // Entertainment
    'bookmyshow': 'cat_entertainment',
    'pvr': 'cat_entertainment',
    'inox': 'cat_entertainment',
    'steam': 'cat_entertainment',
    // Health
    'apollo': 'cat_health',
    'pharmeasy': 'cat_health',
    '1mg': 'cat_health',
    'netmeds': 'cat_health',
    'practo': 'cat_health',
    'cult fit': 'cat_health',
    // Education
    'udemy': 'cat_education',
    'coursera': 'cat_education',
    "byju's": 'cat_education',
    'physics wallah': 'cat_education',
    'unacademy': 'cat_education',
    // Salary
    'salary': 'cat_salary',
    'salary october': 'cat_salary',
    'interest credit': 'cat_salary',
    // Cash
    'atm withdrawal': 'cat_cash',
    'cash withdrawal': 'cat_cash',
  };

  /// Case-insensitive alias lookup; null when unknown.
  static String? assign(String merchantClean) {
    if (merchantClean.isEmpty || merchantClean == 'Unknown') {
      return null;
    }
    return _aliases[merchantClean.trim().toLowerCase()];
  }
}
