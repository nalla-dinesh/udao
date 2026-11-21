// phase-05
// Test fakes for the survival stack — mirrors fake_capture_bridge:
// the survival seam, an in-memory kv, and one override bundle that
// keeps EVERY widget test off platform channels AND off the real
// database (phase-04 lesson: no DB in widget tests).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/capture_health_dao.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/features/capture/capture_providers.dart';
import 'package:udao/features/survival/health/health_dashboard_screen.dart';
import 'package:udao/features/survival/health/probe_bridge.dart';
import 'package:udao/features/survival/health/survival_models.dart';
import 'package:udao/features/survival/survival_providers.dart';

import '../capture/fake_capture_bridge.dart';

/// In-memory KvDao (methods overridden; the super db future is never
/// awaited — see class docs in kv_dao.dart).
class FakeKvDao extends KvDao {
  FakeKvDao() : super(_neverDb);

  // A never-completing future that creates NO timer. (errata-2:
  // Future.delayed creates a FakeTimer inside the widget-test's
  // fake-async zone; the FIRST construction per isolate then fails
  // the binding's pending-timer invariant — order-dependent and
  // baffling. A bare Completer future is inert.)
  static final Future<Never> _neverDb = Completer<Never>().future;

  final Map<String, String> _store = <String, String>{};

  @override
  Future<Result<String?>> get(String key) async {
    return Ok<String?>(_store[key]);
  }

  @override
  Future<Result<void>> set(String key, String value) async {
    _store[key] = value;
    return const Ok<void>(null);
  }

  @override
  Future<Result<void>> delete(String key) async {
    _store.remove(key);
    return const Ok<void>(null);
  }

  /// Test helper: pre-load a key.
  void seed(String key, String value) => _store[key] = value;

  /// Test helper: inspect a key.
  String? read(String key) => _store[key];
}

/// Fake survival seam with call counters + canned answers.
class FakeSurvivalBridge implements SurvivalBridgeApi {
  FakeSurvivalBridge({
    this.powerState = _healthyPower,
    this.exitInfos = const <ExitInfo>[],
    this.watchdog = WatchdogSnapshot.empty,
    this.keepAlive = KeepAliveState.stopped,
    this.openOemResult = true,
  });

  static const PowerState _healthyPower = PowerState(
    ignoringBatteryOptimizations: true,
    powerSaverMode: false,
    backgroundRestricted: false,
    standbyBucket: 10,
    deviceIdle: false,
  );

  PowerState powerState;
  List<ExitInfo> exitInfos;
  WatchdogSnapshot watchdog;
  KeepAliveState keepAlive;
  bool openOemResult;

  int getPowerStateCalls = 0;
  int getExitInfosCalls = 0;
  int getWatchdogCalls = 0;
  int getKeepAliveCalls = 0;
  int startKeepAliveCalls = 0;
  int stopKeepAliveCalls = 0;
  int postNotificationCalls = 0;
  int openBatteryListCalls = 0;
  int requestIgnoreBatteryCalls = 0;
  int openAppDetailsCalls = 0;
  final List<String> openOemComponents = <String>[];

  @override
  Future<PowerState> getPowerState() async {
    getPowerStateCalls++;
    return powerState;
  }

  @override
  Future<List<ExitInfo>> getExitInfos() async {
    getExitInfosCalls++;
    return exitInfos;
  }

  @override
  Future<WatchdogSnapshot> getWatchdogSnapshot() async {
    getWatchdogCalls++;
    return watchdog;
  }

  @override
  Future<KeepAliveState> getKeepAliveState() async {
    getKeepAliveCalls++;
    return keepAlive;
  }

  @override
  Future<bool> startKeepAlive() async {
    startKeepAliveCalls++;
    keepAlive = KeepAliveState(
      running: true,
      lastBeatAt: 1,
      beats: keepAlive.beats,
    );
    return true;
  }

  @override
  Future<bool> stopKeepAlive() async {
    stopKeepAliveCalls++;
    keepAlive = KeepAliveState.stopped;
    return true;
  }

  @override
  Future<bool> postNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    postNotificationCalls++;
    lastPostedId = id;
    return true;
  }

  int? lastPostedId;

  @override
  Future<bool> openBatteryOptimizationSettings() async {
    openBatteryListCalls++;
    return true;
  }

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    requestIgnoreBatteryCalls++;
    return true;
  }

  @override
  Future<bool> openAppDetails() async {
    openAppDetailsCalls++;
    return true;
  }

  @override
  Future<bool> openOemScreen(String component) async {
    openOemComponents.add(component);
    return openOemResult;
  }
}

/// The survival override bundle: capture fakes (listener status) +
/// survival fakes + fixture feeds. NOTHING reaches channels or the
/// real database.
List<Override> survivalTestOverrides({
  required FakeCaptureBridge captureBridge,
  required FakeSurvivalBridge survivalBridge,
  FakeKvDao? kv,
  List<CaptureDayStats> stats = const <CaptureDayStats>[],
  int? clock,
  UdaoDeviceInfo? deviceInfo,
}) {
  return <Override>[
    ...captureTestOverrides(captureBridge),
    survivalBridgeProvider.overrideWithValue(survivalBridge),
    kvDaoProvider.overrideWithValue(kv ?? FakeKvDao()),
    captureStatsProvider.overrideWith((Ref ref) async => stats),
    if (clock != null) healthClockProvider.overrideWith((Ref ref) => clock),
    if (deviceInfo != null)
      udaoDeviceInfoProvider.overrideWith((Ref ref) async => deviceInfo),
  ];
}
