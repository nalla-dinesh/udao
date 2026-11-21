// phase-01
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:udao/features/onboarding/onboarding_provider.dart';

void main() {
  test('defaults: page 0, Savage personality, no name, no intent', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    final OnboardingState state = container.read(onboardingProvider);
    expect(state.page, 0);
    expect(state.personality, UdaoPersonality.savage);
    expect(state.name, '');
    expect(state.notifIntent, isFalse);
  });

  test('setters update state immutably', () {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    final OnboardingNotifier notifier =
        container.read(onboardingProvider.notifier);
    notifier
      ..setPage(3)
      ..setPersonality(UdaoPersonality.sensei)
      ..setNotifIntent(true)
      ..setName('Dinesh');

    final OnboardingState state = container.read(onboardingProvider);
    expect(state.page, 3);
    expect(state.personality, UdaoPersonality.sensei);
    expect(state.notifIntent, isTrue);
    expect(state.name, 'Dinesh');
  });

  test('complete() persists the whole setup', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    final OnboardingNotifier notifier =
        container.read(onboardingProvider.notifier);
    notifier
      ..setPersonality(UdaoPersonality.sensei)
      ..setNotifIntent(true)
      ..setName('  Dinesh ');
    await notifier.complete();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_done'), isTrue);
    expect(prefs.getString('personality'), 'sensei');
    expect(prefs.getBool('notification_intent'), isTrue);
    expect(prefs.getString('user_name'), 'Dinesh', reason: 'trimmed');
  });

  test('complete() skips empty names', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(onboardingProvider.notifier).complete();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('user_name'), isFalse);
  });
}
