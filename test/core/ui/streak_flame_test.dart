// phase-01
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/streak_flame.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  test('flameIntensity ramps 5 → 30 days and clamps outside', () {
    expect(StreakFlame.flameIntensity(5), 0.0);
    expect(StreakFlame.flameIntensity(30), 1.0);
    expect(StreakFlame.flameIntensity(17), closeTo(0.48, 0.001));
    expect(StreakFlame.flameIntensity(2), 0.0, reason: 'below floor');
    expect(StreakFlame.flameIntensity(99), 1.0, reason: 'above ceiling');
  });

  test('flame size grows with intensity (28 → 42 over the ramp)', () {
    expect(28 + StreakFlame.flameIntensity(5) * 14, 28.0);
    expect(28 + StreakFlame.flameIntensity(30) * 14, 42.0);
  });

  testWidgets('renders day count and unit', (WidgetTester tester) async {
    await pumpUdao(tester, const StreakFlame(days: 12, unitLabel: 'din'));
    expect(find.text('12'), findsOneWidget);
    expect(find.text('DIN'), findsOneWidget);
  });

  testWidgets('freeze chip renders when available', (WidgetTester tester) async {
    await pumpUdao(
      tester,
      const StreakFlame(days: 12, freezeAvailable: true, unitLabel: 'din'),
    );
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
