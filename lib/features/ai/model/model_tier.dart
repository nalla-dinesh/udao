// phase-06
// Device-RAM tiering for on-device models (spec): phones under 5 GB
// get the FunctionGemma-class small models suggested, 6 GB+ the Gemma
// 3n E2B, 8 GB+ may run E4B. Suggestion only — a user who insists on
// loading a bigger model is never hard-blocked, the AI settings
// screen just says what the device suggests (their RAM, their call).
//
// RAM comes from our own `udao/platform` channel (MainActivity →
// ActivityManager.MemoryInfo), NOT device_info_plus — that plugin's
// RAM field names drift between majors and this value must not.
enum ModelTier {
  /// FunctionGemma-class function-calling models (270M, ≈288 MB).
  small('functiongemma_270m'),

  /// Gemma 3n E2B it-int4 (≈2 GB .task) — the default target.
  e2b('gemma-3n-e2b-it-int4.task'),

  /// Gemma 3n E4B it-int4 (≈3 GB .task) — 8 GB+ devices.
  e4b('gemma-3n-e4b-it-int4.task');

  const ModelTier(this.suggestedFile);

  /// File the docs point at for this tier (see docs/ai/models.md).
  final String suggestedFile;

  String get label => switch (this) {
        ModelTier.small => 'Small (270M)',
        ModelTier.e2b => 'E2B',
        ModelTier.e4b => 'E4B',
      };
}

abstract final class ModelTiers {
  /// Whole-MB thresholds (plain literals — SDK floor < 3.6).
  static const int smallMaxRamMb = 5 * 1024;
  static const int e2bMinRamMb = 6 * 1024;
  static const int e4bMinRamMb = 8 * 1024;

  /// The highest tier this device's RAM suggests. 0 / unknown RAM →
  /// small (the conservative floor — a device we could not measure
  /// is never told "sure, load the 3 GB model").
  static ModelTier suggested({required int totalRamMb}) {
    if (totalRamMb <= 0 || totalRamMb < e2bMinRamMb) {
      return ModelTier.small;
    }
    if (totalRamMb < e4bMinRamMb) {
      return ModelTier.e2b;
    }
    return ModelTier.e4b;
  }

  /// Tier a model FILE looks like, by name. Unknown naming → null
  /// (surfaced honestly as "unknown tier" instead of a guess).
  static ModelTier? tierForFileName(String fileName) {
    final String f = fileName.toLowerCase();
    if (f.contains('e4b')) {
      return ModelTier.e4b;
    }
    if (f.contains('e2b')) {
      return ModelTier.e2b;
    }
    if (f.contains('270m') || f.contains('functiongemma')) {
      return ModelTier.small;
    }
    return null;
  }

  /// True when [fileTier] fits within what the device suggests
  /// (unknown file tier = fits — we do not refuse unlisted names).
  static bool fits(ModelTier? fileTier, int totalRamMb) {
    if (fileTier == null) {
      return true;
    }
    final ModelTier suggestedTier = suggested(totalRamMb: totalRamMb);
    return fileTier.index <= suggestedTier.index;
  }
}
