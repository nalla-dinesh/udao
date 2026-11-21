// phase-01
// Haptics kill-switch. Calls happen only while disabled, so no
// platform channel is ever touched in this plain (binding-less) test.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/ui/haptics.dart';

void main() {
  test('enabled by default; kill switch gates every flavor', () {
    expect(UdaoHaptics.enabled, isTrue);
    UdaoHaptics.setEnabled(false);
    expect(UdaoHaptics.enabled, isFalse);
    UdaoHaptics.tap();
    UdaoHaptics.impact();
    UdaoHaptics.celebrate();
    UdaoHaptics.setEnabled(true);
    expect(UdaoHaptics.enabled, isTrue);
  });

  test('pref key is frozen (settings screen depends on it)', () {
    expect(UdaoHaptics.prefKey, 'haptics_enabled');
  });
}
