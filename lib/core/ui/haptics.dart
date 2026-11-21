// phase-01
// Haptics wrapper with a global kill-switch (persisted by the settings
// screen from Phase 07; the key is fixed here so both sides agree).
import 'package:flutter/services.dart';

abstract final class UdaoHaptics {
  static const String prefKey = 'haptics_enabled';

  static bool _enabled = true;

  static bool get enabled => _enabled;

  static void setEnabled(bool value) => _enabled = value;

  /// Selection-sized tick — buttons, nav taps, toggles.
  static void tap() {
    if (_enabled) {
      HapticFeedback.selectionClick();
    }
  }

  /// Light impact — chips landing, cards flipping.
  static void impact() {
    if (_enabled) {
      HapticFeedback.lightImpact();
    }
  }

  /// Medium impact — level-ups, verdict delivery.
  static void celebrate() {
    if (_enabled) {
      HapticFeedback.mediumImpact();
    }
  }
}
