// phase-01
// Shared-preferences keys + tiny typed helpers. One home for every
// persisted flag so settings screens and flows can never disagree
// about key names.
import 'package:shared_preferences/shared_preferences.dart';

abstract final class LocalPrefs {
  static const String onboardingDoneKey = 'onboarding_done';
  static const String userNameKey = 'user_name';
  static const String personalityKey = 'personality';
  static const String notifIntentKey = 'notification_intent';

  static Future<bool> isOnboardingDone() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(onboardingDoneKey) ?? false;
  }

  static Future<String> userName() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(userNameKey) ?? '';
  }

  static Future<String> personality() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(personalityKey) ?? 'savage';
  }
}
