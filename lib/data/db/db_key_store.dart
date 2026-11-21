// phase-02
// The SQLCipher key: 32 random bytes, base64, generated exactly once
// and kept in Android Keystore-backed secure storage.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class DbKeyStore {
  static const String _dbKeyName = 'db_key';

  /// Returns the existing key, creating + persisting a fresh one on
  /// first run. Never logged, never leaves the device.
  static Future<String> ensureDbKey() async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    final String? existing = await storage.read(key: _dbKeyName);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final Random random = Random.secure();
    final Uint8List bytes = Uint8List(32);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    final String key = base64Encode(bytes);
    await storage.write(key: _dbKeyName, value: key);
    return key;
  }
}
