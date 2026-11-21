// phase-01
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/permission_priming_card.dart';
import 'package:udao/core/ui/udao_button.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('renders title, body, CTA and secondary',
      (WidgetTester tester) async {
    await pumpUdao(
      tester,
      PermissionPrimingCard(
        title: 'Verdict ke liye notification',
        body: 'Sab kuch phone ke andar rehta hai.',
        ctaLabel: 'ALLOW KARUNGA',
        secondaryLabel: 'BAAD MEIN',
        onSecondary: () {},
      ),
    );
    expect(find.text('Verdict ke liye notification'), findsOneWidget);
    expect(find.text('Sab kuch phone ke andar rehta hai.'), findsOneWidget);
    expect(find.byType(UdaoButton), findsNWidgets(2));
  });

  testWidgets('primary CTA fires', (WidgetTester tester) async {
    bool fired = false;
    await pumpUdao(
      tester,
      PermissionPrimingCard(
        title: 'T',
        body: 'B',
        ctaLabel: 'ALLOW KARUNGA',
        onCta: () => fired = true,
      ),
    );
    await tester.tap(find.text('ALLOW KARUNGA'));
    expect(fired, isTrue);
  });
}
