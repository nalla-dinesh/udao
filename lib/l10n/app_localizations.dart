// phase-01
// Hand-written localizations — NO codegen by design (ADR-0003).
//
// Hinglish (`hi`) is the product's primary voice; `en` is the
// documented fallback (UdaoApp's localeResolutionCallback). The `.arb`
// files under assets/l10n/ are GENERATED from this file by a repo
// script, guaranteeing key parity (see tools/gen_arbs usage in the
// Phase-01 report).
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = <Locale>[
    Locale('hi'),
    Locale('en'),
  ];

  /// `hi` gets Hinglish; everything else resolves to the `en` fallback.
  String get _code => locale.languageCode == 'hi' ? 'hi' : 'en';

  String get appName => 'UDAO';

  // ── Bottom navigation ───────────────────────────────────────────────
  String get navAaj => _code == 'en' ? 'Today' : 'Aaj';
  String get navChat => _code == 'en' ? 'Chat' : 'Chat';
  String get navKhel => _code == 'en' ? 'Play' : 'Khel';
  String get navLedger => _code == 'en' ? 'Ledger' : 'Ledger';
  String get navSettings => _code == 'en' ? 'Settings' : 'Settings';

  // ── Shell placeholder screens ───────────────────────────────────────
  String get aajEmptyTitle =>
      _code == 'en' ? 'Nothing yet today' : 'Aaj ka kuch nahi';
  String get aajEmptyBody => _code == 'en'
      ? 'The moment your first rupee flies, it shows up here.'
      : 'Jab pehla paisa udga, yahan dikh jayega.';
  String get chatEmptyTitle =>
      _code == 'en' ? 'Cat got your tongue?' : 'Chup hai kya?';
  String get chatEmptyBody => _code == 'en'
      ? 'Talk to UDAO — accounting with attitude.'
      : 'UDAO se baat kar — gaaliyon wali hisaab kitaab.';
  String get khelEmptyTitle =>
      _code == 'en' ? 'The game is yet to begin' : 'Khel abhi baaki hai';
  String get khelEmptyBody => _code == 'en'
      ? 'The Chindi Ladder unlocks in Phase 07.'
      : 'Chindi Ladder Phase 07 mein khulta hai.';
  String get ledgerEmptyTitle =>
      _code == 'en' ? 'Empty ledger' : 'Khaali kitaab';
  String get ledgerEmptyBody => _code == 'en'
      ? 'Not a single entry — either you are a saint or beyond saving.'
      : 'Ek bhi entry nahi — ya toh bahut sant hai tu, ya bahut besharam.';
  String get settingsEmptyTitle =>
      _code == 'en' ? 'Settings on the way' : 'Settings aa rahi hai';
  String get settingsEmptyBody => _code == 'en'
      ? 'Full control arrives in Phase 07. Check the theme showcase meanwhile.'
      : 'Poora control Phase 07 mein milta hai. Abhi theme showcase dekh le.';
  String get emptyAction =>
      _code == 'en' ? 'Let us begin' : 'Chalo shuru karein';

  // ── Onboarding ──────────────────────────────────────────────────────
  String get obBrandTagline => _code == 'en'
      ? 'Watch your money fly. You will get laughs AND sense.'
      : 'Paise udte dekho. Hasi aur hosh dono aayenge.';
  String get obHowTitle =>
      _code == 'en' ? 'How this works' : 'Ye kaise kaam karta hai';
  String get obHowCaptureTitle =>
      _code == 'en' ? 'Silent Capture' : 'Chup-Chaap Capture';
  String get obHowCaptureBody => _code == 'en'
      ? 'Payment notifications get caught automatically — you do nothing.'
      : 'Payment notifications khud pakde jaate hain — tujhe kuch nahi karna.';
  String get obHowRoastTitle => _code == 'en' ? 'Roast Engine' : 'Roast Engine';
  String get obHowRoastBody => _code == 'en'
      ? 'A verdict every evening: honest, and a bit too blunt.'
      : 'Har shaam verdict: seedha-jawab, thoda zyada.';
  String get obHowKhelTitle => _code == 'en' ? 'The Game' : 'Khel';
  String get obHowKhelBody => _code == 'en'
      ? 'Climb the Chindi Ladder, build streaks, earn badges.'
      : 'Chindi Ladder chadho, streak banao, badges jeeto.';
  String get obNotifTitle => _code == 'en'
      ? 'Notifications for the verdict'
      : 'Verdict ke liye notification';
  String get obNotifBody => _code == 'en'
      ? 'UDAO needs notification access to catch payments and deliver the evening roast. Everything stays on your phone — nothing is uploaded, ever.'
      : 'UDAO ko notification access chahiye taaki payments pakde jaayein aur shaam ko roast bhej sake. Sab kuch phone ke andar rehta hai — kahin upload nahi hota.';
  String get obNotifDemoTitle =>
      _code == 'en' ? 'It will look like this' : 'Aisa dikhega';
  String get obNotifDemoBody => _code == 'en'
      ? 'Rs 420 flew away today. 15 percent of your GDP, in the name of chai.'
      : 'Aaj 420 rupaye ud gaye. Chai ke naam par 15 percent GDP.';
  String get obNotifCta =>
      _code == 'en' ? 'I will allow' : 'Allow karunga';
  String get obNotifLater => _code == 'en' ? 'Later' : 'Baad mein';
  String get obPersonalityTitle =>
      _code == 'en' ? 'Pick your personality' : 'Apni personality chun';
  String get personalitySavage => _code == 'en' ? 'Savage' : 'Savage';
  String get personalitySavageDesc =>
      _code == 'en' ? 'Default. Unfiltered roast.' : 'Default. Bina filter ke roast.';
  String get personalityHype => _code == 'en' ? 'Hype' : 'Hype';
  String get personalityHypeDesc =>
      _code == 'en' ? 'Save money, get hyped.' : 'Bacha toh toffi milegi.';
  String get personalitySilent => _code == 'en' ? 'Silent' : 'Silent';
  String get personalitySilentDesc =>
      _code == 'en' ? 'Just numbers, no drama.' : 'Sirf numbers, bina drama.';
  String get personalitySensei => _code == 'en' ? 'Sensei' : 'Sensei';
  String get personalitySenseiDesc =>
      _code == 'en' ? 'Wisdom, condensed.' : 'Gyaan ke saar mein.';
  String get obNameTitle => _code == 'en'
      ? 'Tell me your name (optional)'
      : 'Naam bata (optional)';
  String get obNameHint => _code == 'en' ? 'Like: Dinesh' : 'Jaise: Dinesh';
  String get obDoneMessage => _code == 'en'
      ? 'Setup done. Now live your life — UDAO keeps the books.'
      : 'Setup done. Ab jeeyo apni zindagi, hisaab UDAO sambhalega.';
  String get obNext => _code == 'en' ? 'Next' : 'Aage';
  String get obBack => _code == 'en' ? 'Back' : 'Wapas';
  String get obDone => _code == 'en' ? 'Start' : 'Shuru karo';

  // ── Components / misc ───────────────────────────────────────────────
  String get shareAction => _code == 'en' ? 'Share' : 'Share';
  String get streakUnit => _code == 'en' ? 'days' : 'din';

  // ── Settings / showcase ─────────────────────────────────────────────
  String get settingsTitle => _code == 'en' ? 'Settings' : 'Settings';
  String get settingsToolsSection =>
      _code == 'en' ? 'Tools' : 'Tools';
  String get settingsShowcaseTile =>
      _code == 'en' ? 'Theme showcase' : 'Theme showcase';
  String get settingsVersion => 'UDAO v0.1.0';
  String get showcaseTitle =>
      _code == 'en' ? 'Theme Showcase' : 'Theme Showcase';
  String get showcaseToggleTheme =>
      _code == 'en' ? 'Flip theme' : 'Theme badlo';

  // ── Showcase section labels (debug-only screen, EN is fine) ─────────
  String get showcaseSectionColors => 'Colors';
  String get showcaseSectionTypography => 'Typography';
  String get showcaseSectionButtons => 'Buttons';
  String get showcaseSectionCards => 'Cards';
  String get showcaseSectionMoney => 'Money';
  String get showcaseSectionRoast => 'Roast';
  String get showcaseSectionStats => 'Stats';
  String get showcaseSectionGame => 'Game';
  String get showcaseSectionFeedback => 'Feedback';
  String get showcaseSectionNav => 'Nav';

  // ── Phase 03: capture permission gate + settings card ───────────────
  String get gateTitle =>
      _code == 'en' ? 'Notification access' : 'Notification access';
  String get gateStatusListening =>
      _code == 'en' ? 'Capture ON — listening' : 'Capture ON — sun raha hai';
  String get gateStatusOff => _code == 'en'
      ? 'Capture is still OFF'
      : 'Capture abhi bhi OFF hai';
  String get gateStatusNever => _code == 'en'
      ? 'Nothing captured yet'
      : 'Abhi tak kuch nahi pakda gaya';
  String get gatePrimeTitle => _code == 'en'
      ? 'Let UDAO count your money'
      : 'Apne paison ko ginne do';
  String get gatePrimeBody => _code == 'en'
      ? 'UDAO reads bank and UPI app notifications and builds the ledger itself. Everything stays encrypted, on your phone only.'
      : 'UDAO bank aur UPI apps ki notifications padhkar khud ledger banata hai. Sab kuch encrypted, sirf tumhare phone mein.';
  String get gateOpenCta => _code == 'en'
      ? 'Open notification access'
      : 'Notification access kholo';
  String get gateReturnedNote => _code == 'en'
      ? 'Access is still off — find "UDAO Capture" in the list and switch it on.'
      : 'Access abhi bhi band hai — list mein "UDAO Capture" dhoondo aur ON karo.';
  String get gateAndroid15Note => _code == 'en'
      ? 'On Android 15 sideloaded installs, one extra confirmation appears — that is normal.'
      : 'Android 15 pe sideload kiya ho to ek extra confirmation dikhega — bilkul normal hai.';
  String get gateTestTitle =>
      _code == 'en' ? 'Test flight' : 'Test flight';
  String get gateTestBody => _code == 'en'
      ? 'Make a tiny payment now — 30-second monitor.'
      : 'Ab ek chhota payment karke dekho — 30 second monitor.';
  String get gateTestHint => _code == 'en'
      ? 'Send \u20b91 via GPay or PhonePe'
      : 'GPay ya PhonePe se \u20b91 bhejo';
  String get gateCapturedChip =>
      _code == 'en' ? 'Captured!' : 'Pakda gaya!';
  String get gateDoneCta => _code == 'en'
      ? 'Done — continue'
      : 'Ho gaya — aage badho';
  String get settingsCaptureTile =>
      _code == 'en' ? 'Capture' : 'Capture';
  String get settingsCaptureOn => _code == 'en'
      ? 'Notification capture ON'
      : 'Notification capture ON hai';
  String get settingsCaptureOff => _code == 'en'
      ? 'Notification capture OFF'
      : 'Notification capture OFF hai';
  String get settingsCaptureLast =>
      _code == 'en' ? 'Last event' : 'Aakhri event';

  // ── Phase 04: SMS gate, import, receipts, quick add, gap ────────────

  // -- SMS gate (power flavor) ----------------------------------------
  String get smsGateTitle =>
      _code == 'en' ? 'SMS capture' : 'SMS capture';
  String get smsGateOffTitle => _code == 'en'
      ? 'SMS is off in this build'
      : 'Is build mein SMS band hai';
  String get smsGateOffBody => _code == 'en'
      ? 'The Play build of UDAO never reads SMS — notification capture only. The power build (sideloaded) adds bank-SMS capture.'
      : 'UDAO ka Play build SMS kabhi nahi padhta — sirf notification capture. Power build (sideload) mein bank-SMS capture milta hai.';
  String get smsGatePrimeTitle => _code == 'en'
      ? 'Bank SMS se poora hisaab'
      : 'Bank SMS se poora hisaab';
  String get smsGatePrimeBody => _code == 'en'
      ? 'Some payments never make a notification. With SMS access, UDAO catches those too — same encrypted ledger, same phone-only rule.'
      : 'Kuch payments ki notification aati hi nahi. SMS access ke saath UDAO unhe bhi pakad leta hai — wahi encrypted ledger, wahi sirf-phone rule.';
  String get smsGateFactsTitle =>
      _code == 'en' ? 'The straight facts' : 'Seedhi baat';
  String get smsGateFactRead => _code == 'en'
      ? 'Only transactional senders (VM-HDFCBK style) are read; everything else is dropped before storage.'
      : 'Sirf transactional senders (VM-HDFCBK jaise) padhe jaate hain; baaki sab storage tak pahunchne se pehle drop.';
  String get smsGateFactOtp => _code == 'en'
      ? 'OTPs are dropped too — even from your bank. Never stored, never logged.'
      : 'OTP bhi drop hote hain — bank se aaya ho tab bhi. Kabhi store nahi, log nahi.';
  String get smsGateFactPromo => _code == 'en'
      ? 'Promos and marketing die at the gate.'
      : 'Promo aur marketing gate par hi mar jaate hain.';
  String get smsGateFactRetention => _code == 'en'
      ? 'Raw SMS text lives 24 hours in an encrypted file, then it is gone; only the parsed transaction remains.'
      : 'Raw SMS text 24 ghante encrypted file mein rehta hai, phir mit jaata hai; sirf parse hua transaction bachta hai.';
  String get smsGateFactOffline => _code == 'en'
      ? 'Nothing leaves the phone. Ever.'
      : 'Kuch bhi phone se bahar nahi jaata. Kabhi nahi.';
  String get smsGateGrantedTitle => _code == 'en'
      ? 'Bank SMS capture is ON'
      : 'Bank SMS capture ON hai';
  String get smsGateGrantedBody => _code == 'en'
      ? 'No test flight here — an SMS cannot be triggered on demand. Your next real bank SMS will show up in the ledger.'
      : 'Yahan test flight nahi — SMS demand pe trigger nahi hota. Agli asli bank SMS ledger mein dikhegi.';
  String get smsGateAllowCta => _code == 'en'
      ? 'Allow SMS access'
      : 'SMS access do';
  String get smsGatePermDeniedBody => _code == 'en'
      ? 'You denied this permanently. Enable it from system settings.'
      : 'Aapne hamesha ke liye mana kiya. System settings se enable karo.';
  String get smsGateOpenSettings => _code == 'en'
      ? 'Open system settings'
      : 'System settings kholo';

  // -- Statement import ------------------------------------------------
  String get importTitle => _code == 'en'
      ? 'Import statement'
      : 'Statement import';
  String get importPdfBlurb => _code == 'en'
      ? 'Pick a bank-statement PDF (HDFC, SBI, ICICI, Axis, Kotak). Password-protected files open in memory only — the password is never saved.'
      : 'Bank statement PDF chuno (HDFC, SBI, ICICI, Axis, Kotak). Password wali file sirf memory mein khulti hai — password kabhi save nahi hota.';
  String get importCsvBlurb => _code == 'en'
      ? 'Pick a UDAO-exported CSV to restore or merge a backup.'
      : 'UDAO se export hua CSV chuno — backup restore ya merge ke liye.';
  String get importPickCta =>
      _code == 'en' ? 'Choose file' : 'File chuno';
  String get importPasswordTitle => _code == 'en'
      ? 'Statement password'
      : 'Statement ka password';
  String get importPasswordHint =>
      _code == 'en' ? 'PDF password' : 'PDF password';
  String get importPasswordOpen => _code == 'en'
      ? 'Open statement'
      : 'Statement kholo';
  String get importStatNew => _code == 'en' ? 'New' : 'Naye';
  String get importStatDup =>
      _code == 'en' ? 'Duplicates' : 'Duplicate';
  String get importStatSkipped => _code == 'en' ? 'Skipped' : 'Chhuke';
  String get importDupExplainer => _code == 'en'
      ? 'Duplicates (by reference, fingerprint, or same-day match) are skipped automatically — overlapping ranges never double-count.'
      : 'Duplicate (reference, fingerprint, ya usi-din ke match se) apne aap chhod diye jaate hain — overlap kabhi double-count nahi hota.';
  String importConfirmCta(int count) => _code == 'en'
      ? 'Add $count transactions'
      : '$count transaction jodo';
  String get importRowsHeader => _code == 'en' ? 'Rows' : 'Rows';
  String get importSkippedHeader => _code == 'en'
      ? 'Skipped lines'
      : 'Chhodi gayi lines';
  String get importDupInSet =>
      _code == 'en' ? 'dup (in file)' : 'dup (file mein)';
  String get importDupRef => _code == 'en' ? 'dup (ref)' : 'dup (ref)';
  String get importDupFingerprint => _code == 'en' ? 'dup' : 'dup';
  String get importDupFuzzy =>
      _code == 'en' ? 'dup (that day)' : 'dup (us din)';
  String importDoneSummary(int inserted, int dups) => _code == 'en'
      ? '$inserted added, $dups duplicates skipped.'
      : '$inserted jude, $dups duplicate chhode.';
  String get importPickFailed => _code == 'en'
      ? 'Could not open the picker.'
      : 'Picker nahi khul paaya.';
  String get importErrUnsupportedBank => _code == 'en'
      ? 'This bank is not supported yet (HDFC, SBI, ICICI, Axis, Kotak).'
      : 'Ye bank abhi support nahi (HDFC, SBI, ICICI, Axis, Kotak).';
  String get importErrUnsupportedCsv => _code == 'en'
      ? 'Not a UDAO-exported CSV.'
      : 'Ye UDAO ka export CSV nahi hai.';
  String get importErrPdfOpen => _code == 'en'
      ? 'Could not open this PDF.'
      : 'Ye PDF nahi khula.';
  String get importErrCsvRead => _code == 'en'
      ? 'Could not read this CSV.'
      : 'Ye CSV nahi padha gaya.';
  String get importErrGeneric => _code == 'en'
      ? 'Something went wrong reading this file.'
      : 'File padhne mein kuch galat hua.';
  String get importErrWrite => _code == 'en'
      ? 'The import was rolled back — nothing was written.'
      : 'Import rollback ho gaya — kuch likha nahi gaya.';

  // -- Receipts ---------------------------------------------------------
  String get receiptCameraCta => _code == 'en'
      ? 'Photograph the bill'
      : 'Camera se bill ka photo';
  String get receiptGalleryCta => _code == 'en'
      ? 'Pick from gallery'
      : 'Gallery se chuno';
  String get receiptOfflineNote => _code == 'en'
      ? 'OCR runs fully on your phone — the photo never leaves the device, and only a smaller encrypted copy is kept.'
      : 'OCR poora phone pe chalta hai — photo device se bahar nahi jaati, aur sirf chhota encrypted copy rakha jaata hai.';
  String get receiptMerchantLabel => _code == 'en'
      ? 'Shop / merchant'
      : 'Dukaan / merchant';
  String get receiptAmountLabel =>
      _code == 'en' ? 'Amount' : 'Rakam';
  String get receiptToday => _code == 'en' ? 'Today' : 'Aaj';
  String get receiptYesterday => _code == 'en' ? 'Yesterday' : 'Kal';
  String get receiptDebit => _code == 'en' ? 'Spent' : 'Kharch';
  String get receiptCredit =>
      _code == 'en' ? 'Refund / in' : 'Wapsi / aaya';
  String get receiptConfirmCta => _code == 'en'
      ? 'Add to ledger'
      : 'Ledger mein jodo';
  String get receiptOcrFailed => _code == 'en'
      ? 'Could not read the receipt.'
      : 'Receipt nahi padh paye.';
  String get receiptAmountInvalid => _code == 'en'
      ? 'Enter a valid amount first.'
      : 'Pehle sahi rakam likho.';
  String get receiptSaveFailed =>
      _code == 'en' ? 'Could not save.' : 'Save nahi ho paya.';
  String receiptSaved(String amount) => _code == 'en'
      ? 'Added $amount'
      : '$amount jud gaya';
  String get receiptDupWarning => _code == 'en'
      ? 'Heads up: the same amount at the same shop already exists today. Add anyway if this is a different bill.'
      : 'Dhyan do: aaj usi dukaan pe itna hi amount already hai. Agar alag bill hai to phir bhi jodo.';

  // -- Quick add --------------------------------------------------------
  String get quickAddTitle =>
      _code == 'en' ? 'Quick add' : 'Turant jodo';
  String get quickAddFabLabel => _code == 'en' ? 'Add' : 'Jodo';
  String get quickAddBoloTab => _code == 'en' ? 'Bolo' : 'Bolo';
  String get quickAddLikhoTab => _code == 'en' ? 'Type' : 'Likho';
  String get quickAddBillTab => _code == 'en' ? 'Bill' : 'Bill';
  String get quickAddBoloBlurb => _code == 'en'
      ? 'Say it: "sawa sau auto ka" — we turn it into a transaction you confirm.'
      : 'Bolo: "sawa sau auto ka" — hum use transaction bana denge, tum confirm karo.';
  String get quickAddMicCta =>
      _code == 'en' ? 'Start speaking' : 'Bolna shuru';
  String get quickAddListening =>
      _code == 'en' ? 'Listening…' : 'Sun rahe hain…';
  String get quickAddVoiceUnavailable => _code == 'en'
      ? 'No speech service on this phone.'
      : 'Is phone pe speech service nahi hai.';
  String get quickAddVoiceHeardNothing => _code == 'en'
      ? 'Nothing was heard. Try again?'
      : 'Kuch sunayi nahi diya. Phir try karo?';
  String get quickAddVoiceNoAmount => _code == 'en'
      ? 'Could not hear an amount. Try again?'
      : 'Rakam samajh nahi aayi. Phir bolo?';
  String quickAddConfirmQuestion(String amount, String merchant) =>
      _code == 'en'
          ? 'Is this right? \u20b9$amount · $merchant'
          : 'Kya ye sahi hai? \u20b9$amount · $merchant';
  String quickAddUnknownWords(String words) => _code == 'en'
      ? 'Not understood: $words'
      : 'Samajh nahi aaya: $words';
  String get quickAddSaveCta => _code == 'en' ? 'Save' : 'Save karo';
  String get quickAddMerchantLabel =>
      _code == 'en' ? 'Merchant' : 'Merchant';
  String get quickAddBillBlurb => _code == 'en'
      ? 'Photograph a bill — offline OCR fills the form, you confirm.'
      : 'Bill ka photo kheencho — offline OCR form bharta hai, tum confirm karo.';
  String get quickAddBillCta => _code == 'en' ? 'Open bill' : 'Bill kholo';
  String get quickAddSaved =>
      _code == 'en' ? 'Saved.' : 'Save ho gaya.';
  String get quickAddSaveFailed =>
      _code == 'en' ? 'Could not save.' : 'Save nahi hua.';

  // -- Gap detector ------------------------------------------------------
  String get gapTitle => _code == 'en'
      ? 'Missed something?'
      : 'Kya miss hua?';
  String get gapAllGoodTitle =>
      _code == 'en' ? 'All clear' : 'Sab theek';
  String get gapAllGoodBody => _code == 'en'
      ? 'No capture gaps detected in the last two weeks.'
      : 'Pichhle do hafte koi capture gap nahi mila.';
  String gapIntroCopy(int silentDays) => _code == 'en'
      ? 'This week something looks missed — $silentDays day(s) with no captured payments. Check?'
      : 'Is hafte kuch miss hua lag raha hai — $silentDays din koi payment nahi dikhi. Check kar lein?';
  String gapBaselineCopy(String baseline) => _code == 'en'
      ? 'Your baseline: $baseline captured payments/day (active days, last 30).'
      : 'Tumhara baseline: $baseline payment/din (active din, pichhle 30).';
  String get gapSilenceTitle =>
      _code == 'en' ? 'Silent days' : 'Chup din';
  String get gapSilenceBody => _code == 'en'
      ? 'Some weekdays show zero captured payments while your baseline says that is unusual. A statement import fills those days.'
      : 'Kuch weekdays pe koi payment nahi dikhi jabki tumhara baseline kuch aur kehta hai. Statement import un dinon ko bhar dega.';
  String get gapImportCta => _code == 'en'
      ? 'Import a statement'
      : 'Statement import karo';
  String get gapListenerTitle => _code == 'en'
      ? 'Listener looks stuck'
      : 'Listener atka hua lagta hai';
  String gapListenerBody(int hours) => _code == 'en'
      ? 'No notification-source payments for ${hours}h while SMS still arrives — the notification listener is probably off.'
      : '$hours ghante se notification wala koi payment nahi, jabki SMS aa rahi hai — notification listener shayad band hai.';
  String get gapListenerCta => _code == 'en'
      ? 'Check the listener'
      : 'Listener check karo';
  String get gapWeeklyCopy => _code == 'en'
      ? 'This week something looks missed — tap to check.'
      : 'Is hafte kuch miss hua lag raha hai — check kar lein?';

  // -- Settings (phase-04 tools) ----------------------------------------
  String get settingsImportTile => _code == 'en'
      ? 'Import statement'
      : 'Statement import';
  String get settingsGapTile =>
      _code == 'en' ? 'Gap check' : 'Gap check';
  String get settingsHealthTile => _code == 'en'
      ? 'Capture health'
      : 'Capture sehat';
  String get settingsSmsTile =>
      _code == 'en' ? 'SMS capture (power)' : 'SMS capture (power)';

  // ── Survival / health dashboard (phase 05) ──────────────────────────
  String get survivalHealthTitle =>
      _code == 'en' ? 'Capture health' : 'Capture sehat';

  String get survivalStampSharp =>
      _code == 'en' ? 'SHARP' : 'SHARP';
  String get survivalStampSharpBody => _code == 'en'
      ? 'Ears open, ledger live — everything is landing.'
      : 'Kaan khule hain, ledger chal raha hai — sab land ho raha hai.';
  String get survivalStampWatch =>
      _code == 'en' ? 'PAY ATTENTION' : 'DHYAN DO';
  String get survivalStampWatchBody => _code == 'en'
      ? 'Listener is connected but quiet for a while — keep an eye.'
      : 'Listener juda hai par thodi der se chup hai — nazar rakho.';
  String get survivalStampDead =>
      _code == 'en' ? 'OFF' : 'BAND';
  String get survivalStampDeadBody => _code == 'en'
      ? 'Notification access is disconnected — UDAO is deaf right now. Fix below.'
      : 'Notification access kata hua hai — UDAO abhi bahra hai. Neeche theek karo.';
  String survivalLastEvent(String age) => _code == 'en'
      ? 'Last captured event: $age ago'
      : 'Aakhri capture: $age pehle';

  String get survivalGapAlertTitle =>
      _code == 'en' ? 'Gaps found this week' : 'Is hafte gap mile';
  String survivalGapAlertSilent(int days) => _code == 'en'
      ? '$days weekday(s) with zero captured payments.'
      : '$days din (weekday) par koi payment capture nahi hui.';
  String survivalGapAlertSilentAndStale(int days, String hours) => _code == 'en'
      ? '$days silent weekday(s); notification capture silent for $hours h.'
      : '$days chup din; notification capture $hours ghante se chup hai.';
  String get survivalGapAlertSeen =>
      _code == 'en' ? 'Seen — clear it' : 'Dekh liya — hata do';

  String get survivalListenerTitle =>
      _code == 'en' ? 'Notification listener' : 'Notification listener';
  String get survivalListenerBound => _code == 'en'
      ? 'Bound — system binding is live.'
      : 'Bound — system binding live hai.';
  String get survivalListenerUnbound => _code == 'en'
      ? 'Not bound — the system binding is missing.'
      : 'Bound nahi hai — system binding nahi dikh rahi.';
  String get survivalComponentEnabled => _code == 'en'
      ? 'Service component: enabled' : 'Service component: on hai';
  String get survivalComponentDisabled => _code == 'en'
      ? 'Service component: DISABLED' : 'Service component: BAND hai';
  String get survivalRebindCta =>
      _code == 'en' ? 'Rebind' : 'Rebind karo';
  String get survivalToggleCta =>
      _code == 'en' ? 'Hard rebind (toggle)' : 'Hard rebind (toggle)';
  String get survivalRebindSent => _code == 'en'
      ? 'Rebind request sent — give it a few seconds.'
      : 'Rebind request bhej di — kuch second do.';
  String get survivalToggleSent => _code == 'en'
      ? 'Component toggle issued — checking in a moment.'
      : 'Component toggle ho gaya — abhi check karte hain.';

  String get survivalWatchdogTitle =>
      _code == 'en' ? 'Watchdog (30 min)' : 'Watchdog (30 min)';
  String survivalWatchdogLastPing(String age) => _code == 'en'
      ? 'Last ping: $age ago' : 'Aakhri ping: $age pehle';
  String get survivalWatchdogNeverRan => _code == 'en'
      ? 'Watchdog has not run yet — it arms on first app start.'
      : 'Watchdog abhi chala nahi — pehle app start par judta hai.';
  String get survivalWatchdogOemNote => _code == 'en'
      ? 'This maker is known to kill background apps — the OEM guide below matters.'
      : 'Ye maker background apps band karne ke liye mashhoor hai — neeche ka OEM guide zaroori hai.';

  String get survivalSparkTitle =>
      _code == 'en' ? 'Last 7 days' : 'Pichhle 7 din';
  String get survivalSparkSubtitle => _code == 'en'
      ? 'Notifications seen per day (ledger counters).'
      : 'Roz dikhne wale notifications (ledger counters).';
  String get survivalSparkEmpty => _code == 'en'
      ? 'No capture counters yet — first transactions will show up here.'
      : 'Abhi koi counter nahi — pehli transactions yahan dikhengi.';
  String get survivalStatSeen => _code == 'en' ? 'Seen' : 'Dikhe';
  String get survivalStatParsed =>
      _code == 'en' ? 'Parsed' : 'Parse hue';
  String get survivalStatDeduped =>
      _code == 'en' ? 'Dupes dropped' : 'Duplicate hate';

  String get survivalKeepAliveTitle => _code == 'en'
      ? 'Keep-alive service (optional)' : 'Keep-alive service (optional)';
  String survivalKeepAliveOn(int beats) => _code == 'en'
      ? 'Running — $beats beats so far.' : 'Chal raha hai — ab tak $beats beat.';
  String get survivalKeepAliveOff => _code == 'en'
      ? 'Off — arm it only if capture keeps dying on this phone.'
      : 'Band hai — tabhi on karo jab is phone par capture baar-baar band ho.';
  String get survivalKeepAliveNote => _code == 'en'
      ? 'Shows a permanent low-priority notice; survives swipe-away; stops only when you say so.'
      : 'Ek hamesha-wala low-priority notice dikhata hai; swipe-away se bachta hai; sirf tumhare kehne par band hota hai.';
  String get survivalKeepAliveStart =>
      _code == 'en' ? 'Arm keep-alive' : 'Keep-alive on karo';
  String get survivalKeepAliveStop =>
      _code == 'en' ? 'Stop keep-alive' : 'Keep-alive band karo';
  String get survivalKeepAliveStarted =>
      _code == 'en' ? 'Keep-alive armed.' : 'Keep-alive on ho gaya.';
  String get survivalKeepAliveStopped =>
      _code == 'en' ? 'Keep-alive stopped.' : 'Keep-alive band ho gaya.';

  String get survivalBattExemptTitle => _code == 'en'
      ? 'Battery optimization: exempted' : 'Battery optimization: exempt hai';
  String get survivalBattExemptBody => _code == 'en'
      ? 'The OS is not throttling UDAO. Nothing to do here.'
      : 'OS UDAO ko rok nahi raha. Yahan kuch nahi karna.';
  String get survivalBattNotExemptTitle => _code == 'en'
      ? 'Battery optimization: ON (bad for capture)'
      : 'Battery optimization: ON (capture ke liye kharab)';
  String get survivalBattNotExemptBody => _code == 'en'
      ? 'Doze may defer UDAO in idle. Exempt it: battery settings → UDAO → unrestricted.'
      : 'Doze mein UDAO defer ho sakta hai. Exempt karo: battery settings → UDAO → unrestricted.';
  String get survivalBattPlayNote => _code == 'en'
      ? 'Play build opens the system list — find UDAO there.'
      : 'Play build system list kholta hai — wahan UDAO dhoondo.';
  String get survivalBattDirectCta =>
      _code == 'en' ? 'Open direct dialog' : 'Direct dialog kholo';
  String get survivalBattListCta =>
      _code == 'en' ? 'Open battery list' : 'Battery list kholo';
  String get survivalBattDetailsCta =>
      _code == 'en' ? 'App details' : 'App details';
  String get survivalBattOpened => _code == 'en'
      ? 'Opened — flip the setting there.' : 'Khul gaya — wahan setting badlo.';
  String get survivalBattOpenFailed => _code == 'en'
      ? 'Could not open — try app details instead.'
      : 'Nahi khula — app details try karo.';

  String get survivalDeviceTruthTitle =>
      _code == 'en' ? 'What the OS says (right now)' : 'OS kya kehta hai (abhi)';
  String get survivalTruthBatteryOpt =>
      _code == 'en' ? 'Battery optimization' : 'Battery optimization';
  String get survivalTruthExempt => _code == 'en' ? 'exempted' : 'exempt hai';
  String get survivalTruthOptimized =>
      _code == 'en' ? 'optimizing (throttling)' : 'optimize kar raha hai';
  String get survivalTruthPowerSaver =>
      _code == 'en' ? 'Power saver mode' : 'Power saver mode';
  String get survivalTruthOn => _code == 'en' ? 'ON' : 'ON';
  String get survivalTruthOff => _code == 'en' ? 'off' : 'off';
  String get survivalTruthBackgroundRestricted =>
      _code == 'en' ? 'Background restricted' : 'Background restricted';
  String get survivalTruthYes => _code == 'en' ? 'yes' : 'haan';
  String get survivalTruthNo => _code == 'en' ? 'no' : 'nahi';
  String get survivalTruthUnknown => _code == 'en'
      ? 'cannot check on this device' : 'is device par check nahi ho sakta';
  String get survivalTruthStandbyBucket =>
      _code == 'en' ? 'App standby bucket' : 'App standby bucket';
  String get survivalTruthDeviceIdle =>
      _code == 'en' ? 'Device in doze (right now)' : 'Device doze mein (abhi)';

  String get survivalExitTitle => _code == 'en'
      ? 'Why the app died before (last 5)' : 'Pehle app kyu band hua (aakhri 5)';
  String get survivalExitEmpty => _code == 'en'
      ? 'Nothing recorded (Android 11+ keeps this list; all good so far).'
      : 'Kuch record nahi (Android 11+ hi ye list rakhta hai; ab tak sab theek).';

  String get survivalOemTitle =>
      _code == 'en' ? 'This phone\'s maker' : 'Ye phone kis ka hai';
  String survivalOemDetected(String label) => _code == 'en'
      ? 'Detected: $label' : 'Detect hua: $label';
  String get survivalOemSetupCta =>
      _code == 'en' ? 'Open setup guide' : 'Setup guide kholo';

  String survivalOemSetupTitle(String label) => _code == 'en'
      ? 'Survival setup — $label' : 'Survival setup — $label';
  String get survivalOemSetupSummaryTitle =>
      _code == 'en' ? 'Why this phone needs it' : 'Is phone ko kyu chahiye';
  String survivalOemStepTitle(int n) => _code == 'en' ? 'Step $n' : 'Step $n';
  String get survivalOemNotesTitle =>
      _code == 'en' ? 'Good to know' : 'Jaanne layak';
  String get survivalOemAckCta =>
      _code == 'en' ? 'Done — I set this up' : 'Ho gaya — set kar diya';
  String get survivalOemAckDone =>
      _code == 'en' ? 'Marked done' : 'Done mark ho gaya';
  String get survivalOemAckSaved => _code == 'en'
      ? 'Noted. We will only re-ask after a big change.'
      : 'Note kar liya. Bade change ke baad hi wapas poochenge.';
  String get survivalOemLinkOpened => _code == 'en'
      ? 'Opened the OEM screen — flip the setting there.'
      : 'OEM screen khul gaya — wahan setting badlo.';
  String get survivalOemLinkMissed => _code == 'en'
      ? 'This path does not exist on your version — use the manual steps below.'
      : 'Ye path aapke version par nahi hai — neeche ke manual steps use karo.';
  String survivalOemDkmaNote(String url) => _code == 'en'
      ? 'Community-kept reference: $url' : 'Community reference: $url';

  String get survivalExportTitle =>
      _code == 'en' ? 'Diagnostics export' : 'Diagnostics export';
  String get survivalExportBody => _code == 'en'
      ? 'Share a JSON summary (counts + states only — never your transaction text).'
      : 'JSON summary share karo (sirf counts + states — kabhi transaction text nahi).';
  String get survivalExportCta =>
      _code == 'en' ? 'Share JSON' : 'JSON share karo';
  String get survivalExportFailed =>
      _code == 'en' ? 'Export failed — try again.' : 'Export fail hua — dobara try karo.';

  String get survivalBatteryHonesty => _code == 'en'
      ? 'Battery honesty: passive listening costs <1%/day. The optional keep-alive service costs more — it is your call, not ours.'
      : 'Battery sach: passive sunne ka kharcha <1%/din. Optional keep-alive service thoda zyada khaata hai — ye tumhara call hai, humara nahi.';
  // ── phase-06: chat ────────────────────────────────────────────────
  String get chatTitle => _code == 'en' ? 'UDAO Chat' : 'UDAO Chat';
  String get chatPlaceholder => _code == 'en'
      ? 'Poochho kuch bhi — paisa, kharcha, roast…'
      : 'Poochho kuch bhi — paisa, kharcha, roast…';
  String get chatSendTooltip => _code == 'en' ? 'Send' : 'Bhejo';
  String get chatStopTooltip => _code == 'en' ? 'Stop' : 'Rok do';
  String get chatVoiceTooltip => _code == 'en' ? 'Speak' : 'Bolo';
  String get chatAttachTooltip => _code == 'en'
      ? 'Attach receipt'
      : 'Receipt jodo';
  String get chatTemplateOnlyBanner => _code == 'en'
      ? 'Model absent — seedha-jawab mode on hai. Settings se model import karo.'
      : 'Model absent — seedha-jawab mode on hai. Settings se model import karo.';
  String get chatSuggested1 => _code == 'en'
      ? 'is mahine kitna kharcha kiya?'
      : 'is mahine kitna kharcha kiya?';
  String get chatSuggested2 => _code == 'en'
      ? 'Swiggy pe kitna udaya hai?'
      : 'Swiggy pe kitna udaya hai?';
  String get chatSuggested3 => _code == 'en'
      ? 'budget bata do'
      : 'budget bata do';
  String get chatGuardedChip => _code == 'en'
      ? 'softened by guardrail'
      : 'guardrail ne halka kar diya';
  String get chatCappedChip => _code == 'en'
      ? 'tool rounds capped'
      : 'tool rounds ki limit aa gayi';
  String get chatClearAll => _code == 'en'
      ? 'Clear chat history?'
      : 'Chat history mita dein?';
  String get chatClearAllBody => _code == 'en'
      ? 'All messages are deleted from this device. This cannot be undone.'
      : 'Saare messages is device se delete ho jayenge. Wapas nahi aayenge.';
  String get chatClearConfirm => _code == 'en' ? 'Clear' : 'Mita do';
  String get chatClearCancel => _code == 'en' ? 'Keep' : 'Rakh do';
  String chatToolChip(String name, String args, int ms) => _code == 'en'
      ? '→ $name$args · $ms ms'
      : '→ $name$args · $ms ms';
  String chatPersonaTag(String id) => _code == 'en'
      ? 'voice: $id'
      : 'awaaz: $id';

  // ── phase-06: personas / stress ───────────────────────────────────
  String get personaStressNotice => _code == 'en'
      ? 'Thoda halka mode on kar diya — wapas savage chahiye to bata dena.'
      : 'Thoda halka mode on kar diya — wapas savage chahiye to bata dena.';
  String get personaStressExit => _code == 'en' ? 'Savage please' : 'Savage wapas';

  // ── phase-06: AI settings ─────────────────────────────────────────
  String get aiSettingsTitle => _code == 'en' ? 'AI settings' : 'AI settings';
  String get settingsAiTile => _code == 'en' ? 'AI / Dimaag' : 'AI / Dimaag';
  String get aiSettingsModelTitle => _code == 'en'
      ? 'On-device model'
      : 'On-device model';
  String get aiSettingsModelAbsent => _code == 'en'
      ? 'No model on this device. UDAO runs in template-only mode — roasts and tools still work, free-form chat needs a model.'
      : 'Is device pe koi model nahi. UDAO template-only mode mein chal raha hai — roast aur tools chalte hain, free-form chat ke liye model chahiye.';
  String get aiSettingsTemplateOnlyBody => _code == 'en'
      ? 'Import a .task model file (see docs/ai/models.md for exact downloads). The file is validated (size + SHA-256) and stays on this device.'
      : 'Ek .task model file import karo (exact download links docs/ai/models.md mein). File validate hoti hai (size + SHA-256) aur isi device pe rehti hai.';
  String get aiSettingsImportCta => _code == 'en' ? 'Import model' : 'Model import karo';
  String get aiSettingsImportDone => _code == 'en'
      ? 'Model imported.'
      : 'Model import ho gaya.';
  String aiSettingsImportFailed(String reason) => _code == 'en'
      ? 'Import failed: $reason'
      : 'Import fail: $reason';
  String get aiSettingsDeleteCta => _code == 'en' ? 'Delete model' : 'Model delete karo';
  String get aiSettingsDeleteDone => _code == 'en'
      ? 'Model deleted.'
      : 'Model delete ho gaya.';
  String get aiSettingsLoadCta => _code == 'en' ? 'Load model' : 'Model load karo';
  String get aiSettingsModelLoaded => _code == 'en'
      ? 'Model loaded.'
      : 'Model load ho gaya.';
  String aiSettingsModelLoadFailed(String reason) => _code == 'en'
      ? 'Load failed: $reason'
      : 'Load fail: $reason';
  String get aiSettingsFileLabel => _code == 'en' ? 'File' : 'File';
  String get aiSettingsSizeLabel => _code == 'en' ? 'Size' : 'Size';
  String get aiSettingsShaLabel => _code == 'en' ? 'SHA-256 (start)' : 'SHA-256 (shuruaat)';
  String get aiSettingsStatusLabel => _code == 'en' ? 'Status' : 'Status';
  String get aiSettingsStatusLoaded => _code == 'en' ? 'loaded' : 'loaded';
  String get aiSettingsStatusLoading => _code == 'en' ? 'loading…' : 'load ho raha…';
  String get aiSettingsStatusReady => _code == 'en' ? 'ready' : 'ready';
  String get aiSettingsTierTitle => _code == 'en' ? 'Device tier' : 'Device tier';
  String aiSettingsTierBody(String tier, String file) => _code == 'en'
      ? "This phone's RAM suggests tier $tier ($file). Bigger models are never blocked — just slower."
      : 'Is phone ka RAM tier $tier suggest karta hai ($file). Bade models block nahi hote — bas slow chalte hain.';
  String get aiSettingsPreloadTitle => _code == 'en'
      ? 'Keep the brain warm'
      : 'Brain warm rakhna';
  String get aiSettingsPreloadBody => _code == 'en'
      ? 'Preload keeps the model in RAM. Battery honest: it costs more. Default off — the model loads on demand and unloads after 5 idle minutes.'
      : 'Preload model ko RAM mein rakhta hai. Battery sach: thoda zyada kharcha hota hai. Default off — model zaroorat pe load hota hai aur 5 minute idle ke baad unload.';
  String get aiSettingsPreloadToggle => _code == 'en' ? 'Preload' : 'Preload';
  String get aiSettingsTestRoastTitle => _code == 'en' ? 'Test roast' : 'Test roast';
  String get aiSettingsTestRoastBody => _code == 'en'
      ? 'Runs one fixed prompt through the active path (template floor or model) and reports latency + estimated tokens.'
      : 'Ek fixed prompt chalata hai (template ya model) aur latency + estimated tokens batata hai.';
  String get aiSettingsTestRoastCta => _code == 'en' ? 'Run test' : 'Test chalao';
  String aiSettingsTestRoastDone(int ms, int tokens) => _code == 'en'
      ? 'Done in $ms ms · ~$tokens estimated tokens'
      : '$ms ms mein done · ~$tokens estimated tokens';
  String get aiSettingsPersonaTitle => _code == 'en' ? 'Voice' : 'Awaaz';
  String get aiSettingsPersonaSaved => _code == 'en'
      ? 'Voice saved (pinned).'
      : 'Awaaz save ho gayi (pinned).';
  String get aiSettingsPersonaPinBody => _code == 'en'
      ? 'Picking from settings pins the voice — the stress auto-switch (Sensei) will not override it.'
      : 'Settings se chunna = pin. Stress auto-switch (Sensei) isse override nahi karega.';
  String get aiSettingsLearnedTitle => _code == 'en'
      ? 'Learned bank formats'
      : 'Naye bank formats';
  String get aiSettingsLearnedEmpty => _code == 'en'
      ? 'Nothing learned yet. When the AI parses an unknown format, its proposed regex appears here for your approval.'
      : 'Abhi kuch nahi seekha. Jab AI koi unknown format parse kare, uska regex yahan approval ke liye aayega.';
  String aiSettingsLearnedRow(String pattern) => _code == 'en'
      ? 'Regex: $pattern'
      : 'Regex: $pattern';
  String aiSettingsLearnedSample(String sample) => _code == 'en'
      ? 'Learned from: $sample'
      : 'Isse seekha: $sample';
  String get aiSettingsLearnedApprove => _code == 'en' ? 'Save' : 'Save karo';
  String get aiSettingsLearnedDismiss => _code == 'en' ? 'Discard' : 'Nikaal do';
  String get aiSettingsLearnedTestOk => _code == 'en'
      ? 'Test: pattern matches its sample'
      : 'Test: pattern apne sample se match ho gaya';
  String get aiSettingsLearnedTestFail => _code == 'en'
      ? 'Test: pattern does NOT match — discard it'
      : 'Test: pattern match NAHI hua — discard karo';
  String get aiSettingsTelemetryTitle => _code == 'en'
      ? 'AI telemetry (local only)'
      : 'AI telemetry (sirf local)';
  String aiSettingsTelemetryBody(
    int tokens,
    int latencyMs,
    int toolOk,
    int toolFail,
    int blocks,
  ) =>
      _code == 'en'
          ? 'Estimated tokens: $tokens · avg latency: $latencyMs ms · tool calls ok/fail: $toolOk/$toolFail · guardrail blocks: $blocks. No message content is ever stored.'
          : 'Estimated tokens: $tokens · avg latency: $latencyMs ms · tool calls ok/fail: $toolOk/$toolFail · guardrail blocks: $blocks. Koi message content store nahi hota.';

  // ── Khel (Phase 07) ─────────────────────────────────────────────────
  String get khelTitle => _code == 'en' ? 'The Game' : 'Khel';
  String get khelStreakLabel => _code == 'en' ? 'No-spend streak' : 'No-spend streak';
  String get khelLongestLabel => _code == 'en' ? 'Best' : 'Best';
  String get khelFreezesLabel => _code == 'en' ? 'Freezes' : 'Freeze';
  String khelTodayClean(int days) => _code == 'en'
      ? 'Clean so far today — the streak breathes. $days day(s) and counting.'
      : 'Aaj abhi saaf — streak saans le raha hai. $days din ho gaye.';
  String khelTodaySpent(String rupees) => _code == 'en'
      ? 'Spent \u20B9$rupees today — the streak breaks at midnight unless you freeze it.'
      : 'Aaj \u20B9$rupees kharch ho gaya — raat 12 baje streak tootega, freeze nahi lagaya toh.';
  String khelTodaySpentFrozen(String rupees) => _code == 'en'
      ? 'Spent \u20B9$rupees today — but a freeze is committed. The streak survives, it just won\u2019t grow.'
      : 'Aaj \u20B9$rupees kharch hua — par freeze lagaya hai. Streak bacha rahega, badega nahi.';
  String get khelFreezeButton => _code == 'en' ? 'COMMIT FREEZE' : 'FREEZE LAGAO';
  String get khelFreezeApplied => _code == 'en' ? 'Freeze committed for today' : 'Aaj ke liye freeze lag gaya';
  String get khelNoFreezes => _code == 'en'
      ? 'No freezes left — earn them via challenges'
      : 'Koi freeze nahi bacha — challenges se kamao';
  String get khelLadderTitle => _code == 'en' ? 'Chindi Ladder' : 'Chindi Ladder';
  String get khelBadgesTitle => _code == 'en' ? 'Badges' : 'Badges';
  String get khelChallengesTitle => _code == 'en' ? 'Challenges' : 'Challenges';
  String get khelLevel1 => _code == 'en' ? 'Straight' : 'Seedha';
  String get khelLevel2 => _code == 'en' ? 'Wise' : 'Samajhdar';
  String get khelLevel3 => _code == 'en' ? 'Chindi' : 'Chindi';
  String get khelLevel4 => _code == 'en' ? 'Miser' : 'Miser';
  String get khelLevel5 => _code == 'en' ? 'Kanjoos' : 'Kanjoos';
  String get khelLevel6 => _code == 'en' ? 'Chindi Samrat' : 'Chindi Samrat';
  String get khelBadgeFirstDay => _code == 'en' ? 'First Clean Day' : 'Pehla Saaf Din';
  String get khelBadgeFirstDayDesc => _code == 'en'
      ? 'One whole day, zero spends.'
      : 'Poora ek din, zero kharcha.';
  String get khelBadgeL1 => _code == 'en' ? 'Rung 1 — 3 days' : 'Rung 1 — 3 din';
  String get khelBadgeL1Desc => _code == 'en'
      ? 'Three straight no-spend days.'
      : 'Teen lagataar no-spend din.';
  String get khelBadgeL2 => _code == 'en' ? 'Rung 2 — 7 days' : 'Rung 2 — 7 din';
  String get khelBadgeL2Desc => _code == 'en'
      ? 'A full week of restraint.'
      : 'Poora hafta sanyam.';
  String get khelBadgeL3 => _code == 'en' ? 'Rung 3 — 14 days' : 'Rung 3 — 14 din';
  String get khelBadgeL3Desc => _code == 'en'
      ? 'Two weeks. The wallet approves.'
      : 'Do hafte. Wallet pershaan hai.';
  String get khelBadgeL4 => _code == 'en' ? 'Rung 4 — 21 days' : 'Rung 4 — 21 din';
  String get khelBadgeL4Desc => _code == 'en'
      ? 'Three weeks of saying no.'
      : 'Teen hafte na bolne ki kala.';
  String get khelBadgeL5 => _code == 'en' ? 'Rung 5 — 30 days' : 'Rung 5 — 30 din';
  String get khelBadgeL5Desc => _code == 'en'
      ? 'A whole month. Legendary.'
      : 'Poora mahina. Dhamakedaar.';
  String get khelBadgeL6 => _code == 'en' ? 'Rung 6 — 50 days' : 'Rung 6 — 50 din';
  String get khelBadgeL6Desc => _code == 'en'
      ? 'Fifty days. Chindi Samrat.'
      : 'Pachas din. Chindi Samrat.';
  String get khelBadgeComeback => _code == 'en' ? 'Comeback' : 'Comeback';
  String get khelBadgeComebackDesc => _code == 'en'
      ? 'Broke a streak, built a new 3-day one.'
      : 'Streak toota, phir naya 3-din bana.';
  String get khelBadgeFreeze => _code == 'en' ? 'First Freeze' : 'Pehli Freeze';
  String get khelBadgeFreezeDesc => _code == 'en'
      ? 'Used a freeze to save a streak.'
      : 'Streak bachane ke liye freeze lagayi.';
  String get khelBadgeChallenge30 => _code == 'en' ? 'The 30 Challenge' : '30 ka Challenge';
  String get khelBadgeChallenge30Desc => _code == 'en'
      ? 'Completed the 30-day challenge.'
      : '30-din challenge complete kiya.';
  String khelChallengeLabel(int current, int target, String reward) =>
      _code == 'en'
          ? '$current / $target days — reward: $reward freeze(s)'
          : '$current / $target din — inaam: $reward freeze';

  // ── Screen redesign (phase-07 UI pass) ────────────────────────────
  String get aajSpentTodayLabel =>
      _code == 'en' ? 'Spent today' : 'Aaj ka kharcha';
  String aajEntriesChip(int count) =>
      _code == 'en' ? '$count entries' : '$count entries';
  String get aajMovementTitle =>
      _code == 'en' ? "Today's movement" : 'Aaj ki movement';
  String get aajYesterdayChip =>
      _code == 'en' ? 'vs yesterday' : 'kal se';
  String get ledgerTitle => _code == 'en' ? 'Ledger' : 'Kitaab';
  String get ledgerDayToday => _code == 'en' ? 'Today' : 'Aaj';
  String get ledgerDayYesterday => _code == 'en' ? 'Yesterday' : 'Kal';

  // ── Phase-08: Lakshman Rekha (budgets) ───────────────────────────
  String get budgetTitle => 'Lakshman Rekha';
  String get budgetSectionCategories =>
      _code == 'en' ? 'By category' : 'Category-wise';
  String get budgetEmptyTitle => 'Koi rekha nahi';
  String get budgetEmptyBody => _code == 'en'
      ? 'Draw a Lakshman Rekha on your wallet — UDAO will guard it, and roast you if you cross.'
      : 'Wallet pe rekha kheencho — UDAO uski raksha karega, cross kiya toh roast pakka.';
  String get budgetNewTitle => 'Nayi rekha';
  String get budgetEditTitle => 'Rekha edit';
  String get budgetNewCta => 'Nayi rekha';
  String get budgetTargetLabel => 'Kahan rekha?';
  String get budgetWalletLabel => 'Poora wallet';
  String get budgetLimitLabel => 'Kitni? (₹)';
  String get budgetLimitHint => _code == 'en' ? 'e.g. 5000' : 'jaise 5000';
  String get budgetLimitError => 'Rekha ₹0 se upar honi chahiye';
  String get budgetPeriodLabel => 'Kis hisaab se';
  String get budgetPeriodWeekly => 'Haftewar';
  String get budgetPeriodMonthly => 'Mahinewar';
  String get budgetRolloverLabel => 'Bacha hua aage le jao';
  String get budgetRolloverSub => 'Jo bacha, wo agle period mein jud jayega';
  String get budgetSaveCta => 'Rekha lagao';
  String get budgetDeleteCta => 'Hatao';
  String budgetDaysLeft(int count) => '$count din bache';
  String get budgetLeftLabel => 'Bacha';
  String get budgetExceededStamp => 'REKHA CROSS';
  String budgetCarryChip(String amount) => '$amount pichhle se aaya';
  String get budgetSavedSnack => 'Rekha lag gayi';
  String get budgetDeletedSnack => 'Rekha hata di';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'hi' || locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
