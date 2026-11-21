// phase-03
// Dart side of the capture boundary. The abstract class is the seam:
// the pipeline and the UI only ever see [CaptureBridge]; tests inject
// fakes; production binds the platform channels. Nothing above this
// file imports flutter/services — that is the whole point.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/log/udao_logger.dart';
import 'package:udao/core/result/result.dart';

import 'capture_channels.dart';
import 'capture_raw_event.dart';
import 'listener_status.dart';

final UdaoLogger _log = udaoLog.child('capture');

abstract class CaptureBridge {
  /// Live posted notifications (broadcast: many listeners, no loss by
  /// back-pressure on subscribe). WAL replay is NOT on this stream —
  /// it is pull-based via [readWAL]/[ackWAL].
  Stream<CaptureRawEvent> get liveEvents;

  /// Snapshot of the native listener's health.
  Future<Result<ListenerStatus>> status();

  /// All pending WAL entries, oldest first.
  Future<Result<List<CaptureRawEvent>>> readWAL();

  /// Drops WAL entries with `ts <= upToTs` (and, natively, anything
  /// older than 7 days). Returns surviving entries.
  Future<Result<int>> ackWAL(int upToTs);

  /// The one safe rebind primitive.
  Future<Result<bool>> requestRebind();

  /// Opens the system notification-access settings screen.
  Future<Result<bool>> openListenerSettings();

  /// Disable + re-enable + rebind (stuck-listener workaround).
  Future<Result<bool>> rebindViaToggle();

  /// Installs a new allowlist (JSON array of package ids); also
  /// cached natively so the listener has it before the engine runs.
  Future<Result<bool>> pushAllowlist(String json);
}

class PlatformCaptureBridge extends CaptureBridge {
  static const EventChannel _event = EventChannel(CaptureChannels.stream);

  static const MethodChannel _control = MethodChannel(CaptureChannels.control);

  PlatformCaptureBridge() {
    _live = _event
        .receiveBroadcastStream()
        .map((Object? line) => line as String? ?? '')
        .map(CaptureRawEvent.fromLine)
        .where((CaptureRawEvent? e) => e != null)
        .cast<CaptureRawEvent>()
        // The live stream must never surface an unhandled error into
        // the zone: a bad line or a flapping engine is logged and
        // dropped — the WAL replay is the correctness backstop.
        .handleError((Object e) {
      _log.error('live stream error', error: e);
    });
  }

  late final Stream<CaptureRawEvent> _live;

  @override
  Stream<CaptureRawEvent> get liveEvents => _live;

  @override
  Future<Result<ListenerStatus>> status() async {
    return _guard('listenerStatus', () async {
      final Map<Object?, Object?> raw =
          (await _control.invokeMethod<Object?>(
        CaptureChannels.methodListenerStatus,
      )) as Map<Object?, Object?>;
      return ListenerStatus.fromMap(raw);
    });
  }

  @override
  Future<Result<List<CaptureRawEvent>>> readWAL() async {
    return _guard('getWAL', () async {
      final Object? raw =
          await _control.invokeMethod<Object?>(CaptureChannels.methodGetWAL);
      final List<Object?> lines = raw is List ? raw : const <Object?>[];
      final List<CaptureRawEvent> events = <CaptureRawEvent>[];
      int dropped = 0;
      for (final Object? line in lines) {
        final CaptureRawEvent? event =
            CaptureRawEvent.fromLine(line as String? ?? '');
        if (event == null) {
          dropped++;
        } else {
          events.add(event);
        }
      }
      if (dropped > 0) {
        // Count only — never the content (privacy law).
        _log.warn('getWAL: skipped $dropped malformed lines');
      }
      return events;
    });
  }

  @override
  Future<Result<int>> ackWAL(int upToTs) async {
    return _guard('ackWAL', () async {
      final int survivors =
          await _control.invokeMethod<int>(CaptureChannels.methodAckWAL, upToTs) ?? 0;
      return survivors;
    });
  }

  @override
  Future<Result<bool>> requestRebind() async {
    return _guard('requestRebind', () async {
      return await _control.invokeMethod<bool>(
            CaptureChannels.methodRequestRebind,
          ) ??
          false;
    });
  }

  @override
  Future<Result<bool>> openListenerSettings() async {
    return _guard('openListenerSettings', () async {
      return await _control.invokeMethod<bool>(
            CaptureChannels.methodOpenListenerSettings,
          ) ??
          false;
    });
  }

  @override
  Future<Result<bool>> rebindViaToggle() async {
    return _guard('rebindViaToggle', () async {
      return await _control.invokeMethod<bool>(
            CaptureChannels.methodRebindViaToggle,
          ) ??
          false;
    });
  }

  @override
  Future<Result<bool>> pushAllowlist(String json) async {
    return _guard('pushAllowlist', () async {
      return await _control.invokeMethod<bool>(
            CaptureChannels.methodPushAllowlist,
            json,
          ) ??
          false;
    });
  }

  Future<Result<T>> _guard<T>(String scope, Future<T> Function() body) async {
    try {
      return Ok(await body());
    } on Object catch (e, s) {
      _log.error('$scope failed', error: e);
      return Err(CaptureFailure('$scope failed', cause: e, stackTrace: s));
    }
  }
}
