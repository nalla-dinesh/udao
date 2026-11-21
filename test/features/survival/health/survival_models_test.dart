// phase-05
// Model-mapping tests: the Kotlin probe maps → Dart models. Missing
// keys must degrade to honest "unknown" values — never to a healthy
// guess.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/survival/health/survival_models.dart';

void main() {
  group('PowerState.fromMap', () {
    test('full map parses', () {
      final PowerState p = PowerState.fromMap(<Object?, Object?>{
        'ignoringBatteryOptimizations': true,
        'powerSaverMode': false,
        'backgroundRestricted': false,
        'standbyBucket': 30,
        'deviceIdle': false,
      });
      expect(p.ignoringBatteryOptimizations, isTrue);
      expect(p.powerSaverMode, isFalse);
      expect(p.backgroundRestricted, isFalse);
      expect(p.standbyBucket, 30);
      expect(p.deviceIdle, isFalse);
    });

    test('empty map fails safe (booleans false, probes null)', () {
      final PowerState p = PowerState.fromMap(<Object?, Object?>{});
      expect(p.ignoringBatteryOptimizations, isFalse);
      expect(p.powerSaverMode, isFalse);
      expect(p.backgroundRestricted, isNull);
      expect(p.standbyBucket, isNull);
      expect(p.deviceIdle, isFalse);
    });

    test('standby bucket labels (UsageStatsManager values)', () {
      PowerState bucket(int? v) => PowerState.fromMap(<Object?, Object?>{
            'standbyBucket': v,
          });
      expect(bucket(5).standbyBucketLabel, 'exempted');
      expect(bucket(10).standbyBucketLabel, 'active');
      expect(bucket(20).standbyBucketLabel, 'working set');
      expect(bucket(30).standbyBucketLabel, 'frequent');
      expect(bucket(40).standbyBucketLabel, 'rare');
      expect(bucket(45).standbyBucketLabel, 'restricted');
      expect(bucket(null).standbyBucketLabel, 'pata nahi');
      expect(bucket(99).standbyBucketLabel, 'pata nahi');
    });
  });

  group('ExitInfo.fromMap', () {
    test('parses the probe fields', () {
      final ExitInfo e = ExitInfo.fromMap(<Object?, Object?>{
        'reasonCode': 4,
        'reason': 'crash',
        'label': 'App crash hua tha',
        'timestamp': 12345678,
        'pid': 4321,
      });
      expect(e.reason, 'crash');
      expect(e.label, 'App crash hua tha');
      expect(e.timestamp, 12345678);
      expect(e.pid, 4321);
    });

    test('empty map degrades without crashing', () {
      final ExitInfo e = ExitInfo.fromMap(<Object?, Object?>{});
      expect(e.reason, 'unknown');
      expect(e.timestamp, 0);
    });
  });

  group('WatchdogSnapshot.fromMap', () {
    test('parses pinger prefs mirror', () {
      final WatchdogSnapshot w = WatchdogSnapshot.fromMap(<Object?, Object?>{
        'lastPingAt': 999,
        'lastAction': 'toggle',
        'startedDown': true,
        'listenerOk': true,
        'lastEscalatedAt': 555,
        'oemSuspect': true,
      });
      expect(w.lastAction, 'toggle');
      expect(w.startedDown, isTrue);
      expect(w.listenerOk, isTrue);
      expect(w.oemSuspect, isTrue);
    });

    test('empty snapshot defaults to the honest first-run state', () {
      expect(WatchdogSnapshot.empty.lastAction, 'none');
      expect(WatchdogSnapshot.empty.lastPingAt, 0);
      expect(WatchdogSnapshot.empty.oemSuspect, isFalse);
    });
  });

  group('KeepAliveState.fromMap', () {
    test('parses service state mirror', () {
      final KeepAliveState k = KeepAliveState.fromMap(<Object?, Object?>{
        'running': true,
        'lastBeatAt': 777,
        'beats': 12,
      });
      expect(k.running, isTrue);
      expect(k.beats, 12);
    });

    test('stopped default', () {
      expect(KeepAliveState.stopped.running, isFalse);
      expect(KeepAliveState.stopped.beats, 0);
    });
  });
}
