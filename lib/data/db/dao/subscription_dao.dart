// phase-02
// `subscription` — inferred recurring charges.
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/subscription.dart';

class SubscriptionDao {
  SubscriptionDao(this._db);
  final Future<Database> _db;

  Future<Result<void>> upsert(Subscription subscription) {
    return guardDb('subscription.upsert', () async {
      final Database db = await _db;
      await db.insert(
        'subscription',
        subscription.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<Result<List<Subscription>>> getAll() {
    return guardDb('subscription.getAll', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows =
          await db.query('subscription', orderBy: 'last_seen DESC');
      return rows.map(Subscription.fromRow).toList(growable: false);
    });
  }

  Future<Result<List<Subscription>>> findByMerchant(String merchantClean) {
    return guardDb('subscription.findByMerchant', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'subscription',
        where: 'merchant_clean = ?',
        whereArgs: <Object?>[merchantClean],
      );
      return rows.map(Subscription.fromRow).toList(growable: false);
    });
  }

  Future<Result<void>> markStatus(String id, SubscriptionStatus status) {
    return guardDb('subscription.markStatus', () async {
      final Database db = await _db;
      await db.update(
        'subscription',
        <String, Object?>{'status': status.name},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }
}
