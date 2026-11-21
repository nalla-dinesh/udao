// phase-06
// The AiBridge wire contract, pinned from BOTH sides: every method
// the Dart engine calls must exist in AiBridge.kt with the exact
// spelling, the channels must match, and the cancel path must be
// `cancelGenerateResponseAsync` (not the absent `session.cancel()`).
// (static_verify §6p enforces the same in CI-style; this is the
// test-side pin, per the repo's phase-03 channel-test convention.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final File kt = File('android/app/src/main/kotlin/in/udao/app/ai/AiBridge.kt');
  final File dart =
      File('lib/features/ai/runtime/ai_engine.dart');

  late String ktSrc;
  late String dartSrc;

  setUpAll(() {
    ktSrc = kt.readAsStringSync();
    dartSrc = dart.readAsStringSync();
  });

  test('files exist (bridge + engine)', () {
    expect(kt.existsSync(), isTrue);
    expect(dart.existsSync(), isTrue);
  });

  test('channel names match on both sides', () {
    expect(dartSrc, contains("MethodChannel('udao/ai'"));
    expect(ktSrc, contains('"udao/ai"'));
    expect(dartSrc, contains("EventChannel('udao/ai/stream'"));
    expect(ktSrc, contains('"udao/ai/stream"'));
  });

  test('all 8 methods are invoked by Dart and handled by Kotlin', () {
    const List<String> methods = <String>[
      'loadModel',
      'unload',
      'isLoaded',
      'createSession',
      'closeSession',
      'generate',
      'generateVision',
      'cancelGenerate',
    ];
    for (final String m in methods) {
      expect(dartSrc, contains("'$m'"), reason: 'Dart must invoke $m');
      final bool kotlinHandlesIt =
          ktSrc.contains('"$m"') || ktSrc.contains("'$m'");
      expect(kotlinHandlesIt, isTrue, reason: 'Kotlin must handle $m');
    }
  });

  test('cancel uses cancelGenerateResponseAsync, never session.cancel()',
      () {
    expect(ktSrc, contains('cancelGenerateResponseAsync'));
    expect(ktSrc.contains('session.cancel()'), isFalse);
  });

  test('gradle pins the MediaPipe tasks-genai artifact', () {
    final String gradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('com.google.mediapipe:tasks-genai:0.10.35'));
  });

  test('MainActivity exposes totalRamMb for tiering', () {
    final String main = File(
      'android/app/src/main/kotlin/in/udao/app/MainActivity.kt',
    ).readAsStringSync();
    expect(main, contains('totalRamMb'));
    expect(main, contains('ActivityManager'));
  });

  test('model binaries never ride the repo', () {
    final String gitignore = File('.gitignore').readAsStringSync();
    expect(gitignore, contains('*.task'));
    expect(gitignore, contains('*.litertlm'));
    expect(gitignore, contains('*.gguf'));
    final List<FileSystemEntity> offenders = <FileSystemEntity>[
      ...Directory('lib').listSync(recursive: true),
      ...Directory('assets').listSync(recursive: true),
    ]
        .where(
          (FileSystemEntity f) =>
              f.path.endsWith('.task') ||
              f.path.endsWith('.litertlm') ||
              f.path.endsWith('.gguf'),
        )
        .toList();
    expect(offenders, isEmpty);
  });

  test('no discontinued AI plugin is imported anywhere', () {
    final List<File> dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();
    for (final File f in dartFiles) {
      final String src = f.readAsStringSync();
      expect(src, isNot(contains('flutter_gemma')));
      expect(src, isNot(contains('flutter_edge_ai')));
    }
  });
}
