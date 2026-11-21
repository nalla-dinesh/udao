// phase-02
// `badge` + `challenge_progress` — Khel persistence.
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/badge.dart';

class BadgeDao {
  BadgeDao(this._db);
  final Future<Database> _db;

  Future<Result<void>> upsert(Badge badge) {
    return guardDb('badge.upsert', () async {
      final Database db = await _db;
      await db.insert(
        'badge',
        badge.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Result<List<Badge>>> getAll() {
    return guardDb('badge.getAll', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows =
          await db.query('badge', orderBy: 'unlocked_at DESC');
      return rows.map(Badge.fromRow).toList(growable: false);
    });
  }

  Future<Result<void>> markSeen(String id) {
    return guardDb('badge.markSeen', () async {
      final Database db = await _db;
      await db.update(
        'badge',
        <String, Object?>{'seen': 1},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  Future<Result<void>> upsertChallenge(ChallengeProgress progress) {
    return guardDb('badge.upsertChallenge', () async {
      final Database db = await _db;
      await db.insert(
        'challenge_progress',
        progress.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Result<List<ChallengeProgress>>> allChallenges() {
    return guardDb('badge.allChallenges', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows =
          await db.query('challenge_progress', orderBy: 'id ASC');
      return rows.map(ChallengeProgress.fromRow).toList(growable: false);
    });
  }
}
