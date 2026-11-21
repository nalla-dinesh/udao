// phase-01
// Localizations: hi/en voices differ, the ARB files stay in key
// parity with each other, and unknown locales fall back to English.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/l10n/app_localizations.dart';

void main() {
  const AppLocalizations hi = AppLocalizations(Locale('hi'));
  const AppLocalizations en = AppLocalizations(Locale('en'));

  test('Hinglish is the primary voice, English is distinct', () {
    expect(hi.navAaj, 'Aaj');
    expect(en.navAaj, 'Today');
    expect(hi.obNext, 'Aage');
    expect(en.obNext, 'Next');
    expect(hi.appName, 'UDAO');
    expect(en.appName, 'UDAO');
  });

  test('ARB files exist with identical key sets', () {
    final Map<String, dynamic> hiJson =
        jsonDecode(File('assets/l10n/app_hi.arb').readAsStringSync())
            as Map<String, dynamic>;
    final Map<String, dynamic> enJson =
        jsonDecode(File('assets/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;

    hiJson.remove('@@locale');
    enJson.remove('@@locale');

    expect(hiJson.keys.toSet(), equals(enJson.keys.toSet()));
    expect(hiJson, isNotEmpty);
    expect(hiJson.length, greaterThanOrEqualTo(40));
  });

  test('delegate getters match the ARB source of truth', () {
    final Map<String, dynamic> hiJson =
        jsonDecode(File('assets/l10n/app_hi.arb').readAsStringSync())
            as Map<String, dynamic>;
    final Map<String, dynamic> enJson =
        jsonDecode(File('assets/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;

    // Spot-check every category of key (the ARBs are GENERATED from
    // the delegate, so full parity holds by construction).
    expect(hi.navAaj, hiJson['navAaj'] as String);
    expect(en.navAaj, enJson['navAaj'] as String);
    expect(hi.obNotifBody, hiJson['obNotifBody'] as String);
    expect(en.obNotifBody, enJson['obNotifBody'] as String);
    expect(hi.personalitySenseiDesc, hiJson['personalitySenseiDesc'] as String);
    expect(en.showcaseToggleTheme, enJson['showcaseToggleTheme'] as String);
  });

  test('unknown locales resolve to the English fallback', () {
    const AppLocalizations fr = AppLocalizations(Locale('fr'));
    expect(fr.navAaj, 'Today');
    expect(AppLocalizations.delegate.isSupported(const Locale('hi')), isTrue);
    expect(AppLocalizations.delegate.isSupported(const Locale('en')), isTrue);
    expect(AppLocalizations.delegate.isSupported(const Locale('fr')), isFalse);
  });
}
