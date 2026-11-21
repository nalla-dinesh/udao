// phase-06
// File-system seam for the model manager. Production talks to
// dart:io under <appDocuments>/models/; tests run an in-memory fake
// (no DB, no channels — the phase-04 widget-test survival law).
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// Where model files live, relative to app-documents.
abstract final class ModelPaths {
  static const String importedDir = 'models/imported';
  static const String bundledDir = 'models/pad';

  /// The file the (future) PAD pack `gemma3n_e2b` must deliver —
  /// also the adb-push target for development sideloads.
  static const String bundledFile = 'gemma-3n-e2b-it-int4.task';
}

abstract class ModelFileStore {
  Future<List<String>> listNames(String dir);
  Future<bool> exists(String path);
  Future<int> sizeOf(String path);
  Future<String> sha256Of(String path);

  /// Copies [sourcePath] (a picked / cached file) into [dir] as
  /// [fileName]. Returns the final absolute path.
  Future<String> copyIn({
    required String sourcePath,
    required String dir,
    required String fileName,
  });

  Future<void> delete(String path);
  Future<String> resolve(String dir, String fileName);
}

class IoModelFileStore implements ModelFileStore {
  IoModelFileStore({required this.documentsDir});

  final Future<String> Function() documentsDir;

  Future<String> _dirPath(String dir) async {
    final String base = await documentsDir();
    final Directory d = Directory('$base/$dir');
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return d.path;
  }

  @override
  Future<List<String>> listNames(String dir) async {
    final String path = await _dirPath(dir);
    return Directory(path)
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .toList(growable: false);
  }

  @override
  Future<bool> exists(String path) async => File(path).existsSync();

  @override
  Future<int> sizeOf(String path) async => File(path).lengthSync();

  @override
  Future<String> sha256Of(String path) async {
    // `Hash.bind` streams the file through the digest in 64 KiB
    // reads — a 3 GB model never loads into memory.
    final crypto.Digest digest =
        await crypto.sha256.bind(File(path).openRead()).first;
    return digest.toString();
  }

  @override
  Future<String> copyIn({
    required String sourcePath,
    required String dir,
    required String fileName,
  }) async {
    final String dirPath = await _dirPath(dir);
    final File target = File('$dirPath/$fileName');
    await File(sourcePath).copy(target.path);
    return target.path;
  }

  @override
  Future<void> delete(String path) async {
    final File file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  @override
  Future<String> resolve(String dir, String fileName) async =>
      '${await _dirPath(dir)}/$fileName';
}

/// Test double: a map of paths → bytes, no disk.
class MemoryModelFileStore implements ModelFileStore {
  final Map<String, List<int>> files = <String, List<int>>{};
  final Map<String, String> contentHashes = <String, String>{};
  int copyCalls = 0;

  @override
  Future<List<String>> listNames(String dir) async => files.keys
      .where((String p) => p.startsWith('$dir/'))
      .map((String p) => p.substring(dir.length + 1))
      .toList(growable: false);

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<int> sizeOf(String path) async => files[path]?.length ?? 0;

  @override
  Future<String> sha256Of(String path) async =>
      contentHashes[path] ??
      (files[path] == null ? '' : _fakeHash(files[path]!));

  static String _fakeHash(List<int> bytes) {
    // Deterministic stand-in: real SHA only lives in IoModelFileStore.
    int acc = 0;
    for (final int b in bytes) {
      acc = (acc * 31 + b) & 0x7fffffff;
    }
    return acc.toRadixString(16).padLeft(8, '0') * 8;
  }

  @override
  Future<String> copyIn({
    required String sourcePath,
    required String dir,
    required String fileName,
  }) async {
    copyCalls++;
    final List<int>? bytes = files[sourcePath];
    if (bytes == null) {
      throw FileSystemException('source missing', sourcePath);
    }
    final String target = '$dir/$fileName';
    files[target] = List<int>.of(bytes);
    return target;
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }

  @override
  Future<String> resolve(String dir, String fileName) async => '$dir/$fileName';
}
