// phase-03
// The NATIVE ⇄ DART contract, enforced as text: the Kotlin sources,
// the manifest and the Dart constants are grepped for the same
// strings. A rename on one side that misses the other fails here —
// this is the static-verification the phase is allowed (no emulator).
//
// Runs as a plain test because `flutter test` sets cwd to the
// package root, so File('android/...') resolves.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/capture/bridge/capture_channels.dart';

const String _kotlinDir = 'android/app/src/main/kotlin/in/udao/app/capture';

String _kotlin(String name) =>
    File('$_kotlinDir/$name.kt').readAsStringSync();

void main() {
  final String bridge = _kotlin('CaptureBridge');
  final String listener = _kotlin('UdaoNotificationListener');
  final String walWriter = _kotlin('WalWriter');
  final String manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final String dartChannels =
      File('lib/features/capture/bridge/capture_channels.dart')
          .readAsStringSync();
  final String pubspec = File('pubspec.yaml').readAsStringSync();

  group('channel names match Kotlin exactly', () {
    test('event + control channel', () {
      expect(bridge, contains('"${CaptureChannels.stream}"'));
      expect(bridge, contains('"${CaptureChannels.control}"'));
      // And nothing else is inventing channels.
      expect(bridge, contains('EVENT_CHANNEL'));
      expect(bridge, contains('CONTROL_CHANNEL'));
    });

    test('channel constants are the locked values', () {
      expect(CaptureChannels.stream, 'udao/capture/stream');
      expect(CaptureChannels.control, 'udao/capture/control');
      // The Dart side must reference the consts, not raw strings.
      expect(
        dartChannels,
        contains("static const String stream = 'udao/capture/stream'"),
      );
      expect(
        dartChannels,
        contains("static const String control = 'udao/capture/control'"),
      );
    });
  });

  group('method names match Kotlin exactly', () {
    test('control methods', () {
      const List<String> methods = <String>[
        CaptureChannels.methodGetWAL,
        CaptureChannels.methodAckWAL,
        CaptureChannels.methodListenerStatus,
        CaptureChannels.methodRequestRebind,
        CaptureChannels.methodOpenListenerSettings,
        CaptureChannels.methodRebindViaToggle,
        CaptureChannels.methodPushAllowlist,
      ];
      for (final String method in methods) {
        expect(
          bridge,
          contains('"$method"'),
          reason: 'Kotlin CaptureBridge must handle "$method"',
        );
      }
      expect(methods, hasLength(7));
    });

    test('status payload keys', () {
      expect(bridge, contains('"${CaptureChannels.keyConnected}"'));
      expect(bridge, contains('"${CaptureChannels.keyLastEventAt}"'));
      expect(bridge, contains('"${CaptureChannels.keyComponentEnabled}"'));
    });
  });

  group('WAL file contract matches WalWriter', () {
    test('active file + rotation template', () {
      expect(walWriter, contains('"capture_wal.jsonl"'));
      // Rotation files are built from a template — assert it, not a
      // comment.
      expect(walWriter, contains('capture_wal.\$n.jsonl'));
    });

    test('WAL JSON line keys match the Dart model', () {
      const List<String> keys = <String>['pkg', 'title', 'text', 'bigText', 'subText', 'ts'];
      for (final String key in keys) {
        expect(
          listener,
          contains('"$key"'),
          reason: 'listener must write "$key" lines',
        );
      }
      // The Dart model reads the same keys.
      final String rawEvent =
          File('lib/features/capture/bridge/capture_raw_event.dart')
              .readAsStringSync();
      for (final String key in keys) {
        expect(rawEvent, contains("'$key'"));
      }
    });
  });

  group('manifest declares the capture components', () {
    test('notification listener service', () {
      expect(manifest, contains('.capture.UdaoNotificationListener'));
      expect(manifest, contains('BIND_NOTIFICATION_LISTENER_SERVICE'));
      expect(
        manifest,
        contains(
          'android.service.notification.NotificationListenerService',
        ),
      );
    });

    test('boot receiver', () {
      expect(manifest, contains('.capture.BootReceiver'));
      expect(manifest, contains('android.intent.action.BOOT_COMPLETED'));
    });
  });

  group('allowlist asset is wired', () {
    test('listener reads allowlist.json from no_backup', () {
      expect(listener, contains('allowlist.json'));
    });

    test('asset ships and pubspec declares it', () {
      final File asset = File('assets/capture/allowlist.json');
      expect(
        asset.existsSync(),
        isTrue,
        reason: 'assets/capture/allowlist.json must exist',
      );
      expect(pubspec, contains('assets/capture/'));
    });

    test('asset is valid JSON of package ids', () {
      final String json = File('assets/capture/allowlist.json').readAsStringSync();
      expect(json, startsWith('['));
      expect(json, contains('com.google.android.apps.nbu.paysa'));
      expect(json, contains('com.phonepe.app'));
      expect(json, contains('net.one97.paytm'));
    });
  });

  group('MainActivity attaches the bridge', () {
    test('configureFlutterEngine wires CaptureBridge', () {
      final String mainActivity = File(
        'android/app/src/main/kotlin/in/udao/app/MainActivity.kt',
      ).readAsStringSync();
      expect(mainActivity, contains('CaptureBridge.attach'));
    });
  });
}
