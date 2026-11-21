// phase-05
// Survival-stack value models — mirrors of the Kotlin probe maps
// (contracts documented in SurvivalBridge.kt / PowerStateProbe.kt /
// ExitInfoProbe.kt / HealthPinger.kt). Parsing lives next to the
// models so widget tests can feed fixture maps directly.
import 'package:flutter/foundation.dart';

/// Device-truth snapshot (PowerStateProbe).
@immutable
class PowerState {
  const PowerState({
    required this.ignoringBatteryOptimizations,
    required this.powerSaverMode,
    required this.backgroundRestricted,
    required this.standbyBucket,
    required this.deviceIdle,
  });

  final bool ignoringBatteryOptimizations;

  /// Saver mode ON → OS ne background work tight kar diya.
  final bool powerSaverMode;

  /// null = API < 28 ya read nahi hua ("pata nahi", never a guess).
  final bool? backgroundRestricted;

  /// UsageStatsManager bucket; null = unknown. 5=exempted,
  /// 10=active, 20=working set, 30=frequent, 40=rare, 45=restricted.
  final int? standbyBucket;

  /// True only inside a doze idle window RIGHT NOW.
  final bool deviceIdle;

  static PowerState fromMap(Map<Object?, Object?> map) {
    return PowerState(
      ignoringBatteryOptimizations: map['ignoringBatteryOptimizations'] as bool? ?? false,
      powerSaverMode: map['powerSaverMode'] as bool? ?? false,
      backgroundRestricted: map['backgroundRestricted'] as bool?,
      standbyBucket: map['standbyBucket'] as int?,
      deviceIdle: map['deviceIdle'] as bool? ?? false,
    );
  }

  /// Honest Hinglish label for the bucket ("rare" tak system defers).
  String get standbyBucketLabel {
    final int? bucket = standbyBucket;
    if (bucket == null) return 'pata nahi';
    return switch (bucket) {
      5 => 'exempted',
      10 => 'active',
      20 => 'working set',
      30 => 'frequent',
      40 => 'rare',
      45 => 'restricted',
      _ => 'pata nahi',
    };
  }
}

/// One past process death (ExitInfoProbe, API 30+).
@immutable
class ExitInfo {
  const ExitInfo({
    required this.reasonCode,
    required this.reason,
    required this.label,
    required this.timestamp,
    required this.pid,
  });

  final int reasonCode;

  /// Stable slug ("crash", "anr", "low_memory", …).
  final String reason;

  /// Hinglish one-liner (assigned Kotlin-side, shown verbatim).
  final String label;

  final int timestamp;
  final int pid;

  static ExitInfo fromMap(Map<Object?, Object?> map) {
    return ExitInfo(
      reasonCode: map['reasonCode'] as int? ?? 0,
      reason: map['reason'] as String? ?? 'unknown',
      label: map['label'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? 0,
      pid: map['pid'] as int? ?? 0,
    );
  }
}

/// HealthPinger's last-run mirror (SharedPreferences on Kotlin side).
@immutable
class WatchdogSnapshot {
  const WatchdogSnapshot({
    required this.lastPingAt,
    required this.lastAction,
    required this.startedDown,
    required this.listenerOk,
    required this.lastEscalatedAt,
    required this.oemSuspect,
  });

  final int lastPingAt;

  /// WatchdogAction slug: none | rebind | toggle | escalated | suppressed.
  final String lastAction;

  final bool startedDown;
  final bool listenerOk;
  final int lastEscalatedAt;
  final bool oemSuspect;

  static WatchdogSnapshot fromMap(Map<Object?, Object?> map) {
    return WatchdogSnapshot(
      lastPingAt: map['lastPingAt'] as int? ?? 0,
      lastAction: map['lastAction'] as String? ?? 'none',
      startedDown: map['startedDown'] as bool? ?? false,
      listenerOk: map['listenerOk'] as bool? ?? false,
      lastEscalatedAt: map['lastEscalatedAt'] as int? ?? 0,
      oemSuspect: map['oemSuspect'] as bool? ?? false,
    );
  }

  static const WatchdogSnapshot empty = WatchdogSnapshot(
    lastPingAt: 0,
    lastAction: 'none',
    startedDown: false,
    listenerOk: false,
    lastEscalatedAt: 0,
    oemSuspect: false,
  );
}

/// KeepAliveService state mirror.
@immutable
class KeepAliveState {
  const KeepAliveState({
    required this.running,
    required this.lastBeatAt,
    required this.beats,
  });

  final bool running;
  final int lastBeatAt;
  final int beats;

  static KeepAliveState fromMap(Map<Object?, Object?> map) {
    return KeepAliveState(
      running: map['running'] as bool? ?? false,
      lastBeatAt: map['lastBeatAt'] as int? ?? 0,
      beats: map['beats'] as int? ?? 0,
    );
  }

  static const KeepAliveState stopped = KeepAliveState(
    running: false,
    lastBeatAt: 0,
    beats: 0,
  );
}

/// The dashboard's overall stamp (SHARP / DHYAN DO / BAND).
enum HealthVerdict { sharp, watch, dead }

extension HealthVerdictX on HealthVerdict {
  String get slug => switch (this) {
        HealthVerdict.sharp => 'sharp',
        HealthVerdict.watch => 'watch',
        HealthVerdict.dead => 'dead',
      };
}
