// phase-04
// Pure AES-256-GCM file codec (pointycastle) — no plugins, no IO,
// unit-testable in the plain Dart VM. Blob layout is
// `[12-byte IV][ciphertext || 16-byte GCM tag]`. Authenticated: a
// flipped byte anywhere fails the tag and [decrypt] throws — receipt
// vault files are tamper-evident by construction.
//
// pointycastle's GCMBlockCipher.process appends the tag to the
// ciphertext on encrypt and verifies it on decrypt.
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

abstract final class AesGcmCodec {
  static const int ivLength = 12;
  static const int tagLength = 16;

  /// Encrypts [plaintext] under [key] (16/24/32 bytes) with a fresh
  /// random IV. Returns IV || ciphertext || tag.
  static Uint8List encrypt({
    required Uint8List key,
    required Uint8List plaintext,
  }) {
    final Uint8List iv = _secureBytes(ivLength);
    final GCMBlockCipher cipher = GCMBlockCipher(AESEngine())
      ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));
    final Uint8List sealed = cipher.process(plaintext);
    final Uint8List blob = Uint8List(ivLength + sealed.length)
      ..setRange(0, ivLength, iv)
      ..setRange(ivLength, ivLength + sealed.length, sealed);
    return blob;
  }

  /// Verifies + decrypts a blob produced by [encrypt]. Throws
  /// (`InvalidCipherTextException` / `ArgumentError`) on tampering,
  /// wrong key, or a blob shorter than IV+tag.
  static Uint8List decrypt({
    required Uint8List key,
    required Uint8List blob,
  }) {
    if (blob.length < ivLength + tagLength) {
      throw ArgumentError('blob shorter than IV+tag');
    }
    final Uint8List iv = Uint8List.sublistView(blob, 0, ivLength);
    final Uint8List sealed =
        Uint8List.sublistView(blob, ivLength);
    final GCMBlockCipher cipher = GCMBlockCipher(AESEngine())
      ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(key), iv));
    return cipher.process(sealed);
  }

  static Uint8List _secureBytes(int length) {
    final Random random = Random.secure();
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
