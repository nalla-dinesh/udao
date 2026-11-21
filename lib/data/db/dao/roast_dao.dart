// phase-02
// `roast_entry` — roast history (dedup of template reuse + replays).
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/roast_entry.dart';

class RoastDao {
  RoastDao(this._db);
  final Future<Database> _db;

  Future<Result<void>> insert(RoastEntry entry) {
    return guardDb('roast.insert', () async {
      final Database db = await _db;
      await db.insert('roast_entry', entry.toRow());
    });
  }

  /// Latest-first page of roast history.
  Future<Result<List<RoastEntry>>> recent({int limit = 50, int offset = 0}) {
    return guardDb('roast.recent', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'roast_entry',
        orderBy: 'created_at DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map(RoastEntry.fromRow).toList(growable: false);
    });
  }

  /// Has [templateId] already fired today? (Roast novelty guard.)
  Future<Result<bool>> usedTemplateOnDay(String templateId, DateTime dayStart) {
    return guardDb('roast.usedTemplateOnDay', () async {
      final Database db = await _db;
      final int from = dayStart.millisecondsSinceEpoch;
      final int to = from + 86400000;
      final int? n = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM roast_entry'
          ' WHERE template_id = ? AND created_at >= ? AND created_at < ?',
          <Object?>[templateId, from, to],
        ),
      );
      return (n ?? 0) > 0;
    });
  }
}
