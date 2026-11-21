// phase-02
// `pending_review` — low-confidence captures awaiting a human.
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/pending_review_entry.dart';

class PendingReviewDao {
  PendingReviewDao(this._db);
  final Future<Database> _db;

  Future<Result<void>> insert(PendingReviewEntry entry) {
    return guardDb('review.insert', () async {
      final Database db = await _db;
      await db.insert('pending_review', entry.toRow());
    });
  }

  /// Phase-06: re-reads an UNRESOLVED entry with the LLM-fallback
  /// parser's fields (a human still approves afterwards). Row count
  /// 0 = already resolved or gone — callers treat that honestly.
  Future<Result<int>> updateParse(PendingReviewEntry entry) {
    return guardDb('review.updateParse', () async {
      final Database db = await _db;
      return db.update(
        'pending_review',
        entry.toRow(),
        where: 'id = ? AND resolved = 0',
        whereArgs: <Object?>[entry.id],
      );
    });
  }

  /// Oldest-first queue of unresolved entries.
  Future<Result<List<PendingReviewEntry>>> pending({
    int limit = 50,
    int offset = 0,
  }) {
    return guardDb('review.pending', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'pending_review',
        where: 'resolved = 0',
        orderBy: 'received_at ASC',
        limit: limit,
        offset: offset,
      );
      return rows.map(PendingReviewEntry.fromRow).toList(growable: false);
    });
  }

  /// Unresolved count (badge on the review entry point).
  Future<Result<int>> pendingCount() {
    return guardDb('review.pendingCount', () async {
      final Database db = await _db;
      return Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM pending_review WHERE resolved = 0',
            ),
          ) ??
          0;
    });
  }

  /// Marks the entry with the user's verdict — `approved` or
  /// `dismissed` (the Ledger repo converts approvals into txns).
  /// [at] overrides the resolve clock (tests pass deterministic
  /// times; production leaves it at wall-clock now).
  Future<Result<void>> resolve(String id, String resolution, {DateTime? at}) {
    return guardDb('review.resolve', () async {
      final Database db = await _db;
      await db.update(
        'pending_review',
        <String, Object?>{
          'resolved': 1,
          'resolution': resolution,
          'resolved_at': (at ?? DateTime.now()).millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  /// Housekeeping: delete resolved rows older than [cutoff].
  Future<Result<int>> deleteResolvedBefore(DateTime cutoff) {
    return guardDb('review.deleteResolvedBefore', () async {
      final Database db = await _db;
      return db.delete(
        'pending_review',
        where: 'resolved = 1 AND resolved_at < ?',
        whereArgs: <Object?>[cutoff.millisecondsSinceEpoch],
      );
    });
  }
}
