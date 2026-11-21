// phase-01
// Onboarding state (riverpod Notifier) — page, notification intent,
// personality (Savage default) and optional display name. Completing
// persists everything to SharedPreferences, which the router redirect
// reads to open the shell.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/local_prefs.dart';

enum UdaoPersonality { savage, hype, silent, sensei }

class OnboardingState {
  const OnboardingState({
    this.page = 0,
    this.notifIntent = false,
    this.personality = UdaoPersonality.savage,
    this.name = '',
  });

  final int page;
  final bool notifIntent;
  final UdaoPersonality personality;
  final String name;

  OnboardingState copyWith({
    int? page,
    bool? notifIntent,
    UdaoPersonality? personality,
    String? name,
  }) {
    return OnboardingState(
      page: page ?? this.page,
      notifIntent: notifIntent ?? this.notifIntent,
      personality: personality ?? this.personality,
      name: name ?? this.name,
    );
  }
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  void setPage(int page) => state = state.copyWith(page: page);

  void setNotifIntent(bool value) =>
      state = state.copyWith(notifIntent: value);

  void setPersonality(UdaoPersonality value) =>
      state = state.copyWith(personality: value);

  void setName(String value) => state = state.copyWith(name: value);

  /// Persists the finished onboarding. The router redirect flips to
  /// the shell as soon as `onboarding_done` is true.
  Future<void> complete() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LocalPrefs.onboardingDoneKey, true);
    await prefs.setString(
      LocalPrefs.personalityKey,
      state.personality.name,
    );
    await prefs.setBool(LocalPrefs.notifIntentKey, state.notifIntent);
    final String name = state.name.trim();
    if (name.isNotEmpty) {
      await prefs.setString(LocalPrefs.userNameKey, name);
    }
  }
}

final NotifierProvider<OnboardingNotifier, OnboardingState>
    onboardingProvider = NotifierProvider<OnboardingNotifier, OnboardingState>(
  OnboardingNotifier.new,
);
