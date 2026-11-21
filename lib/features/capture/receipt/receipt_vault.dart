// phase-04
// Encrypted receipt storage: each saved receipt image (a
// picker-resized JPEG — full-res originals are deliberately NOT
// kept) is AES-256-GCM sealed with a per-file random IV under a key
// that lives in Android Keystore-backed secure storage. At rest the
// files are ciphertext; even a copied backup directory reveals
// nothing without the key.
//
// Backup exclusion: the app already ships allowBackup=false (the
// encrypted DB is unrestorable without its Keystore key and cloud
// backup of financial metadata contradicts the zero-cloud promise),
// so nothing — vault included — ever leaves the device via backup or
// device-transfer. The vault still encrypts independently: defense
// in depth against local extraction (adb backup is dead, but a
// rooted file copy is not).
//
// Lifecycle: one receipt per txn, named by txn id, deleted with the
// txn (LedgerRepo/receipt sheet call [delete]).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/aes_gcm_codec.dart';

/// The vault key: 32 random bytes, base64, exactly once, never
/// logged, never leaves secure storage (mirrors DbKeyStore).
abstract final class ReceiptVaultKeyStore {
  static const String _keyName = 'receipt_vault_key';

  static Future<Uint8List> ensureKey() async {
    const FlutterSecureStorage storage = FlutterSecureStorage();
    final String? existing = await storage.read(key: _keyName);
    if (existing != null && existing.isNotEmpty) {
      final Uint8List? decoded = tryDecode(existing);
      if (decoded != null && decoded.length == 32) {
        return decoded;
      }
    }
    final Random random = Random.secure();
    final Uint8List bytes = Uint8List(32);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    await storage.write(key: _keyName, value: base64Encode(bytes));
    return bytes;
  }

  static Uint8List? tryDecode(String base64) {
    try {
      return base64Decode(base64);
    } on Object {
      return null;
    }
  }
}

/// The storage seam — tests install an in-memory fake.
abstract class ReceiptVault {
  /// Seals [jpegBytes] as the receipt for [txnId]. Overwrites any
  /// previous receipt for the same txn. Returns the stored path.
  Future<Result<String>> save(String txnId, List<int> jpegBytes);

  /// Decrypts the receipt for [txnId]; `Ok(null)` when absent.
  Future<Result<Uint8List?>> read(String txnId);

  Future<Result<bool>> exists(String txnId);

  /// Deletes with the txn — an orphaned ciphertext must not linger.
  Future<Result<void>> delete(String txnId);
}

class EncryptedReceiptVault implements ReceiptVault {
  EncryptedReceiptVault({required Future<Directory> Function() baseDir})
      : _baseDir = baseDir;

  static const String dirName = 'receipt-vault';

  final Future<Directory> Function() _baseDir;

  Future<Directory> _vaultDir() async {
    final Directory base = await _baseDir();
    final Directory dir = Directory('${base.path}/$dirName');
    await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<Result<String>> save(String txnId, List<int> jpegBytes) async {
    try {
      final Directory dir = await _vaultDir();
      final Uint8List key = await ReceiptVaultKeyStore.ensureKey();
      final Uint8List blob = AesGcmCodec.encrypt(
        key: key,
        plaintext: Uint8List.fromList(jpegBytes),
      );
      final File file = File('${dir.path}/$txnId.bin');
      await file.writeAsBytes(blob, flush: true);
      return Ok(file.path);
    } on Object catch (e, s) {
      return Err(CaptureFailure('vault_save_failed', cause: e, stackTrace: s));
    }
  }

  @override
  Future<Result<Uint8List?>> read(String txnId) async {
    try {
      final Directory dir = await _vaultDir();
      final File file = File('${dir.path}/$txnId.bin');
      if (!await file.exists()) {
        return const Ok<Uint8List?>(null);
      }
      final Uint8List key = await ReceiptVaultKeyStore.ensureKey();
      return Ok<Uint8List?>(
        AesGcmCodec.decrypt(key: key, blob: await file.readAsBytes()),
      );
    } on Object catch (e, s) {
      return Err(CaptureFailure('vault_read_failed', cause: e, stackTrace: s));
    }
  }

  @override
  Future<Result<bool>> exists(String txnId) async {
    try {
      final Directory base = await _baseDir();
      return Ok(await File('${base.path}/$dirName/$txnId.bin').exists());
    } on Object catch (e, s) {
      return Err(
        CaptureFailure('vault_exists_failed', cause: e, stackTrace: s),
      );
    }
  }

  @override
  Future<Result<void>> delete(String txnId) async {
    try {
      final Directory base = await _baseDir();
      final File file = File('${base.path}/$dirName/$txnId.bin');
      if (await file.exists()) {
        await file.delete();
      }
      return const Ok<void>(null);
    } on Object catch (e, s) {
      return Err(
        CaptureFailure('vault_delete_failed', cause: e, stackTrace: s),
      );
    }
  }
}
