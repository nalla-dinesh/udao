// phase-06
// 60 hand-written Hinglish roast templates (spec distribution:
// food-delivery 12, shopping 8, subscriptions 8, overspend 10,
// streak-win 8, month-end 6, salary-day 4, no-spend 4). Quality
// bar: funny-not-meaning, meme-idiom, Rs-concrete — and NEVER an
// essential-category target (the guardrail enforces it at runtime;
// the corpus test enforces it at authoring time).
//
// Slots: {merchant} {amount} {delta} {days} {count} {streak}
import 'roast_template.dart';

abstract final class RoastTemplates {
  static const List<RoastTemplate> all = <RoastTemplate>[
    // ── food-delivery (12) ───────────────────────────────────────
    RoastTemplate(
      id: 'food-01',
      category: 'food-delivery',
      intensity: 1,
      body: '{merchant} ka {amount} — ghar ka khana ab sidepiece hai?',
    ),
    RoastTemplate(
      id: 'food-02',
      category: 'food-delivery',
      intensity: 2,
      body: 'Is mahine {merchant} pe {amount} udaya. Kitchen sirf showpiece.',
    ),
    RoastTemplate(
      id: 'food-03',
      category: 'food-delivery',
      intensity: 1,
      body: 'Delivery boy tumhe zyada jaanta hai jo tumhe apna flatmate jaanta hai.',
    ),
    RoastTemplate(
      id: 'food-04',
      category: 'food-delivery',
      intensity: 2,
      body: '{count} order is mahine — {merchant} ka IPO tumhari wajah se aaya hoga.',
    ),
    RoastTemplate(
      id: 'food-05',
      category: 'food-delivery',
      intensity: 3,
      body: '{merchant} pe {amount}?! Bhai rasoi ghar mein hai, gas bhi hai, bas banane ka mann nahi.',
    ),
    RoastTemplate(
      id: 'food-06',
      category: 'food-delivery',
      intensity: 1,
      body: 'Swiggy-Zomato ka combined valuation mein tumhara {amount} ka contribution note kiya gaya hai.',
    ),
    RoastTemplate(
      id: 'food-07',
      category: 'food-delivery',
      intensity: 2,
      body: 'Aaj tak ka delivery charge jama karloge to ek nayi fridge aa jayegi.',
    ),
    RoastTemplate(
      id: 'food-08',
      category: 'food-delivery',
      intensity: 3,
      body: '{amount} ka khaana bahar se? {delta} zyada than last month — diet ya dividend?',
    ),
    RoastTemplate(
      id: 'food-09',
      category: 'food-delivery',
      intensity: 1,
      body: 'Ek aur biryani order hoti to {merchant} tumhe employee discount deta.',
    ),
    RoastTemplate(
      id: 'food-10',
      category: 'food-delivery',
      intensity: 2,
      body: '{count} deliveries, {amount} ka kharcha — plate wash karne ka skill zero.',
    ),
    RoastTemplate(
      id: 'food-11',
      category: 'food-delivery',
      intensity: 3,
      body: 'Kitchen ka gas cylinder expire ho gaya — {merchant} ka account active hai. Priorities!',
    ),
    RoastTemplate(
      id: 'food-12',
      category: 'food-delivery',
      intensity: 1,
      body: 'Weekend aa gaya — matlab {merchant} ka CEO apni holiday planning kar sakta hai.',
    ),

    // ── shopping (8) ─────────────────────────────────────────────
    RoastTemplate(
      id: 'shop-01',
      category: 'shopping',
      intensity: 1,
      body: '{merchant} pe {amount} — sale thi ya tumne sale kar di?',
    ),
    RoastTemplate(
      id: 'shop-02',
      category: 'shopping',
      intensity: 2,
      body: 'Shopping {delta} badhi hai. Wardrobe full, wallet empty — balance of life.',
    ),
    RoastTemplate(
      id: 'shop-03',
      category: 'shopping',
      intensity: 2,
      body: '{amount} ka samaan jo 2 hafte baad "purana" lagega. Classic.',
    ),
    RoastTemplate(
      id: 'shop-04',
      category: 'shopping',
      intensity: 3,
      body: '{merchant} ka {amount}?! Wo cheez abhi bhi packing mein hai, admit karo.',
    ),
    RoastTemplate(
      id: 'shop-05',
      category: 'shopping',
      intensity: 1,
      body: 'Cart saaf karne ka naam "minimalism" nahi hota. Just saying.',
    ),
    RoastTemplate(
      id: 'shop-06',
      category: 'shopping',
      intensity: 2,
      body: '{count} orders shopping mein — kurkure kharidne mein itna focus hota to CEO hote.',
    ),
    RoastTemplate(
      id: 'shop-07',
      category: 'shopping',
      intensity: 3,
      body: 'Is month shopping {amount} cross kar gayi. "Zaroorat thi" — haan, bilkul.',
    ),
    RoastTemplate(
      id: 'shop-08',
      category: 'shopping',
      intensity: 1,
      body: '{merchant} tumhara phone number yaad rakhta hai. Regular customer discount maang lo.',
    ),

    // ── subscriptions (8) ────────────────────────────────────────
    RoastTemplate(
      id: 'sub-01',
      category: 'subscriptions',
      intensity: 2,
      body: '{count} subscriptions chal rahi hain — kitni actually use hoti hain? Seedha jawab.',
    ),
    RoastTemplate(
      id: 'sub-02',
      category: 'subscriptions',
      intensity: 3,
      body: '{amount} monthly sirf subscriptions pe — OTT library ka museum bana rakha hai.',
    ),
    RoastTemplate(
      id: 'sub-03',
      category: 'subscriptions',
      intensity: 1,
      body: 'Wo wala app jo ek baar kholne ke baad "auto-renew" ho raha hai? Haan wahi. {merchant}.',
    ),
    RoastTemplate(
      id: 'sub-04',
      category: 'subscriptions',
      intensity: 2,
      body: '{merchant} ka plan chalu hai par dekhne ka time nahi. Money sleeps, app streams.',
    ),
    RoastTemplate(
      id: 'sub-05',
      category: 'subscriptions',
      intensity: 1,
      body: 'Subscriptions ka total dekh ke lagta hai tum CEO ho kisi streaming company ke.',
    ),
    RoastTemplate(
      id: 'sub-06',
      category: 'subscriptions',
      intensity: 3,
      body: '{count} apps, {amount} monthly — aur ek bhi serial adhaykhand se aage nahi dekhi. Brave.',
    ),
    RoastTemplate(
      id: 'sub-07',
      category: 'subscriptions',
      intensity: 2,
      body: 'Ek subscription cancel karo, mahine ka {amount} bacha lo. Simple math, badi mushkil.',
    ),
    RoastTemplate(
      id: 'sub-08',
      category: 'subscriptions',
      intensity: 1,
      body: '{merchant} ne tumhe free trial ka jaal diya tha — ab tum full-time customer ho.',
    ),

    // ── general overspend (10) ───────────────────────────────────
    RoastTemplate(
      id: 'overspend-01',
      category: 'overspend',
      intensity: 2,
      body: 'Is mahine {amount} ud chuka hai — aur mahine ko abhi {days} din baaki hain.',
    ),
    RoastTemplate(
      id: 'overspend-02',
      category: 'overspend',
      intensity: 3,
      body: 'Kharcha last month se {delta} zyada. Grow karna chahiye salary bhi — sirf expenses nahi.',
    ),
    RoastTemplate(
      id: 'overspend-03',
      category: 'overspend',
      intensity: 1,
      body: 'Paisa haath mein nahi rehta — bas WiFi ke packets jaise udta hai.',
    ),
    RoastTemplate(
      id: 'overspend-04',
      category: 'overspend',
      intensity: 2,
      body: 'Budget ne kaha tha {amount} — wallet ne kaha " aur nahi".',
    ),
    RoastTemplate(
      id: 'overspend-05',
      category: 'overspend',
      intensity: 1,
      body: 'Aaj ka kharcha dekh ke calendar ne poocha — "special occasion?"',
    ),
    RoastTemplate(
      id: 'overspend-06',
      category: 'overspend',
      intensity: 3,
      body: 'Mahina khatam hone se pehle hi {amount} done. {days} din pehle se endgame.',
    ),
    RoastTemplate(
      id: 'overspend-07',
      category: 'overspend',
      intensity: 2,
      body: 'Zyada kharcha, kam savings — ye graph to seedha ja raha hai... neeche.',
    ),
    RoastTemplate(
      id: 'overspend-08',
      category: 'overspend',
      intensity: 1,
      body: 'Every rupee counts — tumhare yahan to har rupee double count ho raha hai.',
    ),
    RoastTemplate(
      id: 'overspend-09',
      category: 'overspend',
      intensity: 2,
      body: '{count} transactions aaj — ATM machine ko bhi break chahiye hoga.',
    ),
    RoastTemplate(
      id: 'overspend-10',
      category: 'overspend',
      intensity: 3,
      body: 'Kharche ki speed dekh ke RBI ko tumse budgeting seekhni chahiye.',
    ),

    // ── streak-win hype (8) ──────────────────────────────────────
    RoastTemplate(
      id: 'streak-01',
      category: 'streak-win',
      intensity: 1,
      body: '{streak} din ka no-spend streak! Wallet ne poocha — "tum ho kaun?"',
    ),
    RoastTemplate(
      id: 'streak-02',
      category: 'streak-win',
      intensity: 1,
      body: 'Streak {streak} din — discipline level: monk. Thoda show-off allowed hai.',
    ),
    RoastTemplate(
      id: 'streak-03',
      category: 'streak-win',
      intensity: 2,
      body: '{streak} din bilkul zero udai. Ye screenshot banake wall pe lagao.',
    ),
    RoastTemplate(
      id: 'streak-04',
      category: 'streak-win',
      intensity: 1,
      body: 'Budget ke andar kharcha + {streak} din ka streak zinda — aaj tum finance influencer ho.',
    ),
    RoastTemplate(
      id: 'streak-05',
      category: 'streak-win',
      intensity: 2,
      body: 'Is month spending {delta} kam — aur {streak} din ka streak. Double kill!',
    ),
    RoastTemplate(
      id: 'streak-06',
      category: 'streak-win',
      intensity: 1,
      body: 'Savings ka concept tumne sirf YouTube pe dekha tha — aaj {streak} din live dekh rahe hain.',
    ),
    RoastTemplate(
      id: 'streak-07',
      category: 'streak-win',
      intensity: 2,
      body: '{streak} din, ek bhi impulse purchase nahi. Willpower ka band baaja.',
    ),
    RoastTemplate(
      id: 'streak-08',
      category: 'streak-win',
      intensity: 1,
      body: 'Ye streak {streak} din se chal raha hai — Snapchat streak se zyada valuable hai, promise.',
    ),

    // ── month-end (6) ────────────────────────────────────────────
    RoastTemplate(
      id: 'monthend-01',
      category: 'month-end',
      intensity: 2,
      body: 'Mahine ke aakhri {days} din aur {amount} budget mein — math karo khud.',
    ),
    RoastTemplate(
      id: 'monthend-02',
      category: 'month-end',
      intensity: 3,
      body: 'Month-end + khali wallet = classic bollywood climax. Roti daal kharche bandh.',
    ),
    RoastTemplate(
      id: 'monthend-03',
      category: 'month-end',
      intensity: 1,
      body: 'Month ke last days: UPI se pehle 10 baar sochna. Free activities list banao.',
    ),
    RoastTemplate(
      id: 'monthend-04',
      category: 'month-end',
      intensity: 2,
      body: 'Salary {days} din door hai — ab {amount} se poora week nikalna hai. Reality show hai kya?',
    ),
    RoastTemplate(
      id: 'monthend-05',
      category: 'month-end',
      intensity: 1,
      body: 'Month-end mode: ghar ka khana premium lagta hai. Aur waise hi healthy hai.',
    ),
    RoastTemplate(
      id: 'monthend-06',
      category: 'month-end',
      intensity: 2,
      body: 'Pichle hafte ka kharcha dekh ke lagta hai month-end tumhare liye scripted hai.',
    ),

    // ── salary-day (4) ───────────────────────────────────────────
    RoastTemplate(
      id: 'salary-01',
      category: 'salary-day',
      intensity: 1,
      body: 'Salary aa gayi — 3 din ka festival shuru. Par is baar {days} din chalana hai.',
    ),
    RoastTemplate(
      id: 'salary-02',
      category: 'salary-day',
      intensity: 2,
      body: 'Paisa aate hi pehla order {merchant} se? Wallet ko thoda breach dene do, warna sad jayega.',
    ),
    RoastTemplate(
      id: 'salary-03',
      category: 'salary-day',
      intensity: 1,
      body: 'Salary day + no-spend day = rare combo. Stat-level respect if pulled off.',
    ),
    RoastTemplate(
      id: 'salary-04',
      category: 'salary-day',
      intensity: 2,
      body: 'Naya mahina, naya salary, purani aadatein. 4th tareekh tak sambhal jao.',
    ),

    // ── no-spend-streak (4) ──────────────────────────────────────
    RoastTemplate(
      id: 'nospend-01',
      category: 'no-spend',
      intensity: 1,
      body: 'Aaj ek bhi rupaya nahi uda — {streak} din ka streak. Legend.',
    ),
    RoastTemplate(
      id: 'nospend-02',
      category: 'no-spend',
      intensity: 1,
      body: 'Zero-spend day done. Kharche wale devta aaj naraz honge.',
    ),
    RoastTemplate(
      id: 'nospend-03',
      category: 'no-spend',
      intensity: 2,
      body: '{streak} din se no-spend streak — itna sanyas to sadhu bhi nahi karte.',
    ),
    RoastTemplate(
      id: 'nospend-04',
      category: 'no-spend',
      intensity: 1,
      body: 'Aaj ka score: kharcha 0, savings hero. Kal bhi repeat karo.',
    ),
  ];
}
