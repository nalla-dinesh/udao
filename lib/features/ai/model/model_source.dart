// phase-06
// Where an on-device model CAN come from. Discovery order (spec):
//   1. BundledAsset — a Play Asset Delivery on-demand pack
//      (`gemma3n_e2b` containing `gemma-3n-e2b-it-int4.task`).
//      Config-only today: PAD needs the play-core plugin + a Play
//      listing, so the human's setup path is documented in
//      docs/ai/asset-delivery.md and the expected file location is
//      a plain staging dir we can check without any plugin.
//   2. ImportedFile — a user-picked file copied into
//      <appDocuments>/models/imported/ via SAF (file_picker),
//      validated (extension, size, SHA-256) by [ModelManager].
//   3. Absent — template-only mode. The app NEVER pretends a model
//      is present (honesty law).
//
// No model binary is ever committed to git (gitignore: *.task,
// *.litertlm, *.gguf, /assets/models/).
sealed class ModelSource {
  const ModelSource();
}

/// Future PAD pack — resolves only when the pack's expected file has
/// actually landed in the staging dir (delivered by the human's PAD
/// flow, or `adb push` during development).
class BundledAsset extends ModelSource {
  const BundledAsset({required this.packName, required this.fileName});

  /// PAD on-demand pack id (`gemma3n_e2b`).
  final String packName;

  /// File the pack must contain (`gemma-3n-e2b-it-int4.task`).
  final String fileName;
}

/// A user-imported model file living under models/imported/.
class ImportedFile extends ModelSource {
  const ImportedFile({required this.path});

  /// Absolute path inside app-documents — never a SAF content uri
  /// (the file is COPIED at import time so it survives reboots).
  final String path;
}

/// No model on this device — the honest third state.
class Absent extends ModelSource {
  const Absent();
}

/// One concrete, validated model candidate found on disk.
class ModelCandidate {
  const ModelCandidate({
    required this.source,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.importedAtMs,
  });

  final ModelSource source;
  final String fileName;

  /// 50 MB–5 GB enforced at import (smaller = not a model, larger
  /// = almost certainly the wrong file / a zip).
  final int sizeBytes;

  /// Lowercase hex SHA-256 — computed at import, re-verified at every
  /// load (integrity: a corrupted re-download fails closed).
  final String sha256;
  final int importedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'importedAtMs': importedAtMs,
        'kind': source is BundledAsset ? 'bundled' : 'imported',
      };

  static ModelCandidate? fromJson(Map<Object?, Object?> json) {
    final String? name = json['fileName'] as String?;
    if (name == null) {
      return null;
    }
    final String kind = json['kind'] as String? ?? 'imported';
    return ModelCandidate(
      source: kind == 'bundled'
          ? BundledAsset(packName: 'gemma3n_e2b', fileName: name)
          : ImportedFile(path: 'models/imported/$name'),
      fileName: name,
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      sha256: json['sha256'] as String? ?? '',
      importedAtMs: json['importedAtMs'] as int? ?? 0,
    );
  }
}
