// phase-01
// The redirect decision, as a pure function — no router, no prefs,
// no ambiguity.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/constants/routes.dart';
import 'package:udao/core/router/udao_router.dart';

void main() {
  test('fresh install is forced into onboarding from anywhere', () {
    expect(
      udaoRedirect(onboardingDone: false, location: Routes.aaj),
      Routes.onboarding,
    );
    expect(
      udaoRedirect(onboardingDone: false, location: Routes.settings),
      Routes.onboarding,
    );
    expect(
      udaoRedirect(onboardingDone: false, location: Routes.onboarding),
      isNull,
      reason: 'already there',
    );
  });

  test('a finished user never sees onboarding again', () {
    expect(
      udaoRedirect(onboardingDone: true, location: Routes.onboarding),
      Routes.aaj,
    );
    expect(
      udaoRedirect(onboardingDone: true, location: Routes.chat),
      isNull,
    );
    expect(
      udaoRedirect(onboardingDone: true, location: Routes.ledger),
      isNull,
    );
  });
}
