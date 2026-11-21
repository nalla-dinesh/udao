// phase-01
// Golden scaffold: the theme showcase screenshotted at 375×812 and
// 412×915 logical px in BOTH themes, DPR 1.0.
//
// Baseline policy: the AUTO-BASELINE comparator writes a missing
// baseline on first run (and passes); afterwards the bytes must match
// exactly. Regenerate intentionally by deleting the file under
// test/golden/goldens/.
//
// The showcase contains infinite animations (shimmer, level pulse), so
// these tests pump fixed durations — never pumpAndSettle.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/theme/udao_theme.dart';
import 'package:udao/features/settings/theme_showcase_screen.dart';
import 'package:udao/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Missing baseline → auto-write + pass; existing baseline → byte-exact.
class AutoBaselineComparator implements GoldenFileComparator {
  File _file(Uri golden) => File(golden.toFilePath());

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final File file = _file(golden);
    if (!file.existsSync()) {
      await update(golden, imageBytes);
      return true;
    }
    final Uint8List baseline = await file.readAsBytes();
    if (listEquals(baseline, imageBytes)) {
      return true;
    }
    await File('${file.path}.actual.png').writeAsBytes(
      imageBytes,
      flush: true,
    );
    return false;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    final File file = _file(golden);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(imageBytes, flush: true);
  }

Future<ui.Image> getBaseline(Uri golden) async {
    final Uint8List bytes = await _file(golden).readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<Size> getSize(Uri golden) async {
    final ui.Image image = await getBaseline(golden);
    final Size size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  @override
  Uri getTestUri(Uri key, int? version) {
    if (version == null) {
      return key;
    }
    final String keyString = key.toString();
    final int dot = keyString.lastIndexOf('.');
    return Uri.parse(
      dot == -1
          ? '$keyString.$version'
          : '${keyString.substring(0, dot)}.$version${keyString.substring(dot)}',
    );
  }
}

Future<void> _pumpShowcase(
  WidgetTester tester, {
  required bool dark,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? UdaoTheme.dark() : UdaoTheme.light(),
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ThemeShowcaseScreen(),
    ),
  );
  // One deterministic frame mid-animation (shimmer position and glow
  // progress are a pure function of this elapsed time).
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  goldenFileComparator = AutoBaselineComparator();

  testWidgets('showcase golden — dark 375×812', (WidgetTester tester) async {
    await _pumpShowcase(tester, dark: true, size: const Size(375, 812));
    await expectLater(
      find.byType(ThemeShowcaseScreen),
      matchesGoldenFile('test/golden/goldens/showcase_dark_375x812.png'),
    );
  });

  testWidgets('showcase golden — light 375×812', (WidgetTester tester) async {
    await _pumpShowcase(tester, dark: false, size: const Size(375, 812));
    await expectLater(
      find.byType(ThemeShowcaseScreen),
      matchesGoldenFile('test/golden/goldens/showcase_light_375x812.png'),
    );
  });

  testWidgets('showcase golden — dark 412×915', (WidgetTester tester) async {
    await _pumpShowcase(tester, dark: true, size: const Size(412, 915));
    await expectLater(
      find.byType(ThemeShowcaseScreen),
      matchesGoldenFile('test/golden/goldens/showcase_dark_412x915.png'),
    );
  });

  testWidgets('showcase golden — light 412×915', (WidgetTester tester) async {
    await _pumpShowcase(tester, dark: false, size: const Size(412, 915));
    await expectLater(
      find.byType(ThemeShowcaseScreen),
      matchesGoldenFile('test/golden/goldens/showcase_light_412x915.png'),
    );
  });
}
