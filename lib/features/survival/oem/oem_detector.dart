// phase-05
// OEM detection — pure logic, no IO, fully table-testable.
//
// Rule (spec of record): BOTH Build.MANUFACTURER and Build.BRAND are
// consulted; BRAND is checked FIRST because sub-brands are more
// specific there (an iQOO phone reports manufacturer "vivo" but
// brand "iQOO"; a Poco reports manufacturer "Xiaomi" but brand
// "Poco"). Matching is case-insensitive and whitespace-trimmed on
// exact tokens — no fuzzy contains() that could misfire on unknown
// strings. Unknown makers land on [OemId.stock] with an honest
// "khaas setup nahi mila" guide instead of a wrong one.
import 'package:flutter/foundation.dart';

/// The 11-entry survival matrix (10 makers + stock Android).
enum OemId {
  xiaomi('xiaomi', 'Xiaomi / MIUI (Poco, Redmi included)', 'https://dontkillmyapp.com/xiaomi'),
  samsung('samsung', 'Samsung (One UI)', 'https://dontkillmyapp.com/samsung'),
  oppo('oppo', 'Oppo (ColorOS)', 'https://dontkillmyapp.com/oppo'),
  realme('realme', 'Realme (Realme UI)', 'https://dontkillmyapp.com/realme'),
  vivo('vivo', 'Vivo (Funtouch / OriginOS)', 'https://dontkillmyapp.com/vivo'),
  iqoo('iqoo', 'iQOO', 'https://dontkillmyapp.com/vivo'),
  huawei('huawei', 'Huawei (EMUI)', 'https://dontkillmyapp.com/huawei'),
  honor('honor', 'Honor (MagicOS)', 'https://dontkillmyapp.com/honor'),
  oneplus('oneplus', 'OnePlus (OxygenOS)', 'https://dontkillmyapp.com/oneplus'),
  nokia('nokia', 'Nokia (near-stock)', 'https://dontkillmyapp.com/nokia'),
  stock('stock', 'Stock Android', 'https://dontkillmyapp.com');

  const OemId(this.slug, this.label, this.dontKillMyAppUrl);

  /// Stable machine id (kv + diagnostics export).
  final String slug;

  /// Human label for cards and headers.
  final String label;

  /// dontkillmyapp.com community page (the honest, kept-current
  /// reference for OEM kill behavior).
  final String dontKillMyAppUrl;

  /// True when this maker's stock behavior is known to kill
  /// background listeners (drives the dashboard's nag weight).
  bool get isAggressiveKiller => switch (this) {
        OemId.xiaomi ||
        OemId.huawei ||
        OemId.honor ||
        OemId.oppo ||
        OemId.vivo ||
        OemId.iqoo ||
        OemId.realme ||
        OemId.oneplus =>
          true,
        OemId.samsung || OemId.nokia || OemId.stock => false,
      };
}

/// Pure detection over (manufacturer, brand).
@immutable
class OemDetector {
  const OemDetector();

  /// BRAND tokens first (sub-brand precision), then MANUFACTURER.
  /// Exact match on the normalized token; anything unknown → stock.
  OemId detect({required String manufacturer, required String brand}) {
    final String b = _normalize(brand);
    final OemId? byBrand = _brandTable[b];
    if (byBrand != null) {
      return byBrand;
    }
    final String m = _normalize(manufacturer);
    return _manufacturerTable[m] ?? OemId.stock;
  }

  static String _normalize(String s) => s.trim().toLowerCase();

  /// Brand-level aliases (checked first — most specific).
  static const Map<String, OemId> _brandTable = <String, OemId>{
    'poco': OemId.xiaomi, // Poco brand, manufacturer "Xiaomi"
    'redmi': OemId.xiaomi, // Redmi brand, manufacturer "Xiaomi"
    'redmi note': OemId.xiaomi,
    'poco phone': OemId.xiaomi,
    'xiaomi': OemId.xiaomi,
    'mi': OemId.xiaomi, // very old MI branding
    'iqoo': OemId.iqoo, // brand iQOO, manufacturer "vivo"
    'vivo': OemId.vivo,
    'oppo': OemId.oppo,
    'realme': OemId.realme,
    'oneplus': OemId.oneplus,
    'oplus': OemId.oneplus, // newer OnePlus/Oppo merged builds
    'huawei': OemId.huawei,
    'honor': OemId.honor,
    'hihonor': OemId.honor, // post-split Honor builds
    'samsung': OemId.samsung,
    'nokia': OemId.nokia,
    'hmd global': OemId.nokia,
    'google': OemId.stock,
    'motorola': OemId.stock,
    'lenovo': OemId.stock,
    'asus': OemId.stock,
    'nothing': OemId.stock,
    'nothing phone': OemId.stock,
  };

  /// Manufacturer-level aliases (fallback when brand is generic,
  /// e.g. brand "Android" on some Vivo builds).
  static const Map<String, OemId> _manufacturerTable = <String, OemId>{
    'xiaomi': OemId.xiaomi,
    'vivo': OemId.vivo,
    'oppo': OemId.oppo,
    'realme': OemId.realme,
    'oneplus': OemId.oneplus,
    'one plus technology': OemId.oneplus,
    'huawei': OemId.huawei,
    'honor': OemId.honor,
    'hihonor': OemId.honor,
    'samsung': OemId.samsung,
    'samsung electronics': OemId.samsung,
    'nokia': OemId.nokia,
    'hmd global': OemId.nokia,
    'google': OemId.stock,
  };
}
