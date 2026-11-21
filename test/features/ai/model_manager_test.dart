// phase-06
// ModelManager: discovery order, import validation (ext/size),
// load/SHA-fail-closed/unload, preload preference, idle unload,
// tiering (RAM bands + file-name tiers + fits).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/features/ai/model/model_file_store.dart';
import 'package:udao/features/ai/model/model_manager.dart';
import 'package:udao/features/ai/model/model_source.dart';
import 'package:udao/features/ai/model/model_tier.dart';

import '../../data/db/test_db.dart' as helper;
import 'fake_ai_engine.dart';

void main() {
  late UdaoDatabase db;
  late KvDao kv;
  late MemoryModelFileStore store;
  late FakeAiInferenceEngine engine;

  setUp(() async {
    db = await helper.createTestDb();
    kv = KvDao(db.db);
    store = MemoryModelFileStore();
    engine = FakeAiInferenceEngine();
  });
  tearDown(() async {
    engine.dispose();
    await helper.disposeTestDb(db);
  });

  ModelManager manager({
    int ramMb = 8 * 1024,
    Duration idle = const Duration(minutes: 5),
  }) =>
      ModelManager(
        store: store,
        kv: kv,
        engine: engine,
        totalRamMb: () async => ramMb,
        idleTimeout: idle,
      );

  String stageModel(String name, int mb, {String dir = 'picked'}) {
    final List<int> bytes = List<int>.generate(
      mb * 1024 * 1024,
      (int i) => i % 251,
    );
    final String src = '$dir/$name';
    store.files[src] = bytes;
    return src;
  }

  test('discovery: nothing → absent', () async {
    final ModelManager m = manager();
    expect(await m.discover(), isNull);
    expect(m.state.phase, ModelPhase.absent);
  });

  test('discovery: PAD staging wins over imported dir', () async {
    final List<int> bytes = List<int>.generate(
      60 * 1024 * 1024,
      (int i) => i % 251,
    );
    store.files['${ModelPaths.bundledDir}/${ModelPaths.bundledFile}'] =
        bytes;
    stageModel('user-model.task', 60);
    final ModelManager m = manager();
    final ModelCandidate? c = await m.discover();
    expect(c, isNotNull);
    expect(c!.fileName, ModelPaths.bundledFile);
    expect(m.state.phase, ModelPhase.ready);
  });

  test('discovery: imported dir when no PAD staging', () async {
    stageModel(
      'gemma-3n-e2b-it-int4.task',
      60,
      dir: ModelPaths.importedDir,
    );
    final ModelManager m = manager();
    final ModelCandidate? c = await m.discover();
    expect(c!.fileName, 'gemma-3n-e2b-it-int4.task');
    expect(c.sha256, hasLength(64));
    expect(m.state.phase, ModelPhase.ready);
  });

  test('import: happy path copies, hashes, registers', () async {
    final String src = stageModel('my-model.task', 60);
    final ModelManager m = manager();
    final Result<ModelCandidate> r = await m.importFromFile(src);
    expect(r.isErr, isFalse, reason: '${r.failureOrNull}');
    final ModelCandidate c = r.valueOrNull!;
    expect(c.fileName, 'my-model.task');
    expect(c.sizeBytes, 60 * 1024 * 1024);
    final String? registered =
        (await kv.get(ModelManager.kvImported)).valueOrNull;
    expect(registered, isNotNull);
    final Map<String, Object?> regJson =
        jsonDecode(registered!) as Map<String, Object?>;
    expect(regJson['name'], 'my-model.task');
    expect(regJson['sha256'], hasLength(64));
    expect(regJson['sha256'], c.sha256);
    expect(store.copyCalls, 1);
    expect(m.state.phase, ModelPhase.ready);
  });

  test('import: non-.task rejected', () async {
    final String src = stageModel('model.gguf', 60);
    final Result<ModelCandidate> r =
        await manager().importFromFile(src);
    expect(r.isErr, isTrue);
    expect(r.failureOrNull!.message, 'ai-import-not-a-task');
  });

  test('import: missing source rejected', () async {
    final Result<ModelCandidate> r =
        await manager().importFromFile('picked/ghost.task');
    expect(r.failureOrNull!.message, 'ai-import-missing');
  });

  test('import: below 50 MB rejected, above 5 GB rejected', () async {
    final String small = stageModel('tiny.task', 49);
    expect(
      (await manager().importFromFile(small)).failureOrNull!.message,
      'ai-import-size',
    );
    // 6 GB — over the cap. Memory-light: the store fakes sizes via
    // real byte lists, so use a >5GB list is impossible in-memory;
    // instead exercise the boundary via a stub store.
    final _OversizeStore oversize = _OversizeStore();
    final ModelManager m = ModelManager(
      store: oversize,
      kv: kv,
      engine: engine,
      totalRamMb: () async => 8 * 1024,
    );
    final Result<ModelCandidate> r =
        await m.importFromFile('picked/huge.task');
    expect(r.failureOrNull!.message, 'ai-import-size');
  });

  test('load: happy path → loaded, engine fed, idle timer armed',
      () async {
    stageModel(
      'gemma-3n-e2b-it-int4.task',
      60,
      dir: ModelPaths.importedDir,
    );
    final ModelManager m = manager();
    await m.discover();
    final Result<bool> r = await m.load();
    expect(r.valueOrNull, isTrue);
    expect(m.state.phase, ModelPhase.loaded);
    expect(engine.loadedPaths, hasLength(1));
    expect(engine.loadedPaths.single, contains('.task'));
    expect(m.isLoaded, isTrue);
    await m.unload();
    expect(m.state.phase, ModelPhase.ready);
    expect(engine.unloadCalls, 1);
  });

  test('load: no model → honest model-absent', () async {
    final Result<bool> r = await manager().load();
    expect(r.failureOrNull!.message, 'model-absent');
  });

  test('load: SHA mismatch fails closed', () async {
    final String src = stageModel('corrupt.task', 60);
    final ModelManager m = manager();
    await m.importFromFile(src);
    // Tamper after import.
    store.files['${ModelPaths.importedDir}/corrupt.task']![0] = 255;
    final Result<bool> r = await m.load();
    expect(r.failureOrNull!.message, 'ai-sha-mismatch');
    expect(engine.loadedPaths, isEmpty);
    expect(m.state.phase, ModelPhase.error);
  });

  test('idle unload fires after the idle timeout (preload off)',
      () async {
    stageModel(
      'gemma-3n-e2b-it-int4.task',
      60,
      dir: ModelPaths.importedDir,
    );
    final ModelManager m = manager(idle: const Duration(milliseconds: 5));
    await m.discover();
    await m.load();
    expect(m.isLoaded, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(m.isLoaded, isFalse, reason: 'idle timer must unload');
    expect(engine.unloadCalls, 1);
  });

  test('preload ON keeps the model resident past idle', () async {
    stageModel(
      'gemma-3n-e2b-it-int4.task',
      60,
      dir: ModelPaths.importedDir,
    );
    final ModelManager m = manager(idle: const Duration(milliseconds: 5));
    await m.discover();
    await m.setPreload(true);
    await m.load();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(m.isLoaded, isTrue, reason: 'preload pins the model');
    expect(engine.unloadCalls, 0);
  });

  test('preload defaults OFF', () async {
    expect(await manager().preloadEnabled(), isFalse);
  });

  test('memory pressure unloads unless preload', () async {
    stageModel(
      'gemma-3n-e2b-it-int4.task',
      60,
      dir: ModelPaths.importedDir,
    );
    final ModelManager m = manager();
    await m.discover();
    await m.load();
    await m.onAppMemoryPressure();
    expect(m.isLoaded, isFalse);
    expect(engine.unloadCalls, 1);

    await m.load();
    await m.setPreload(true);
    await m.onAppMemoryPressure();
    expect(m.isLoaded, isTrue, reason: 'pinned by user preference');
  });

  test('deleteModel unloads, removes file + registry', () async {
    final String src = stageModel('gone.task', 60);
    final ModelManager m = manager();
    await m.importFromFile(src);
    await m.load();
    final Result<bool> r = await m.deleteModel();
    expect(r.valueOrNull, isTrue);
    expect(m.state.phase, ModelPhase.absent);
    expect((await kv.get(ModelManager.kvImported)).valueOrNull, isNull);
    expect(
      await store.exists('${ModelPaths.importedDir}/gone.task'),
      isFalse,
    );
  });

  group('tiering', () {
    test('RAM bands: <5GB small, 6GB e2b, 8GB e4b', () {
      expect(
        ModelTiers.suggested(totalRamMb: 3 * 1024),
        ModelTier.small,
      );
      expect(
        ModelTiers.suggested(totalRamMb: 5 * 1024),
        ModelTier.small,
      );
      expect(
        ModelTiers.suggested(totalRamMb: 6 * 1024),
        ModelTier.e2b,
      );
      expect(
        ModelTiers.suggested(totalRamMb: 7 * 1024),
        ModelTier.e2b,
      );
      expect(
        ModelTiers.suggested(totalRamMb: 8 * 1024),
        ModelTier.e4b,
      );
      expect(
        ModelTiers.suggested(totalRamMb: 16 * 1024),
        ModelTier.e4b,
      );
    });

    test('unknown RAM → conservative small', () {
      expect(ModelTiers.suggested(totalRamMb: 0), ModelTier.small);
      expect(ModelTiers.suggested(totalRamMb: -1), ModelTier.small);
    });

    test('file-name tiers', () {
      expect(
        ModelTiers.tierForFileName('gemma-3n-E4B-it-int4.task'),
        ModelTier.e4b,
      );
      expect(
        ModelTiers.tierForFileName('gemma-3n-e2b-it-int4.task'),
        ModelTier.e2b,
      );
      expect(
        ModelTiers.tierForFileName('functiongemma-270m-it.task'),
        ModelTier.small,
      );
      expect(ModelTiers.tierForFileName('mystery.bin'), isNull);
    });

    test('fits: e4b file on a 6GB device is flagged', () {
      expect(ModelTiers.fits(ModelTier.e4b, 6 * 1024), isFalse);
      expect(ModelTiers.fits(ModelTier.e2b, 6 * 1024), isTrue);
      expect(ModelTiers.fits(ModelTier.small, 3 * 1024), isTrue);
      expect(ModelTiers.fits(null, 3 * 1024), isTrue);
    });

    test('suggestedTier reads the RAM channel once', () async {
      final ModelManager m = manager(ramMb: 6 * 1024);
      expect(await m.suggestedTier(), ModelTier.e2b);
      expect(await m.deviceRamMb(), 6 * 1024);
    });
  });
}

/// Store stub that reports an over-cap size without materialising
/// 5 GB of bytes.
class _OversizeStore extends MemoryModelFileStore {
  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<int> sizeOf(String path) async =>
      6 * 1024 * 1024 * 1024;
}
