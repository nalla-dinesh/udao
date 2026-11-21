// phase-06
// Model lifecycle: discovery (PAD staging → imported → absent),
// validation (extension, size, SHA-256 re-verify on load), RAM
// tiering, load/unload, 5-min idle unload + memory-pressure unload
// (both respect the explicit preload toggle), and a [ChangeNotifier]
// status the AI settings screen renders.
//
// A model load is a heavyweight, user-visible act (2 GB file, RAM
// tier warnings) — it is NEVER done silently in the background.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';
import '../../../data/db/dao/kv_dao.dart';
import '../runtime/ai_engine.dart';
import 'model_file_store.dart';
import 'model_source.dart';
import 'model_tier.dart';

enum ModelPhase { absent, ready, loading, loaded, error }

class ModelManagerState {
  const ModelManagerState({
    required this.phase,
    this.candidate,
    this.message,
  });

  final ModelPhase phase;
  final ModelCandidate? candidate;
  final String? message;

  static const ModelManagerState absent = ModelManagerState(phase: ModelPhase.absent);
}

class ModelManager extends ChangeNotifier {
  ModelManager({
    required ModelFileStore store,
    required KvDao kv,
    required AiInferenceEngine engine,
    required Future<int> Function() totalRamMb,
    this.idleTimeout = const Duration(minutes: 5),
  })  : _store = store,
        _kv = kv,
        _engine = engine,
        _ramReader = totalRamMb;

  final ModelFileStore _store;
  final KvDao _kv;
  final AiInferenceEngine _engine;
  final Future<int> Function() _ramReader;

  /// Idle unload delay (config — tests run it at 0 / tiny values).
  final Duration idleTimeout;

  static const String kvImported = 'ai.model.imported';
  static const String kvPreload = 'ai.settings.preload';
  static const String kvLastUsed = 'ai.model.lastUsedMs';

  static const int minModelBytes = 50 * 1024 * 1024;
  static const int maxModelBytes = 5 * 1024 * 1024 * 1024;

  ModelManagerState _state = ModelManagerState.absent;
  Timer? _idleTimer;
  int? _cachedRamMb;

  ModelManagerState get state => _state;
  bool get isLoaded => _state.phase == ModelPhase.loaded;

  void _setState(ModelManagerState next) {
    _state = next;
    notifyListeners();
  }

  // ── discovery ───────────────────────────────────────────────────

  /// Discovery order: PAD staging dir, then imported dir, then the
  /// persisted registry (covers a deleted-but-registered file
  /// honestly — load then fails the SHA re-check), then absent.
  Future<ModelCandidate?> discover() async {
    // 1. PAD staging (docs/ai/asset-delivery.md).
    final String bundledPath =
        await _store.resolve(ModelPaths.bundledDir, ModelPaths.bundledFile);
    if (await _store.exists(bundledPath)) {
      final ModelCandidate candidate = await _describe(
        source: const BundledAsset(
          packName: 'gemma3n_e2b',
          fileName: ModelPaths.bundledFile,
        ),
        path: bundledPath,
      );
      _setState(
        ModelManagerState(
          phase: ModelPhase.ready,
          candidate: candidate,
        ),
      );
      return candidate;
    }
    // 2. Imported dir.
    final List<String> imported =
        await _store.listNames(ModelPaths.importedDir);
    if (imported.isNotEmpty) {
      final String name = imported.first;
      final String path =
          await _store.resolve(ModelPaths.importedDir, name);
      final ModelCandidate candidate = await _describe(
        source: ImportedFile(path: path),
        path: path,
      );
      _setState(
        ModelManagerState(
          phase: ModelPhase.ready,
          candidate: candidate,
        ),
      );
      return candidate;
    }
    // 3. Registry (file gone → honest absent + stale-registry note).
    final Result<String?> stored = await _kv.get(kvImported);
    final String? json = stored.valueOrNull;
    final String? registeredName = _registeredName(json);
    if (registeredName != null && registeredName.isNotEmpty) {
      final String path =
          await _store.resolve(ModelPaths.importedDir, registeredName);
      if (await _store.exists(path)) {
        final ModelCandidate candidate = await _describe(
          source: ImportedFile(path: path),
          path: path,
        );
        _setState(
          ModelManagerState(
            phase: ModelPhase.ready,
            candidate: candidate,
          ),
        );
        return candidate;
      }
    }
    _setState(ModelManagerState.absent);
    return null;
  }

