// phase-03
// Test double for the capture seam. Records every control call and
// replays canned state — the whole point of CaptureBridge being an
// abstract class (see lib/features/capture/bridge/capture_bridge.dart).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/features/capture/bridge/capture_bridge.dart';
import 'package:udao/features/capture/bridge/capture_raw_event.dart';
import 'package:udao/features/capture/bridge/listener_status.dart';
import 'package:udao/features/capture/capture_providers.dart';

class FakeCaptureBridge extends CaptureBridge {
  FakeCaptureBridge({
    this.statusValue = const ListenerStatus(
      connected: false,
      lastEventAt: 0,
      componentEnabled: false,
    ),
    List<CaptureRawEvent> wal = const <CaptureRawEvent>[],
  }) : walValue = List<CaptureRawEvent>.of(wal);

  ListenerStatus statusValue;
  final List<CaptureRawEvent> walValue;

  /// Flip to simulate a native read failure ( WAL unreadable ).
  bool failReadWAL = false;

  /// Last ack call (null = never acked).
  int? ackedUpTo;
  int openSettingsCalls = 0;
  int rebindCalls = 0;
  int toggleCalls = 0;
  final List<String> pushedAllowlists = <String>[];

  // sync delivery is deliberate: emit() must run listeners inline so
  // widget tests can assert after a single pump. With the default
  // async controller, delivery races the frame (phase-03 errata
  // round 2: same test passed and failed across runs).
  final StreamController<CaptureRawEvent> _live =
      StreamController<CaptureRawEvent>.broadcast(sync: true);

  /// Simulates a native live push.
  void emit(CaptureRawEvent event) => _live.add(event);

  Future<void> close() => _live.close();

  @override
  Stream<CaptureRawEvent> get liveEvents => _live.stream;

  @override
  Future<Result<ListenerStatus>> status() async => Ok(statusValue);

  @override
  Future<Result<List<CaptureRawEvent>>> readWAL() async {
    if (failReadWAL) {
      return const Err(CaptureFailure('getWAL failed'));
    }
    return Ok(List<CaptureRawEvent>.of(walValue));
  }

  @override
  Future<Result<int>> ackWAL(int upToTs) async {
    ackedUpTo = upToTs;
    return const Ok(0);
  }

  @override
  Future<Result<bool>> requestRebind() async {
    rebindCalls++;
    return const Ok(true);
  }

  @override
  Future<Result<bool>> openListenerSettings() async {
    openSettingsCalls++;
    return const Ok(true);
  }

  @override
  Future<Result<bool>> rebindViaToggle() async {
    toggleCalls++;
    return const Ok(true);
  }

  @override
  Future<Result<bool>> pushAllowlist(String json) async {
    pushedAllowlists.add(json);
    return const Ok(true);
  }
}

/// Timer-free [ListenerHealthNotifier] stand-in: build() and
/// refresh() only mirror [FakeCaptureBridge.statusValue], so widget
/// tests never leave pending 60s timers behind.
class FakeListenerHealthNotifier extends ListenerHealthNotifier {
  FakeListenerHealthNotifier(this.bridge);

  final FakeCaptureBridge bridge;

  @override
  AsyncValue<ListenerStatus> build() {
    state = AsyncData<ListenerStatus>(bridge.statusValue);
    return state;
  }

  @override
  Future<void> refresh() async {
    state = AsyncData<ListenerStatus>(bridge.statusValue);
  }
}

/// Standard overrides for widget tests touching capture UI.
List<Override> captureTestOverrides(FakeCaptureBridge bridge) {
  return <Override>[
    captureBridgeProvider.overrideWithValue(bridge),
    listenerHealthProvider
        .overrideWith(() => FakeListenerHealthNotifier(bridge)),
  ];
}
