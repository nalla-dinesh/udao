// phase-03
// Riverpod wiring for the capture stack. One rule holds the file
// together: NOTHING here touches platform channels directly except
// [PlatformCaptureBridge] behind the [captureBridgeProvider] seam —
// so every downstream piece (pipeline, replay, UI, tests) runs on
// fakes without a device.
import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:udao/core/result/result.dart';

import '../../data/db/dao/kv_dao.dart';
import '../../data/db/dao/txn_dao.dart';
import '../../data/db/udao_database.dart';
import '../../data/repos/ledger_repo.dart';
import 'bridge/capture_bridge.dart';
import 'bridge/capture_raw_event.dart';
import 'bridge/listener_status.dart';
import 'bridge/wal_replay.dart';
import 'pipeline/capture_pipeline.dart';
import 'pipeline/ledger_events.dart';

/// The single encrypted DB handle (UdaoDatabase is a singleton).
final Provider<UdaoDatabase> dbProvider = Provider<UdaoDatabase>(
  (Ref ref) => UdaoDatabase.instance,
);

final Provider<LedgerRepo> ledgerRepoProvider = Provider<LedgerRepo>(
  (Ref ref) => LedgerRepo(ref.watch(dbProvider)),
);

final Provider<TxnDao> txnDaoProvider = Provider<TxnDao>(
  (Ref ref) => TxnDao(ref.watch(dbProvider).db),
);

final Provider<KvDao> kvDaoProvider = Provider<KvDao>(
  (Ref ref) => KvDao(ref.watch(dbProvider).db),
);

/// The capture seam: production binds the platform channels, tests
/// override with a fake.
final Provider<CaptureBridge> captureBridgeProvider = Provider<CaptureBridge>(
  (Ref ref) => PlatformCaptureBridge(),
);

/// Broadcast domain events (one per auto-accepted txn).
final Provider<LedgerEvents> ledgerEventsProvider =
    Provider<LedgerEvents>((Ref ref) {
  final LedgerEvents events = LedgerEvents();
  ref.onDispose(events.dispose);
  return events;
});

final Provider<CapturePipeline> capturePipelineProvider =
    Provider<CapturePipeline>((Ref ref) {
  return CapturePipeline(
    repo: ref.watch(ledgerRepoProvider),
    txnDao: ref.watch(txnDaoProvider),
    kvDao: ref.watch(kvDaoProvider),
    events: ref.watch(ledgerEventsProvider),
  );
});

/// Live-event ingestion daemon. Watching this provider from main is
/// what STARTS capture; un-watching (never, in practice) stops it.
final Provider<StreamSubscription<CaptureRawEvent>> captureDaemonProvider =
    Provider<StreamSubscription<CaptureRawEvent>>((Ref ref) {
  final CaptureBridge bridge = ref.watch(captureBridgeProvider);
  final CapturePipeline pipeline = ref.watch(capturePipelineProvider);
  final StreamSubscription<CaptureRawEvent> sub =
      bridge.liveEvents.listen((CaptureRawEvent event) {
    unawaited(pipeline.run(event));
  });
  ref.onDispose(sub.cancel);
  return sub;
});

/// Foreground WAL drain. SMS arrivals are written to the WAL by a
/// process-agnostic broadcast receiver (the engine may be dead when
/// they land) — but when the app IS open, waiting for the next app
/// start to see a bank SMS is unacceptable. This daemon drains the
/// WAL every 15s and on every app resume. Replay is idempotent
/// (at-least-once + the dedup engine absorbs re-runs); the flag
/// merely keeps drains serialized.
final Provider<void> walDrainDaemonProvider = Provider<void>((Ref ref) {
  final CaptureBridge bridge = ref.watch(captureBridgeProvider);
  final CapturePipeline pipeline = ref.watch(capturePipelineProvider);
  bool draining = false;
  Future<void> drain() async {
    if (draining) {
      return;
    }
    draining = true;
    try {
      await replayWal(bridge: bridge, pipeline: pipeline);
    } on Object {
      // Non-fatal: the next tick retries; the start-time replay in
      // bootstrapCapture is the zero-loss backstop.
    } finally {
      draining = false;
    }
  }

  final Timer ticker = Timer.periodic(
    const Duration(seconds: 15),
    (_) => unawaited(drain()),
  );
  final AppLifecycleListener lifecycle = AppLifecycleListener(
    onResume: () => unawaited(drain()),
  );
  ref.onDispose(() {
    ticker.cancel();
    lifecycle.dispose();
  });
});

/// Boot sequence: push the asset allowlist to native (so the listener
/// filters correctly even before the Dart UI is up) and replay the
/// WAL. Called once from main after the DB warm-up. Never throws —
/// capture boot must not block first frame.
Future<void> bootstrapCapture(ProviderContainer container) async {
  final CaptureBridge bridge = container.read(captureBridgeProvider);
  final CapturePipeline pipeline = container.read(capturePipelineProvider);

  try {
    final String json =
        await rootBundle.loadString('assets/capture/allowlist.json');
    await bridge.pushAllowlist(json);
  } on Object {
    // Asset read / push failure is non-fatal: native keeps its
    // default or last-cached allowlist.
  }

  await replayWal(bridge: bridge, pipeline: pipeline);

  // Start live ingestion for the rest of this session.
  container.read(captureDaemonProvider);
  // And keep draining the WAL while the process lives (SMS while the
  // app is open must not wait for the next cold start).
  container.read(walDrainDaemonProvider);
}

/// Listener health, polled every 60s while the app is foregrounded
/// and re-polled the instant the user returns from system settings.
final NotifierProvider<ListenerHealthNotifier, AsyncValue<ListenerStatus>>
    listenerHealthProvider =
    NotifierProvider<ListenerHealthNotifier, AsyncValue<ListenerStatus>>(
  ListenerHealthNotifier.new,
);

class ListenerHealthNotifier extends Notifier<AsyncValue<ListenerStatus>> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  @override
  AsyncValue<ListenerStatus> build() {
    ref.onDispose(_teardown);
    _lifecycle = AppLifecycleListener(onResume: refresh);
    _startTimer();
    refresh();
    return const AsyncLoading<ListenerStatus>();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => refresh());
  }

  Future<void> refresh() async {
    final Result<ListenerStatus> status =
        await ref.read(captureBridgeProvider).status();
    final ListenerStatus? value = status.valueOrNull;
    if (value != null) {
      state = AsyncData<ListenerStatus>(value);
    } else if (state is! AsyncData<ListenerStatus>) {
      state = AsyncError<ListenerStatus>(
        status.failureOrNull ?? StateError('listener status unavailable'),
        StackTrace.current,
      );
    }
  }

  void _teardown() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
