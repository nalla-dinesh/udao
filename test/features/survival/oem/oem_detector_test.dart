// phase-05
// The OEM detection matrix — 30 realistic Build pairs (manufacturer,
// brand). The brand-first rule (sub-brand precision) is the load-
// bearing behavior: Poco/Redmi→xiaomi, iQOO→vivo-family iQOO,
// honor-brand-on-Huawei→honor.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/features/survival/oem/oem_detector.dart';

void main() {
  const OemDetector detector = OemDetector();

  OemId detect(String manufacturer, String brand) =>
      detector.detect(manufacturer: manufacturer, brand: brand);

  group('xiaomi family (brand wins)', () {
    test('Poco brand, Xiaomi manufacturer', () {
      expect(detect('Xiaomi', 'poco'), OemId.xiaomi);
    });
    test('Redmi brand, Xiaomi manufacturer', () {
      expect(detect('Xiaomi', 'Redmi'), OemId.xiaomi);
    });
    test('plain xiaomi brand', () {
      expect(detect('Xiaomi', 'xiaomi'), OemId.xiaomi);
    });
    test('manufacturer fallback when brand generic', () {
      expect(detect('Xiaomi', 'Android'), OemId.xiaomi);
    });
    test('case-insensitive', () {
      expect(detect('XIAOMI', 'POCO'), OemId.xiaomi);
    });
    test('whitespace trimmed', () {
      expect(detect('  Xiaomi ', ' poco '), OemId.xiaomi);
    });
    test('old MI branding', () {
      expect(detect('Xiaomi', 'mi'), OemId.xiaomi);
    });
  });

  group('samsung', () {
    test('plain samsung', () {
      expect(detect('samsung', 'samsung'), OemId.samsung);
    });
    test('Samsung Electronics manufacturer', () {
      expect(detect('Samsung Electronics', 'samsung'), OemId.samsung);
    });
    test('unknown brand, samsung manufacturer', () {
      expect(detect('samsung', 'galaxy'), OemId.samsung);
    });
  });

  group('vivo family (the iQOO split)', () {
    test('plain vivo', () {
      expect(detect('vivo', 'vivo'), OemId.vivo);
    });
    test('iQOO brand with vivo manufacturer → iQOO (brand precision)',
        () {
      expect(detect('vivo', 'iQOO'), OemId.iqoo);
    });
    test('vivo manufacturer, generic brand → vivo', () {
      expect(detect('vivo', 'Android'), OemId.vivo);
    });
    test('iqoo both fields', () {
      expect(detect('iqoo', 'iqoo'), OemId.iqoo);
    });
  });

  group('oppo / realme / oneplus', () {
    test('plain oppo', () {
      expect(detect('OPPO', 'OPPO'), OemId.oppo);
    });
    test('realme brand (coloros base)', () {
      expect(detect('realme', 'realme'), OemId.realme);
    });
    test('Realme manufacturer with generic brand', () {
      expect(detect('Realme', 'Android'), OemId.realme);
    });
    test('plain oneplus', () {
      expect(detect('OnePlus', 'OnePlus'), OemId.oneplus);
    });
    test('oplus brand (merged builds) → oneplus', () {
      expect(detect('OnePlus', 'oplus'), OemId.oneplus);
    });
    test('One Plus Technology manufacturer', () {
      expect(detect('One Plus Technology', 'oplus'), OemId.oneplus);
    });
  });

  group('huawei / honor (post-split aliases)', () {
    test('plain huawei', () {
      expect(detect('HUAWEI', 'HUAWEI'), OemId.huawei);
    });
    test('honor brand on huawei-era device → honor (brand wins)', () {
      expect(detect('Huawei', 'honor'), OemId.honor);
    });
    test('plain honor', () {
      expect(detect('HONOR', 'HONOR'), OemId.honor);
    });
    test('HiHonor post-split builds', () {
      expect(detect('HiHonor', 'hihonor'), OemId.honor);
    });
  });

  group('nokia', () {
    test('plain nokia', () {
      expect(detect('Nokia', 'Nokia'), OemId.nokia);
    });
    test('HMD Global manufacturer', () {
      expect(detect('HMD Global', 'Nokia'), OemId.nokia);
    });
  });

  group('stock family (honest default)', () {
    test('google pixel', () {
      expect(detect('Google', 'google'), OemId.stock);
    });
    test('google manufacturer, generic brand', () {
      expect(detect('Google', 'Android'), OemId.stock);
    });
    test('motorola', () {
      expect(detect('motorola', 'motorola'), OemId.stock);
    });
    test('asus', () {
      expect(detect('asus', 'ASUS'), OemId.stock);
    });
    test('nothing phone', () {
      expect(detect('Nothing', 'Nothing'), OemId.stock);
    });
    test('fully unknown maker', () {
      expect(detect('AcmeCorp', 'acme'), OemId.stock);
    });
    test('empty fields never crash', () {
      expect(detect('', ''), OemId.stock);
    });
  });

  group('aggressive-killer flags (nag weight)', () {
    test('the eight aggressive makers', () {
      const List<OemId> aggressive = <OemId>[
        OemId.xiaomi,
        OemId.huawei,
        OemId.honor,
        OemId.oppo,
        OemId.vivo,
        OemId.iqoo,
        OemId.realme,
        OemId.oneplus,
      ];
      for (final OemId id in aggressive) {
        expect(id.isAggressiveKiller, isTrue, reason: id.slug);
      }
    });
    test('samsung/nokia/stock are not flagged', () {
      expect(OemId.samsung.isAggressiveKiller, isFalse);
      expect(OemId.nokia.isAggressiveKiller, isFalse);
      expect(OemId.stock.isAggressiveKiller, isFalse);
    });
  });

  test('matrix size is the locked 11', () {
    expect(OemId.values, hasLength(11));
  });
}
