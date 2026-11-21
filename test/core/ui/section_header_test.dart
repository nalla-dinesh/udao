// phase-01
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/section_header.dart';

import '../../helpers/udao_test_app.dart';

void _noop() {}

void main() {
  testWidgets('renders number, label and optional action',
      (WidgetTester tester) async {
    await pumpUdao(
      tester,
      // The action pill renders only when it is wired to a callback —
      // a tappable-looking label with no onTap is dead UI.
      const SectionHeader(
        number: '01',
        label: 'LEDGER',
        actionLabel: 'SEE ALL',
        onAction: _noop,
      ),
    );
    expect(find.text('01'), findsOneWidget);
    expect(find.text('LEDGER'), findsOneWidget);
    expect(find.text('SEE ALL'), findsOneWidget);
  });

  testWidgets('action tap fires callback', (WidgetTester tester) async {
    bool fired = false;
    await pumpUdao(
      tester,
      SectionHeader(
        number: '02',
        label: 'KHEL',
        actionLabel: 'SEE ALL',
        onAction: () => fired = true,
      ),
    );
    await tester.tap(find.text('SEE ALL'));
    expect(fired, isTrue);
  });
}
