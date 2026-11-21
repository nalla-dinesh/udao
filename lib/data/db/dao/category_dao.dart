// phase-02
// `category` reads + reseed path.
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/category.dart';

class CategoryDao {
  CategoryDao(this._db);
  final Future<Database> _db;

  /// All categories, display order.
  Future<Result<List<Category>>> getAll() {
    return guardDb('category.getAll', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows =
          await db.query('category', orderBy: 'sort ASC');
      return rows.map(Category.fromRow).toList(growable: false);
    });
  }

  Future<Result<Category?>> findById(String id) {
    return guardDb('category.findById', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'category',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : Category.fromRow(rows.first);
    });
  }

  /// Insert-or-replace every seed row (post-wipe reseed, imports).
  Future<Result<void>> upsertAll(List<Category> categories) {
    return guardDb('category.upsertAll', () async {
      final Database db = await _db;
      final Batch batch = db.batch();
      for (final Category c in categories) {
        batch.insert(
          'category',
          c.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Result<void>> update(Category category) {
    return guardDb('category.update', () async {
      final Database db = await _db;
      await db.update(
        'category',
        category.toRow(),
        where: 'id = ?',
        whereArgs: <Object?>[category.id],
      );
    });
  }
}