  /// Registry format: `{"name":"x.task","sha256":"..."}`. A legacy
  /// bare `"x.task"` string (pre-JSON builds) resolves with no sha —
  /// load() then simply skips integrity verification.
  static String? _registeredName(String? json) {
    if (json == null || json.isEmpty) {
      return null;
    }
    if (json.startsWith('{')) {
      try {
        final Map<String, Object?> decoded =
            jsonDecode(json) as Map<String, Object?>;
        return decoded['name'] as String?;
      } on FormatException {
        return null;
      }
    }
    return json;
  }

  static String? _registeredSha(String? json) {
    if (json == null || !json.startsWith('{')) {
      return null;
    }
    try {
      final Map<String, Object?> decoded =
          jsonDecode(json) as Map<String, Object?>;
      return decoded['sha256'] as String?;
    } on FormatException {
      return null;
    }
  }

  Future<ModelCandidate> _describe({
    required ModelSource source,
    required String path,
  }) async {
    final int size = await _store.sizeOf(path);
    final String hash = await _store.sha256Of(path);
    return ModelCandidate(
      source: source,
      fileName: path.split('/').last,
      sizeBytes: size,
      sha256: hash,
      importedAtMs: 0,
    );
  }

  // ── import / delete ─────────────────────────────────────────────

  /// SAF-import a picked file: validate → copy → hash → register.
  Future<Result<ModelCandidate>> importFromFile(String sourcePath) async {
    final String fileName = sourcePath.split('/').last;
    if (!fileName.toLowerCase().endsWith('.task')) {
      return const Err<ModelCandidate>(
        ModelFailure('ai-import-not-a-task'),
      );
    }
    if (!await _store.exists(sourcePath)) {
      return const Err<ModelCandidate>(
        ModelFailure('ai-import-missing'),
      );
    }
    final int size = await _store.sizeOf(sourcePath);
    if (size < minModelBytes || size > maxModelBytes) {
      return const Err<ModelCandidate>(
        ModelFailure('ai-import-size'),
      );
    }
    final String target;
    try {
      target = await _store.copyIn(
        sourcePath: sourcePath,
        dir: ModelPaths.importedDir,
        fileName: fileName,
      );
    } on Object catch (e) {
      return Err<ModelCandidate>(ModelFailure('ai-import-copy', cause: e));
    }
    final String hash = await _store.sha256Of(target);
    final ModelCandidate candidate = ModelCandidate(
      source: ImportedFile(path: target),
      fileName: fileName,
      sizeBytes: size,
      sha256: hash,
      importedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final Result<void> saved = await _kv.set(
      kvImported,
      jsonEncode(<String, Object?>{'name': fileName, 'sha256': hash}),
    );
    if (saved.isErr) {
      return Err<ModelCandidate>(saved.failureOrNull!);
    }
    _setState(
      ModelManagerState(
        phase: ModelPhase.ready,
        candidate: candidate,
      ),
    );
    return Ok<ModelCandidate>(candidate);
  }

  /// Deletes the model file + registry row; unloads first.
  Future<Result<bool>> deleteModel() async {
    await unload();
    final ModelCandidate? candidate = _state.candidate;
    if (candidate == null) {
      return const Ok<bool>(true);
    }
    if (candidate.source is ImportedFile) {
      await _store.delete((candidate.source as ImportedFile).path);
    }
    await _kv.delete(kvImported);
    _setState(ModelManagerState.absent);
    return const Ok<bool>(true);
  }

  // ── load / unload ───────────────────────────────────────────────

  Future<Result<bool>> load() async {
    final ModelCandidate? candidate = await discover();
    if (candidate == null) {
      return const Err<bool>(ModelFailure('model-absent'));
    }
    _setState(
      ModelManagerState(
        phase: ModelPhase.loading,
        candidate: candidate,
      ),
    );
    // Integrity: re-verify the SHA REGISTERED AT IMPORT TIME against
    // the file's CURRENT hash (a corrupted re-download must fail
    // closed, never crash the inference engine). Comparing a freshly
    // described hash against itself always matched — the registry is
    // the only honest witness.
    if (candidate.source is ImportedFile) {
      final String? registeredSha = _registeredSha(
        (await _kv.get(kvImported)).valueOrNull,
      );
      if (registeredSha != null && registeredSha.isNotEmpty) {
        final String actual = await _store.sha256Of(
          (candidate.source as ImportedFile).path,
        );
        if (registeredSha != actual) {
          _setState(
            const ModelManagerState(
              phase: ModelPhase.error,
              message: 'ai-sha-mismatch',
            ),
          );
          return const Err<bool>(ModelFailure('ai-sha-mismatch'));
        }
      }
    }
    final String path = switch (candidate.source) {
      ImportedFile(:final String path) => path,
      BundledAsset() => await _store.resolve(
          ModelPaths.bundledDir,
          candidate.fileName,
        ),
      Absent() => '',
    };
    final bool wantsVision =
        ModelTiers.tierForFileName(candidate.fileName) != ModelTier.small;
    final Result<bool> loaded = await _engine.loadModel(
      path: path,
      maxTokens: 1024,
      maxImages: wantsVision ? 1 : 0,
    );
    if (loaded.isErr) {
      _setState(ModelManagerState(
          phase: ModelPhase.error,
          candidate: candidate,
          message: loaded.failureOrNull?.message,
        ),
      );
      return Err<bool>(loaded.failureOrNull!);
    }
    await _kv.set(
      kvLastUsed,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
    _setState(
      ModelManagerState(
        phase: ModelPhase.loaded,
        candidate: candidate,
      ),
    );
    _armIdleTimer();
    return const Ok<bool>(true);
  }

  Future<void> unload() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_state.phase == ModelPhase.loaded) {
      await _engine.unload();
    }
    if (_state.candidate != null) {
      _setState(
        ModelManagerState(
          phase: ModelPhase.ready,
          candidate: _state.candidate,
        ),
      );
    } else {
      _setState(ModelManagerState.absent);
    }
  }

