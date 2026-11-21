// phase-05
// The survival probe seam — same pattern as the capture bridge: an
// abstract class the app binds to the platform channel and every
// test binds to a fake. NOTHING in the survival feature touches
// MethodChannel directly except [PlatformSurvivalBridge].
import 'package:flutter/services.dart';

import 'survival_models.dart';

/// Read-only probes + the keep-alive lever + OEM/battery intents.
abstract class SurvivalBridgeApi {
  Future<PowerState> getPowerState();

  Future<List<ExitInfo>> getExitInfos();

  Future<WatchdogSnapshot> getWatchdogSnapshot();

  Future<KeepAliveState> getKeepAliveState();

  Future<bool> startKeepAlive();

  Future<bool> stopKeepAlive();

  /// Whitelisted IDs only (escalation + gap alert).
  Future<bool> postNotification({required int id, required String title, required String body});

  /// System list screen — play-safe, no special permission.
  Future<bool> openBatteryOptimizationSettings();

  /// Direct system dialog — POWER FLAVOR ONLY; play builds return
  /// false and the UI chain falls through to the list screen.
  Future<bool> requestIgnoreBatteryOptimizations();

  Future<bool> openAppDetails();

  /// OEM deep link; false = screen not found (caller shows manual steps).
  Future<bool> openOemScreen(String component);
}

class PlatformSurvivalBridge implements SurvivalBridgeApi {
  static const MethodChannel _channel = MethodChannel('udao/survival');

  // The _guard pattern (mirrors PlatformCaptureBridge): if a channel
  // call escapes while tests are tearing down, Swallow it — tests
  // inject fakes and never exercise this class anyway.
  Future<T?> _guard<T>(Future<T?> Function() body) async {
    try {
      return await body();
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<PowerState> getPowerState() async {
    final Map<Object?, Object?>? map =
        await _guard<Map<Object?, Object?>?>(() => _channel.invokeMapMethod('getPowerState'));
    if (map == null) {
      // Honest absence — never fabricate a healthy device.
      return const PowerState(
        ignoringBatteryOptimizations: false,
        powerSaverMode: false,
        backgroundRestricted: null,
        standbyBucket: null,
        deviceIdle: false,
      );
    }
    return PowerState.fromMap(map);
  }

  @override
  Future<List<ExitInfo>> getExitInfos() async {
    final List<Object?>? list =
        await _guard<List<Object?>?>(() => _channel.invokeListMethod('getExitInfos'));
    if (list == null) return const <ExitInfo>[];
    return list
        .whereType<Map<Object?, Object?>>()
        .map(ExitInfo.fromMap)
        .toList(growable: false);
  }

  @override
  Future<WatchdogSnapshot> getWatchdogSnapshot() async {
    final Map<Object?, Object?>? map =
        await _guard<Map<Object?, Object?>?>(() => _channel.invokeMapMethod('getWatchdogSnapshot'));
    if (map == null) return WatchdogSnapshot.empty;
    return WatchdogSnapshot.fromMap(map);
  }

  @override
  Future<KeepAliveState> getKeepAliveState() async {
    final Map<Object?, Object?>? map =
        await _guard<Map<Object?, Object?>?>(() => _channel.invokeMapMethod('getKeepAliveState'));
    if (map == null) return KeepAliveState.stopped;
    return KeepAliveState.fromMap(map);
  }

  @override
  Future<bool> startKeepAlive() async =>
      await _guard<bool?>(() => _channel.invokeMethod('startKeepAlive')) ?? false;

  @override
  Future<bool> stopKeepAlive() async =>
      await _guard<bool?>(() => _channel.invokeMethod('stopKeepAlive')) ?? false;

  @override
  Future<bool> postNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    return await _guard<bool?>(
          () => _channel.invokeMethod(
            'postNotification',
            <String, Object?>{
              'id': id,
              'title': title,
              'body': body,
            },
          ),
        ) ??
        false;
  }

  @override
  Future<bool> openBatteryOptimizationSettings() async =>
      await _guard<bool?>(
        () => _channel.invokeMethod('openBatteryOptimizationSettings'),
      ) ??
      false;

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async =>
      await _guard<bool?>(
        () => _channel.invokeMethod('requestIgnoreBatteryOptimizations'),
      ) ??
      false;

  @override
  Future<bool> openAppDetails() async =>
      await _guard<bool?>(() => _channel.invokeMethod('openAppDetails')) ??
      false;

  @override
  Future<bool> openOemScreen(String component) async =>
      await _guard<bool?>(
        () => _channel.invokeMethod(
          'openOemScreen',
          <String, Object?>{'component': component},
        ),
      ) ??
      false;
}
