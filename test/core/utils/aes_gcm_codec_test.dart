// phase-04
// AES-256-GCM codec: round-trip integrity, per-file IV freshness,
// tamper detection (auth tag), wrong-key rejection, and blob-shape
// rejection. Pure pointycastle — runs in the plain VM.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/utils/aes_gcm_codec.dart';

Uint8List _key(int fill) => Uint8List.fromList(
      List<int>.generate(32, (int i) => (fill + i) % 256),
    );

void main() {
  test('round-trips arbitrary bytes', () {
    final Uint8List key = _key(1);
    final Uint8List plain = Uint8List.fromList(
      List<int>.generate(5000, (int i) => i % 251),
    );
    final Uint8List blob = AesGcmCodec.encrypt(key: key, plaintext: plain);
    expect(blob.length, plain.length + 12 + 16);
    final Uint8List back = AesGcmCodec.decrypt(key: key, blob: blob);
    expect(back, plain);
  });

  test('every encryption uses a fresh IV', () {
    final Uint8List key = _key(2);
    final Uint8List plain = Uint8List.fromList(<int>[1, 2, 3]);
    final Uint8List a = AesGcmCodec.encrypt(key: key, plaintext: plain);
    final Uint8List b = AesGcmCodec.encrypt(key: key, plaintext: plain);
    expect(a, isNot(b), reason: 'IV reuse would leak equality');
    expect(
      a.sublist(12),
      isNot(b.sublist(12)),
      reason: 'GCM nonce reuse is catastrophic',
    );
  });

  test('tampered ciphertext fails the tag', () {
    final Uint8List key = _key(3);
    final Uint8List blob =
        AesGcmCodec.encrypt(key: key, plaintext: Uint8List.fromList(<int>[9, 9, 9, 9]));
    blob[blob.length - 1] ^= 0x01;
    expect(
      () => AesGcmCodec.decrypt(key: key, blob: blob),
      throwsA(anything),
      reason: 'GCM authentication must catch bit flips',
    );
  });

  test('tampered IV fails the tag', () {
    final Uint8List key = _key(4);
    final Uint8List blob =
        AesGcmCodec.encrypt(key: key, plaintext: Uint8List.fromList(<int>[7]));
    blob[0] ^= 0xFF;
    expect(() => AesGcmCodec.decrypt(key: key, blob: blob), throwsA(anything));
  });

  test('wrong key fails', () {
    final Uint8List blob = AesGcmCodec.encrypt(
      key: _key(5),
      plaintext: Uint8List.fromList(<int>[1, 2, 3]),
    );
    expect(
      () => AesGcmCodec.decrypt(key: _key(6), blob: blob),
      throwsA(anything),
    );
  });

  test('short blob rejected without touching the cipher', () {
    final Uint8List tiny = Uint8List.fromList(<int>[1, 2, 3]);
    expect(
      () => AesGcmCodec.decrypt(key: _key(7), blob: tiny),
      throwsArgumentError,
    );
  });

  test('empty plaintext still round-trips (sealed empty file)', () {
    final Uint8List key = _key(8);
    final Uint8List blob = AesGcmCodec.encrypt(
      key: key,
      plaintext: Uint8List(0),
    );
    expect(blob.length, 12 + 16);
    expect(AesGcmCodec.decrypt(key: key, blob: blob), isEmpty);
  });
}
