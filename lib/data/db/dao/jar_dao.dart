// phase-02
// `jar` — labelled savings goals.
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/jar.dart';

class JarDao {
  JarDao(this._db);
  final Future<Database> _db;

  Future<Result<void>> insert(Jar jar) {
    return guardDb('jar.insert', () async {
      final Database db = await _db;
      await db.insert('jar', jar.toRow());
    });
  }

  Future<Result<List<Jar>>> getAll() {
    return guardDb('jar.getAll', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows =
          await db.query('jar', orderBy: 'sort ASC, created_at ASC');
      return rows.map(Jar.fromRow).toList(growable: false);
    });
  }

  Future<Result<void>> update(Jar jar) {
    return guardDb('jar.update', () async {
      final Database db = await _db;
      await db.update(
        'jar',
        jar.toRow(),
        where: 'id = ?',
        whereArgs: <Object?>[jar.id],
      );
    });
  }

  Future<Result<void>> deleteById(String id) {
    return guardDb('jar.deleteById', () async {
      final Database db = await _db;
      await db.delete('jar', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }
}
