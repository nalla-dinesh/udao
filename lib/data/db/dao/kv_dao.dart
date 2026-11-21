// phase-02
// `kv` — tiny typed key/value store for engine state that doesn't
// deserve its own table (agent flags, seeds, counters).
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';

class KvDao {
  KvDao(this._db);
  final Future<Database> _db;

  Future<Result<String?>> get(String key) {
    return guardDb('kv.get', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'kv',
        columns: <String>['value'],
        where: 'key = ?',
        whereArgs: <Object?>[key],
        limit: 1,
      );
      return rows.isEmpty ? null : rows.first['value'] as String?;
    });
  }

  Future<Result<void>> set(String key, String value) {
    return guardDb('kv.set', () async {
      final Database db = await _db;
      await db.insert(
        'kv',
        <String, Object?>{
          'key': key,
          'value': value,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Result<void>> delete(String key) {
    return guardDb('kv.delete', () async {
      final Database db = await _db;
      await db.delete('kv', where: 'key = ?', whereArgs: <Object?>[key]);
    });
  }
}
