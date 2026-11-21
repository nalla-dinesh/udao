// phase-04
// Which build the user is running — the runtime source of truth for
// flavor-gated UI (the SMS capture screen must never render in the
// Play build, even if a route bug pointed at it).
//
// PRIMARY: the platform channel (`udao/platform` / `getDeviceInfo`)
// reports BuildConfig.FLAVOR from the actual installed APK. That is
// what the gate screens use — it cannot drift from the store build
// the way a compile-time constant can.
//
// (A compile-time `String.fromEnvironment('app.flavor')` also works
// because --android-flavor defines it, but it is only a secondary
// assert: it evaluates to '' under `flutter run` without a flavor,
// where the channel still says the truth.)
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:udao/core/constants/app_constants.dart';

enum AppFlavor { play, power, unknown }

/// Resolves once per app start; `AppFlavor.unknown` (channel missing
/// or flavor "none" — e.g. an unflavored debug run) fails CLOSED:
/// flavor-gated features stay hidden until proven otherwise.
final FutureProvider<AppFlavor> appFlavorProvider =
    FutureProvider<AppFlavor>((Ref ref) async {
  try {
    final Object? facts = await const MethodChannel(
      AppConstants.platformChannelName,
    ).invokeMethod<Object?>(AppConstants.platformDeviceInfoMethod);
    if (facts is Map) {
      final Object? flavor = facts['appFlavor'];
      switch (flavor) {
        case 'play':
          return AppFlavor.play;
        case 'power':
          return AppFlavor.power;
      }
    }
  } on Object {
    // Channel failure (tests, unknown host): unknown, fail closed.
  }
  return AppFlavor.unknown;
});
