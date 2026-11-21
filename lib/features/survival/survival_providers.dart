// phase-05
// Riverpod wiring for the survival stack. Same rule as the capture
// providers: NOTHING here touches a MethodChannel directly except
// the platform bridges ([PlatformSurvivalBridge] behind
// [survivalBridgeProvider], and the read-only `udao/platform`
// device-info provider) — tests override the seams with fakes.
//
// One special duty lives here: the gap-alert FLUSH. The weekly
// workmanager job cannot reach the survival channel (background
// isolate, ADR-0006), so it parks the alert in kv; the dashboard
// reads it, and [flushGapAlert] posts the notification through the
// foreground-engine channel and clears the kv row.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/log/udao_logger.dart';
import '../../core/result/result.dart';
import '../../core/utils/date_utils.dart';
import '../../data/db/dao/kv_dao.dart';
import '../capture/capture_providers.dart';
import 'health/probe_bridge.dart';
import 'health/survival_models.dart';
import 'jobs/background_jobs.dart';
import 'oem/oem_detector.dart';

// ── The survival seam ────────────────────────────────────────────────

/// Everything channel-y behind one fake-able seam.
final Provider<SurvivalBridgeApi> survivalBridgeProvider =
    Provider<SurvivalBridgeApi>((Ref ref) => PlatformSurvivalBridge());

// ── Device / OEM identity ────────────────────────────────────────────

/// Read-only `udao/platform` mirror for the fields the survival
/// stack needs (contract: MainActivity.kt UdaoChannel). Unknown on
/// channel failure — OEM detection then falls to [OemId.stock],
/// which is the honest default.
class UdaoDeviceInfo {
  const UdaoDeviceInfo({
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.versionRelease,
    required this.isEmulator,
  });

  static const UdaoDeviceInfo unknown = UdaoDeviceInfo(
    manufacturer: 'Android',
    brand: 'Android',
    model: '',
    versionRelease: '',
    isEmulator: false,
  );

  final String manufacturer;
  final String brand;
  final String model;
  final String versionRelease;
  final bool isEmulator;
}

final FutureProvider<UdaoDeviceInfo> udaoDeviceInfoProvider =
    FutureProvider<UdaoDeviceInfo>((Ref ref) async {
  try {
    final Object? facts = await const MethodChannel(
      AppConstants.platformChannelName,
    ).invokeMethod<Object?>(AppConstants.platformDeviceInfoMethod);
    if (facts is Map) {
      return UdaoDeviceInfo(
        manufacturer: facts['manufacturer'] as String? ?? 'Android',
        brand: facts['brand'] as String? ?? 'Android',
        model: facts['model'] as String? ?? '',
        versionRelease: facts['versionRelease'] as String? ?? '',
        isEmulator: facts['isEmulator'] as bool? ?? false,
      );
    }
  } on Object {
    // Channel failure (tests): unknown identity, honest defaults.
  }
  return UdaoDeviceInfo.unknown;
});

/// OEM matrix entry for THIS phone.
final FutureProvider<OemId> oemIdProvider = FutureProvider<OemId>(
  (Ref ref) async {
    final UdaoDeviceInfo info = await ref.watch(udaoDeviceInfoProvider.future);
    return const OemDetector()
        .detect(manufacturer: info.manufacturer, brand: info.brand);
  },
);

// ── Probes ───────────────────────────────────────────────────────────

final FutureProvider<PowerState> powerStateProvider =
    FutureProvider<PowerState>((Ref ref) {
  return ref.watch(survivalBridgeProvider).getPowerState();
});

final FutureProvider<List<ExitInfo>> exitInfosProvider =
    FutureProvider<List<ExitInfo>>((Ref ref) {
  return ref.watch(survivalBridgeProvider).getExitInfos();
});

final FutureProvider<WatchdogSnapshot> watchdogSnapshotProvider =
    FutureProvider<WatchdogSnapshot>((Ref ref) {
  return ref.watch(survivalBridgeProvider).getWatchdogSnapshot();
});

// ── Keep-alive lever ─────────────────────────────────────────────────

final NotifierProvider<KeepAliveNotifier, AsyncValue<KeepAliveState>>
    keepAliveProvider =
    NotifierProvider<KeepAliveNotifier, AsyncValue<KeepAliveState>>(
  KeepAliveNotifier.new,
);