  /// Any inference activity pushes the idle timer back.
  void touch() {
    if (isLoaded) {
      _armIdleTimer();
    }
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (idleTimeout == Duration.zero) {
      return;
    }
    // The preload preference is consulted when the timer FIRES, so
    // flipping it mid-idle-window needs no timer surgery.
    _idleTimer = Timer(idleTimeout, () => unawaited(_idleUnload()));
  }

  Future<void> _idleUnload() async {
    if (isLoaded && !await preloadEnabled()) {
      await unload();
    }
  }

  Future<bool> preloadEnabled() async {
    final Result<String?> v = await _kv.get(kvPreload);
    return v.valueOrNull == '1';
  }

  Future<void> setPreload(bool enabled) async {
    await _kv.set(kvPreload, enabled ? '1' : '0');
    if (enabled) {
      _idleTimer?.cancel();
    } else if (isLoaded) {
      _armIdleTimer();
    }
  }

  /// OS memory pressure — unload unless the user pinned preload.
  Future<void> onAppMemoryPressure() async {
    if (isLoaded && !await preloadEnabled()) {
      await unload();
    }
  }

  // ── tiering ─────────────────────────────────────────────────────

  Future<int> deviceRamMb() async {
    return _cachedRamMb ??= await _ramReader();
  }

  Future<ModelTier> suggestedTier() async {
    final int ram = await deviceRamMb();
    return ModelTiers.suggested(totalRamMb: ram);
  }

  /// Honest "this file exceeds what the device suggests" signal.
  Future<bool> candidateFitsDevice() async {
    final ModelCandidate? candidate = _state.candidate;
    if (candidate == null) {
      return true;
    }
    final int ram = await deviceRamMb();
    return ModelTiers.fits(
      ModelTiers.tierForFileName(candidate.fileName),
      ram,
    );
  }
}
