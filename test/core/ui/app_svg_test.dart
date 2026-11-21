// phase-01
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:udao/core/ui/app_icons.dart';
import 'package:udao/core/ui/app_svg.dart';

import '../../helpers/udao_test_app.dart';

void main() {
  testWidgets('every registered brand mark renders', (WidgetTester tester) async {
    const List<String> marks = <String>[
      AppIcons.logoMark,
      AppIcons.roastFlame,
      AppIcons.chindiBadge,
      AppIcons.streakFlame,
      AppIcons.jar,
      AppIcons.ladder,
      AppIcons.subscriptionSlayer,
      AppIcons.verdictBell,
    ];

    for (final String mark in marks) {
      await pumpUdao(tester, AppSvg(mark, width: 48, height: 48));
      expect(tester.takeException(), isNull, reason: mark);
    }
  });

  testWidgets('color tints via ColorFilter, default stays untouched',
      (WidgetTester tester) async {
    await pumpUdao(
      tester,
      const AppSvg(AppIcons.logoMark, width: 24, height: 24),
    );
    final SvgPicture plain =
        tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(plain.colorFilter, isNull);

    await pumpUdao(
      tester,
      const AppSvg(AppIcons.logoMark, width: 24, height: 24, color: Color(0xFFFF5A3C)),
    );
    final SvgPicture tinted = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(tinted.colorFilter, isNotNull);
  });
}
