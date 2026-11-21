// phase-02
// Duplicate detection: `sha1(ref | amount | counterparty | 10-minute
// bucket)` — the fingerprint stored on every txn row (unique index)
// and consulted by the capture repo before writes.
import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract final class DedupEngine {
  /// 10-minute bucket width in ms.
  static const int bucketMs = 600000;

  /// Stable sha1 of the raw capture text (capture_event.raw_hash).
  static String rawHash(String text) =>
      sha1.convert(utf8.encode(text)).toString();

  /// Stable fingerprint for one capture. Same payment reported by
  /// GPay (no ref) and HDFC (ref present) produces different
  /// fingerprints — the repo's `findNear` window catches those.
  static String fingerprint({
    required int amountPaise,
    required String counterparty,
    required DateTime at,
    String? refNo,
  }) {
    final int bucket = (at.millisecondsSinceEpoch ~/ bucketMs) * bucketMs;
    final String ref =
        (refNo == null || refNo.isEmpty) ? '-' : refNo.trim();
    return sha1
        .convert(utf8.encode('$ref|$amountPaise|$counterparty|$bucket'))
        .toString();
  }
}
