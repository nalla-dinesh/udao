// phase-01
// UDAO app root — dual themes (system mode), branded router, Hinglish
// localizations with English fallback.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/constants/app_constants.dart';
import 'core/router/udao_router.dart';
import 'core/theme/udao_theme.dart';
import 'l10n/app_localizations.dart';

class UdaoApp extends StatelessWidget {
  const UdaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: UdaoTheme.light(),
      darkTheme: UdaoTheme.dark(),
      routerConfig: buildUdaoRouter(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback:
          (Locale? deviceLocale, Iterable<Locale> supported) {
        if (deviceLocale != null && deviceLocale.languageCode == 'hi') {
          return const Locale('hi');
        }
        return const Locale('en');
      },
    );
  }
}
