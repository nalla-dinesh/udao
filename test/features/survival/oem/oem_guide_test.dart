// phase-05
// Structural invariants of the OEM guide matrix: every one of the 11
// makers has a complete guide, every deep link is a well-formed
// component string, and the manual fallback is ALWAYS present — a
// dead OEM link can never be a dead end.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/survival/oem/oem_detector.dart';
import 'package:udao/features/survival/oem/oem_guide_data.dart';

final RegExp _componentRe =
    RegExp(r'^[a-zA-Z0-9._]+/[a-zA-Z0-9._]+$');

void main() {
  test('every OemId has a guide (no silent stock fallback)', () {
    for (final OemId id in OemId.values) {
      final OemSetupGuide guide = OemGuideData.forId(id);
      expect(guide.oem, id, reason: 'guide registered under its own id');
    }
  });

  test('unknown lookups fail safe to the stock guide', () {
    expect(OemGuideData.forId(OemId.stock).oem, OemId.stock);
    expect(OemGuideData.all, hasLength(11));
  });

  group('per-guide completeness', () {
    for (final MapEntry(:OemId key, :OemSetupGuide value)
        in OemGuideData.all.entries) {
      test('${key.slug} guide is complete and honest', () {
        expect(value.summary, isNotEmpty);
        expect(
          value.steps,
          isNotEmpty,
          reason: 'at least one step',
        );
        expect(
          value.manualSteps,
          isNotEmpty,
          reason: 'manual fallback ALWAYS present',
        );
        expect(value.notes, isNotEmpty);
        expect(key.dontKillMyAppUrl, startsWith('https://'));

        for (final OemGuideStep step in value.steps) {
          expect(step.title, isNotEmpty);
          expect(step.detail, isNotEmpty);
          final OemDeepLink? link = step.deepLink;
          if (link != null) {
            expect(link.label, isNotEmpty);
            expect(
              link.component,
              matches(_componentRe),
              reason: 'flat ComponentName "pkg/cls", got: ${link.component}',
            );
          }
        }
      });
    }
  });

  test('xiaomi guide carries the autostart + battery deep links', () {
    final OemSetupGuide guide = OemGuideData.forId(OemId.xiaomi);
    final List<String> components = <String>[
      for (final OemGuideStep s in guide.steps)
        if (s.deepLink != null) s.deepLink!.component,
    ];
    expect(components, contains(contains('miui.securitycenter')));
    expect(components, contains(contains('miui.powerkeeper')));
  });

  test('vivo and iqoo guides differ (sub-brand gets its own links)', () {
    final OemSetupGuide vivo = OemGuideData.forId(OemId.vivo);
    final OemSetupGuide iqoo = OemGuideData.forId(OemId.iqoo);
    expect(
      vivo.steps.first.deepLink!.component,
      isNot(iqoo.steps.first.deepLink!.component),
    );
    expect(iqoo.steps.first.deepLink!.component, contains('iqoo.secure'));
  });

  test('nokia and stock guides stay humble (no OEM deep links)', () {
    for (final OemId id in <OemId>[OemId.nokia, OemId.stock]) {
      final OemSetupGuide guide = OemGuideData.forId(id);
      for (final OemGuideStep s in guide.steps) {
        expect(
          s.deepLink,
          isNull,
          reason: '${id.slug} has no OEM-specific screens to open',
        );
      }
    }
  });

  test('huawei guide mentions the three-toggle manual manage', () {
    final OemSetupGuide guide = OemGuideData.forId(OemId.huawei);
    final String joined =
        '${guide.steps.map((s) => '${s.title} ${s.detail}').join(' ')} '
        '${guide.manualSteps.join(' ')}';
    expect(joined.toLowerCase(), contains('manage manually'));
  });
}
