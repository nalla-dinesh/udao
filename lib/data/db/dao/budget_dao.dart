// phase-02
// `budget` CRUD.
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/budget.dart';

class BudgetDao {
  BudgetDao(this._db);
  final Future<Database> _db;

  Future<Result<void>> upsert(Budget budget) {
    return guardDb('budget.upsert', () async {
      final Database db = await _db;
      await db.insert(
        'budget',
        budget.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Active budgets (`active` flag on). Pass `includeInactive: true`
  /// for the Settings management list.
  Future<Result<List<Budget>>> getAll({bool includeInactive = false}) {
    return guardDb('budget.getAll', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'budget',
        where: includeInactive ? null : 'active = 1',
        orderBy: 'category_id ASC',
      );
      return rows.map(Budget.fromRow).toList(growable: false);
    });
  }

  /// The budget guarding one category (null = whole-wallet budget
  /// may exist but is not returned here).
  Future<Result<Budget?>> findByCategory(String categoryId) {
    return guardDb('budget.findByCategory', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'budget',
        where: 'category_id = ? AND active = 1',
        whereArgs: <Object?>[categoryId],
        limit: 1,
      );
      return rows.isEmpty ? null : Budget.fromRow(rows.first);
    });
  }

  Future<Result<void>> deleteById(String id) {
    return guardDb('budget.deleteById', () async {
      final Database db = await _db;
      await db.delete('budget', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }
}
