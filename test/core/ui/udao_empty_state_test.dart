// phase-01
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/udao_empty_state.dart';
import 'package:udao/core/ui/udao_button.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('renders illustration title and body', (WidgetTester tester) async {
    await pumpUdao(
      tester,
      const UdaoEmptyState(
        illustration: 'assets/icons/logo-mark.svg',
        title: 'Khaali kitaab',
        body: 'Ek bhi entry nahi.',
      ),
    );
    expect(find.text('Khaali kitaab'), findsOneWidget);
    expect(find.text('Ek bhi entry nahi.'), findsOneWidget);
  });

  testWidgets('optional action renders and fires', (WidgetTester tester) async {
    bool fired = false;
    await pumpUdao(
      tester,
      UdaoEmptyState(
        illustration: 'assets/icons/logo-mark.svg',
        title: 'T',
        body: 'B',
        actionLabel: 'SHURU',
        onAction: () => fired = true,
      ),
    );
    expect(find.byType(UdaoButton), findsOneWidget);
    await tester.tap(find.text('SHURU'));
    expect(fired, isTrue);
  });
}
