// phase-05
// The NATIVE ⇄ DART survival contract, enforced as text (same style
// as the phase-03 bridge contract test): the Kotlin sources, the
// manifests, and the Dart constants must agree on channel names,
// method names, pref keys, notification ids, cadences and bans.
// A rename on one side that misses the other fails here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _ktSurvival =
    'android/app/src/main/kotlin/in/udao/app/survival';
const String _ktCapture =
    'android/app/src/main/kotlin/in/udao/app/capture';

String _kt(String dir, String name) => File('$dir/$name.kt').readAsStringSync();

void main() {
  late final String survivalBridge;
  late final String keepAlive;
  late final String gateway;
  late final String pinger;
  late final String mainManifest;
  late final String playManifest;
  late final String powerManifest;
  late final String dartProbeBridge;
  late final String dartProviders;
  late final String dartJobs;
  late final String mainDart;
  late final String pubspec;

  setUpAll(() {
    survivalBridge = _kt(_ktSurvival, 'SurvivalBridge');
    keepAlive = _kt(_ktSurvival, 'KeepAliveService');
    gateway = _kt(_ktSurvival, 'NotificationGateway');
    pinger = _kt(_ktCapture, 'HealthPinger');
    mainManifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    playManifest =
        File('android/app/src/play/AndroidManifest.xml').readAsStringSync();
    powerManifest =
        File('android/app/src/power/AndroidManifest.xml').readAsStringSync();
    dartProbeBridge = File(
      'lib/features/survival/health/probe_bridge.dart',
    ).readAsStringSync();
    dartProviders = File(
      'lib/features/survival/survival_providers.dart',
    ).readAsStringSync();
    dartJobs = File(
      'lib/features/survival/jobs/background_jobs.dart',
    ).readAsStringSync();
    mainDart = File('lib/main.dart').readAsStringSync();
    pubspec = File('pubspec.yaml').readAsStringSync();
  });

  group('udao/survival channel parity', () {
    test('channel name matches on both sides', () {
      expect(survivalBridge, contains('"udao/survival"'));
      expect(dartProbeBridge, contains("MethodChannel('udao/survival')"));
    });

    test('all eleven methods match Kotlin exactly', () {
      const List<String> methods = <String>[
        'getPowerState',
        'getExitInfos',
        'getWatchdogSnapshot',
        'getKeepAliveState',
        'startKeepAlive',
        'stopKeepAlive',
        'postNotification',
        'openBatteryOptimizationSettings',
        'requestIgnoreBatteryOptimizations',
        'openAppDetails',
        'openOemScreen',
      ];
      for (final String m in methods) {
        expect(
          survivalBridge,
          contains('"$m"'),
          reason: 'Kotlin SurvivalBridge must handle "$m"',
        );
        expect(
          dartProbeBridge,
          contains("'$m'"),
          reason: 'Dart probe bridge must call "$m"',
        );
      }
      expect(methods, hasLength(11));
    });

    test('postNotification id whitelist = escalation + gap only', () {
      expect(
        survivalBridge,
        contains('id == NotificationGateway.ID_ESCALATION'),
      );
      expect(
        survivalBridge,
        contains('id == NotificationGateway.ID_GAP_ALERT'),
      );
    });

    test('gap notification id parity (Kotlin 1003 == Dart 1003)', () {
      expect(gateway, contains('ID_GAP_ALERT = 1003'));
      expect(dartProviders, contains('gapAlertNotificationId = 1003'));
    });
  });

  group('watchdog (HealthPinger) spec', () {
    test('cadence constants: 30 min repeat, 5s latch, 24h cooldown', () {
      expect(pinger, contains('REPEAT_MINUTES = 30L'));
      expect(pinger, contains('REBIND_LATCH_MS = 5_000L'));
      expect(
        pinger,
        contains('ESCALATION_COOLDOWN_MS = 24L * 60L * 60L * 1000L'),
      );
    });

    test('recovery ladder order: rebind → toggle → escalate', () {
      final int rebindAt = pinger.indexOf('action = WatchdogAction.REBIND');
      final int toggleAt = pinger.indexOf('action = WatchdogAction.TOGGLE');
      final int escalateAt = pinger.indexOf('maybeEscalate(ctx)');
      expect(rebindAt, greaterThan(-1));
      expect(toggleAt, greaterThan(rebindAt));
      expect(escalateAt, greaterThan(toggleAt));
    });

    test('every run writes the snapshot + WAL sweep', () {
      expect(pinger, contains('writeSnapshot'));
      expect(pinger, contains('WalWriter.sweep'));
    });

    test('snapshot pref keys: pinger writes, bridge mirrors, Dart parses',
        () {
      // Kotlin: HealthPinger persists the watchdog_* keys…
      const List<String> prefKeys = <String>[
        'watchdog_lastPingAt',
        'watchdog_lastAction',
        'watchdog_startedDown',
        'watchdog_lastEscalatedAt',
        'watchdog_oemSuspect',
        'watchdog_listenerOk',
      ];
      for (final String k in prefKeys) {
        expect(pinger, contains('"$k"'), reason: 'pinger writes "$k"');
      }
      // …and SurvivalBridge re-exposes them UNPREFIXED, which is what
      // the Dart WatchdogSnapshot.fromMap parses.
      const List<String> mirrorKeys = <String>[
        'lastPingAt',
        'lastAction',
        'startedDown',
        'listenerOk',
        'lastEscalatedAt',
        'oemSuspect',
      ];
      for (final String k in mirrorKeys) {
        expect(
          survivalBridge,
          contains('"$k"'),
          reason: 'bridge mirrors "$k" for Dart',
        );
      }
      expect(
        File('lib/features/survival/health/survival_models.dart')
            .readAsStringSync(),
        contains("lastAction: map['lastAction']"),
      );
    });

    test('periodic chain: KEEP + exponential backoff', () {
      expect(pinger, contains('ExistingPeriodicWorkPolicy.KEEP'));
      expect(pinger, contains('BackoffPolicy.EXPONENTIAL'));
      expect(pinger, contains('PeriodicWorkRequestBuilder<HealthPinger>'));
    });
  });

  group('keep-alive service rules', () {
    test('specialUse FGS type + 15 min heartbeat', () {
      expect(keepAlive, contains('FOREGROUND_SERVICE_TYPE_SPECIAL_USE'));
      expect(keepAlive, contains('HEARTBEAT_MS = 15L * 60L * 1000L'));
    });

    test('STOP action exists (low-priority notice is escapable)', () {
      expect(keepAlive, contains('ACTION_STOP'));
      expect(gateway, contains('addAction(0, "Band karo", stopIntent)'));
    });

    test('onTaskRemoved NEVER stopSelfs (survives the swipe)', () {
      final int at = keepAlive.indexOf('override fun onTaskRemoved');
      expect(at, greaterThan(-1));
      final String block = keepAlive.substring(at, keepAlive.indexOf('}', at));
      expect(
        block.contains('stopSelf'),
        isFalse,
        reason: 'onTaskRemoved must not stop the service',
      );
      expect(block.contains('deliberately empty'), isTrue);
    });

    test('onTimeout honored gracefully', () {
      expect(keepAlive, contains('override fun onTimeout(startId: Int'));
    });
  });

  group('battery optimization flavor split', () {
    test('power flavor declares the direct-dialog permission', () {
      expect(
        powerManifest,
        contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS'),
      );
    });

    test('play flavor and main manifest NEVER declare it', () {
      const String perm = 'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS';
      expect(playManifest.contains(perm), isFalse);
      expect(mainManifest.contains(perm), isFalse);
    });

    test('Kotlin double-guards the direct ask by flavor', () {
      expect(
        survivalBridge,
        contains('BuildConfig.FLAVOR != "power"'),
      );
    });
  });

  group('manifest + boot rules', () {
    test('KeepAliveService declared specialUse with the subtype property',
        () {
      expect(mainManifest, contains('in.udao.app.survival.KeepAliveService'));
      expect(mainManifest, contains('android:foregroundServiceType="specialUse"'));
      expect(
        mainManifest,
        contains('android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE'),
      );
      expect(mainManifest, contains('android:stopWithTask="false"'));
    });

    test('FOREGROUND_SERVICE_SPECIAL_USE permission present', () {
      expect(
        mainManifest,
        contains('android.permission.FOREGROUND_SERVICE_SPECIAL_USE'),
      );
    });

    test('bans: no dataSync FGS, no FGS-from-boot, no wake locks, no setExact',
        () {
      expect(mainManifest.contains('dataSync'), isFalse);
      final String boot = _kt(_ktCapture, 'BootReceiver');
      // BootReceiver rebinds + schedules the pinger; it must NOT
      // start any foreground service.
      expect(boot, contains('requestRebind'));
      expect(boot, contains('schedulePeriodic'));
      expect(boot.contains('startForegroundService'), isFalse);
      expect(boot.contains('startService'), isFalse);
      expect(mainManifest.contains('WAKE_LOCK'), isTrue); // declared, unused by jobs
      for (final String dir in <String>[_ktSurvival, _ktCapture]) {
        for (final FileSystemEntity f in Directory(dir).listSync()) {
          final String src = File(f.path).readAsStringSync();
          expect(
            src.contains('setExact'),
            isFalse,
            reason: '${f.path} must not use setExact alarms',
          );
          expect(
            src.contains('WakeLock'),
            isFalse,
            reason: '${f.path} must not acquire wake locks',
          );
        }
      }
    });
  });

  group('device info extension (udao/platform)', () {
    test('new identity fields exposed', () {
      final String mainActivitySrc = File(
        'android/app/src/main/kotlin/in/udao/app/MainActivity.kt',
      ).readAsStringSync();
      expect(mainActivitySrc, contains('"model" to Build.MODEL'));
      expect(
        mainActivitySrc,
        contains('"versionRelease" to Build.VERSION.RELEASE'),
      );
      expect(mainActivitySrc, contains('"isEmulator" to isEmulator()'));
    });

    test('MainActivity registers the survival bridge + periodic watchdog',
        () {
      final String mainActivitySrc = File(
        'android/app/src/main/kotlin/in/udao/app/MainActivity.kt',
      ).readAsStringSync();
      expect(mainActivitySrc, contains('SurvivalBridge.attach'));
      expect(mainActivitySrc, contains('HealthPinger.schedulePeriodic'));
    });
  });

  group('workmanager wiring', () {
    test('dependency pinned exactly', () {
      expect(pubspec, contains('workmanager: 0.10.10'));
    });

    test('main.dart initializes the dispatcher after warm-up', () {
      expect(mainDart, contains('initializeBackgroundJobs'));
    });

    test('dart jobs keep KEEP + battery-not-low + backoff', () {
      expect(dartJobs, contains('ExistingPeriodicWorkPolicy.keep'));
      expect(dartJobs, contains('requiresBatteryNotLow: true'));
      expect(dartJobs, contains('BackoffPolicy.exponential'));
      expect(dartJobs, contains('@pragma(\'vm:entry-point\')'));
    });

    test('nightly target inside the 01:00–04:00 IST window', () {
      expect(dartJobs, contains('DateTime.utc(nowIst.year, nowIst.month, nowIst.day, 1, 30)'));
      expect(dartJobs, contains('Duration(hours: 24)'));
    });
  });
}
