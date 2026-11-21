// phase-02
// `capture_event` — pipeline health + the 24h raw-text privacy purge.
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/capture_event.dart';

/// One day of capture-pipeline counters (health dashboard row).
class CaptureDayStats {
  const CaptureDayStats({
    required this.dayStartMs,
    required this.seen,
    required this.parsed,
    required this.deduped,
  });
  final int dayStartMs;
  final int seen;
  final int parsed;

  /// Duplicates suppressed by the dedup engine.
  final int deduped;
}

class CaptureHealthDao {
  CaptureHealthDao(this._db);
  final Future<Database> _db;

  Future<Result<void>> insert(CaptureEvent event) {
    return guardDb('capture.insert', () async {
      final Database db = await _db;
      await db.insert('capture_event', event.toRow());
    });
  }

  /// **Privacy job:** blanks `raw_text` on rows older than [cutoff]
  /// (default 24h). The row survives with hash + parsed fields — the
  /// review queue only ever sees fresh text. Returns rows purged.
  Future<Result<int>> purgeRawTextOlderThan(
    DateTime cutoff, {
    int limit = 500,
  }) {
    return guardDb('capture.purgeRawTextOlderThan', () async {
      final Database db = await _db;
      return db.update(
        'capture_event',
        <String, Object?>{'raw_text': null},
        where: 'received_at < ? AND raw_text IS NOT NULL'
            ' AND id IN (SELECT id FROM capture_event'
            '  WHERE received_at < ? AND raw_text IS NOT NULL LIMIT ?)',
        whereArgs: <Object?>[
          cutoff.millisecondsSinceEpoch,
          cutoff.millisecondsSinceEpoch,
          limit,
        ],
      );
    });
  }

  /// Per-day counters for the health dashboard (recent first).
  Future<Result<List<CaptureDayStats>>> statsByDay({int days = 14}) {
    return guardDb('capture.statsByDay', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT (received_at / 86400000) * 86400000 AS day,'
        '   COUNT(*) AS seen,'
        '   SUM(parsed) AS parsed,'
        '   SUM(deduped) AS deduped'
        ' FROM capture_event'
        ' GROUP BY day ORDER BY day DESC LIMIT ?',
        <Object?>[days],
      );
      return rows
          .map(
            (Map<String, Object?> r) => CaptureDayStats(
              dayStartMs: r['day']! as int,
              seen: r['seen']! as int,
              parsed: (r['parsed'] as int? ?? 0),
              deduped: (r['deduped'] as int? ?? 0),
            ),
          )
          .toList(growable: false);
    });
  }

  /// Latest events, newest first (debug/Settings view).
  Future<Result<List<CaptureEvent>>> recent({int limit = 50}) {
    return guardDb('capture.recent', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'capture_event',
        orderBy: 'received_at DESC',
        limit: limit,
      );
      return rows.map(CaptureEvent.fromRow).toList(growable: false);
    });
  }
}