class KeepAliveNotifier extends Notifier<AsyncValue<KeepAliveState>> {
  @override
  AsyncValue<KeepAliveState> build() {
    unawaited(_refresh());
    return const AsyncValue<KeepAliveState>.loading();
  }

  Future<void> _refresh() async {
    try {
      final KeepAliveState s =
          await ref.read(survivalBridgeProvider).getKeepAliveState();
      state = AsyncValue<KeepAliveState>.data(s);
    } on Object catch (e, s) {
      state = AsyncValue<KeepAliveState>.error(e, s);
    }
  }

  Future<void> start() async {
    state = const AsyncValue<KeepAliveState>.loading();
    try {
      await ref.read(survivalBridgeProvider).startKeepAlive();
    } finally {
      await _refresh();
    }
  }

  Future<void> stop() async {
    state = const AsyncValue<KeepAliveState>.loading();
    try {
      await ref.read(survivalBridgeProvider).stopKeepAlive();
    } finally {
      await _refresh();
    }
  }
}

// ── kv-backed survival state (acks + nag cooldowns + job mirrors) ────

/// Versioned kv keys — one home, bump the `v` on breaking change.
abstract final class SurvivalKvKeys {
  /// ISO date when the user last acknowledged the OEM setup flow.
  static const String oemSetupAck = 'survival.oemSetupAck.v1';

  /// Epoch ms when the battery-optimization card last NAGGED
  /// (auto-reshown); the card is always renderable from settings —
  /// the cooldown only bounds the unsolicited nag.
  static const String batteryNagAt = 'survival.batteryNagAt.v1';
}

/// True when the battery card may nag again (≤1 per 7 days).
Future<bool> batteryNagAllowed(KvDao kv, {required int nowMs}) async {
  final Result<String?> r = await kv.get(SurvivalKvKeys.batteryNagAt);
  final String? raw = r.valueOrNull;
  final int lastShown = int.tryParse(raw ?? '') ?? 0;
  return nowMs - lastShown >= 7 * 24 * 60 * 60 * 1000;
}

/// Records a nag; swallows errors (a failed timestamp write must
/// never break the dashboard).
Future<void> markBatteryNag(KvDao kv, {required int nowMs}) async {
  try {
    await kv.set(SurvivalKvKeys.batteryNagAt, nowMs.toString());
  } on Object catch (e) {
    udaoLog.error('battery nag stamp failed', error: e);
  }
}

/// OEM setup ack helpers (versioned: a bumped key re-shows the flow).
Future<DateTime?> oemSetupAckedAt(KvDao kv) async {
  final Result<String?> r = await kv.get(SurvivalKvKeys.oemSetupAck);
  final String? raw = r.valueOrNull;
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw);
}

Future<void> markOemSetupAcked(KvDao kv, {required DateTime now}) async {
  await kv.set(SurvivalKvKeys.oemSetupAck, IstDates.isoDate(now));
}

// ── Gap-alert flush (weekly job → kv → here) ─────────────────────────

/// The parked gap alert, if any (dashboard shows the card until the
/// user acts). Missing/corrupt → null — never a crash.
final FutureProvider<Map<String, Object?>?> gapAlertPendingProvider =
    FutureProvider<Map<String, Object?>?>((Ref ref) async {
  final Result<String?> r = await ref
      .watch(kvDaoProvider)
      .get(BackgroundJobs.kvGapAlertPending);
  final String? raw = r.valueOrNull;
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : null;
  } on Object {
    return null;
  }
});

/// SurvivalBridge's notification id whitelist mirror (ID_GAP_ALERT).
const int gapAlertNotificationId = 1003;

/// Posts the gap notification through the survival channel and
/// clears the kv row. User-initiated (foreground engine) — the
/// background job itself cannot reach the channel (ADR-0006).
/// Deps are explicit so unit tests can drive it with fakes.
Future<void> flushGapAlert({
  required SurvivalBridgeApi bridge,
  required KvDao kv,
  required void Function() onCleared,
}) async {
  try {
    await bridge.postNotification(
      id: gapAlertNotificationId,
      title: 'UDAO capture mein gap mila',
      body: 'Pichhle hafte kuch transactions miss ho gaye lagte '
          'hain — app khol kar details dekho.',
    );
  } on Object catch (e) {
    udaoLog.error('gap alert flush failed', error: e);
  } finally {
    try {
      await kv.delete(BackgroundJobs.kvGapAlertPending);
    } on Object catch (e) {
      udaoLog.error('gap alert clear failed', error: e);
    }
    onCleared();
  }
}
