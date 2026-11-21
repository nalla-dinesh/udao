// phase-02
// `streak_state` — the single-row Khel heart.
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/streak_state.dart';

class StreakDao {
  StreakDao(this._db);
  final Future<Database> _db;

  /// Reads row 1, creating the initial row on a fresh DB.
  Future<Result<StreakState>> read() {
    return guardDb('streak.read', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'streak_state',
        where: 'id = 1',
        limit: 1,
      );
      if (rows.isEmpty) {
        const StreakState initial = StreakState.initial();
        await db.insert('streak_state', initial.toRow());
        return initial;
      }
      return StreakState.fromRow(rows.first);
    });
  }

  Future<Result<void>> write(StreakState state) {
    return guardDb('streak.write', () async {
      final Database db = await _db;
      await db.insert(
        'streak_state',
        state.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Result<void>> reset() => write(const StreakState.initial());
}
