// phase-01
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:udao/core/ui/udao_bottom_nav.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  List<UdaoNavItem> items() => <UdaoNavItem>[
        const UdaoNavItem(label: 'AAJ', iconData: PhosphorIconsBold.gearSix),
        const UdaoNavItem(label: 'CHAT', iconData: PhosphorIconsBold.gearSix),
        const UdaoNavItem(label: 'KHEL', iconData: PhosphorIconsBold.gearSix),
        const UdaoNavItem(label: 'LEDGER', iconData: PhosphorIconsBold.gearSix),
        const UdaoNavItem(label: 'SETTINGS', iconData: PhosphorIconsBold.gearSix),
      ];

  testWidgets('renders every destination label', (WidgetTester tester) async {
    await pumpUdao(
      tester,
      UdaoBottomNav(
        currentIndex: 0,
        onTap: (int i) {},
        items: items(),
      ),
    );
    for (final String label in <String>['AAJ', 'CHAT', 'KHEL', 'LEDGER', 'SETTINGS']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('taps report the tapped index', (WidgetTester tester) async {
    final List<int> taps = List<int>.empty(growable: true);
    await pumpUdao(
      tester,
      UdaoBottomNav(
        currentIndex: 2,
        onTap: taps.add,
        items: items(),
      ),
    );

    await tester.tap(find.text('SETTINGS'));
    expect(taps, <int>[4]);

    await tester.tap(find.text('AAJ'));
    expect(taps, <int>[4, 0]);
  });

  testWidgets('badge counts cap at 9+', (WidgetTester tester) async {
    await pumpUdao(
      tester,
      UdaoBottomNav(
        currentIndex: 0,
        onTap: (int i) {},
        items: items(),
        badges: const <int, int>{1: 12},
      ),
    );
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('UdaoNavItem asserts exactly one icon source', (
    WidgetTester tester,
  ) async {
    expect(
      () => UdaoNavItem(label: 'X', svgAsset: 'a.svg', iconData: PhosphorIconsBold.gearSix),
      throwsA(isA<AssertionError>()),
    );
  });
}
