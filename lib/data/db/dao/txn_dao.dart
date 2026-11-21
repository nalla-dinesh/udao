// phase-02
// All reads/writes for the `txn` table — the hottest DAO in the app.
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/db/dao/dao_helpers.dart';
import 'package:udao/data/models/txn.dart';

/// Category-wise total over a window (paise).
class CategorySpend {
  const CategorySpend({required this.categoryId, required this.total});
  final String? categoryId;
  final Money total;
}

/// Per-day spend total — `dayStartMs` is an IST midnight epoch-ms.
class DayTotal {
  const DayTotal({required this.dayStartMs, required this.debit});
  final int dayStartMs;
  final Money debit;
}

/// Per-day capture counts split by source (gap detector input).
class DaySourceCount {
  const DaySourceCount({
    required this.dayStartMs,
    required this.notification,
    required this.sms,
  });

  final int dayStartMs;
  final int notification;
  final int sms;

  int get total => notification + sms;
}

class TxnDao {
  TxnDao(this._db);
  final Future<Database> _db;

  /// Insert-or-ignore keyed on `uq_txn_dedup`: first capture of a
  /// payment wins, later duplicates (GPay notification + HDFC SMS)
  /// are ignored. Returns true when this call performed the insert.
  Future<Result<bool>> upsertByDedupKey(Txn txn) {
    return guardDb('txn.upsertByDedupKey', () async {
      final Database db = await _db;
      final int rows = await db.insert(
        'txn',
        txn.toRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return rows > 0;
    });
  }

  Future<Result<Txn?>> findById(String id) {
    return guardDb('txn.findById', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'txn',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return rows.isEmpty ? null : Txn.fromRow(rows.first);
    });
  }

  Future<Result<Txn?>> findByDedupKey(String dedupKey) {
    return guardDb('txn.findByDedupKey', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.query(
        'txn',
        where: 'dedup_key = ?',
        whereArgs: <Object?>[dedupKey],
        limit: 1,
      );
      return rows.isEmpty ? null : Txn.fromRow(rows.first);
    });
  }

  /// Dedup across sources: same amount ± merchant within a 10-minute
  /// window around [around]. The dedup engine calls this before
  /// writing, when the fingerprint itself differs.
  Future<Result<List<Txn>>> findNear({
    required DateTime around,
    required int amountPaise,
    String? merchantClean,
    Duration window = const Duration(minutes: 10),
  }) {
    return guardDb('txn.findNear', () async {
      final Database db = await _db;
      final int from = around.subtract(window).millisecondsSinceEpoch;
      final int to = around.add(window).millisecondsSinceEpoch;
      final List<Map<String, Object?>> rows = await db.query(
        'txn',
        where: 'amount = ? AND occurred_at >= ? AND occurred_at <= ?'
            '${merchantClean == null ? '' : ' AND merchant_clean = ?'}',
        whereArgs: <Object?>[
          amountPaise,
          from,
          to,
          if (merchantClean != null) merchantClean,
        ],
        orderBy: 'occurred_at ASC',
      );
      return rows.map(Txn.fromRow).toList(growable: false);
    });
  }

  /// Filtered, newest-first page. Every filter is optional; `search`
  /// matches merchant_clean with a prefix-free LIKE.
  Future<Result<List<Txn>>> page({
    int limit = 50,
    int offset = 0,
    DateTime? from,
    DateTime? to,
    String? categoryId,
    TxnDirection? direction,
    TxnSource? source,
    String? search,
  }) {
    return guardDb('txn.page', () async {
      final Database db = await _db;
      final String where = _whereFor(
        from: from,
        to: to,
        categoryId: categoryId,
        direction: direction,
        source: source,
        search: search,
      );
      final List<Object?> args = _argsFor(
        from: from,
        to: to,
        categoryId: categoryId,
        direction: direction,
        source: source,
        search: search,
      );
      final List<Map<String, Object?>> rows = await db.query(
        'txn',
        where: where.isEmpty ? null : where,
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'occurred_at DESC, id DESC',
        limit: limit,
        offset: offset,
      );
      return rows.map(Txn.fromRow).toList(growable: false);
    });
  }

  Future<Result<int>> count({
    DateTime? from,
    DateTime? to,
    String? categoryId,
    TxnDirection? direction,
    TxnSource? source,
    String? search,
  }) {
    return guardDb('txn.count', () async {
      final Database db = await _db;
      final String where = _whereFor(
        from: from,
        to: to,
        categoryId: categoryId,
        direction: direction,
        source: source,
        search: search,
      );
      final List<Object?> args = _argsFor(
        from: from,
        to: to,
        categoryId: categoryId,
        direction: direction,
        source: source,
        search: search,
      );
      return Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM txn'
              '${where.isEmpty ? '' : ' WHERE $where'}',
              args.isEmpty ? null : args,
            ),
          ) ??
          0;
    });
  }

  /// Sum of `amount` matching the filters (sign-agnostic: pass a
  /// [direction] to split debits/credits).
  Future<Result<Money>> sumBetween(
    DateTime from,
    DateTime to, {
    String? categoryId,
    TxnDirection? direction,
  }) {
    return guardDb('txn.sumBetween', () async {
      final Database db = await _db;
      final List<Object?> args = <Object?>[
        from.millisecondsSinceEpoch,
        to.millisecondsSinceEpoch,
        if (categoryId != null) categoryId,
        if (direction != null) direction.name,
      ];
      final int? paise = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT SUM(amount) FROM txn'
          ' WHERE occurred_at >= ? AND occurred_at <= ?'
          '${categoryId == null ? '' : ' AND category_id = ?'}'
          '${direction == null ? '' : ' AND direction = ?'}',
          args,
        ),
      );
      return Money(paise ?? 0);
    });
  }

  /// Category totals over a window (debits only — budgets care about
  /// spends). NULL category rows are preserved as `categoryId: null`.
  Future<Result<List<CategorySpend>>> sumByCategory(
    DateTime from,
    DateTime to,
  ) {
    return guardDb('txn.sumByCategory', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT category_id, SUM(amount) AS total FROM txn'
        ' WHERE occurred_at >= ? AND occurred_at <= ?'
        '   AND direction = ?'
        ' GROUP BY category_id'
        ' ORDER BY total DESC',
        <Object?>[
          from.millisecondsSinceEpoch,
          to.millisecondsSinceEpoch,
          TxnDirection.debit.name,
        ],
      );
      return rows
          .map(
            (Map<String, Object?> r) => CategorySpend(
              categoryId: r['category_id'] as String?,
              total: Money(r['total'] as int? ?? 0),
            ),
          )
          .toList(growable: false);
    });
  }

  /// Per-day debit totals over a window (streaks + charts).
  Future<Result<List<DayTotal>>> totalsByDay(DateTime from, DateTime to) {
    return guardDb('txn.totalsByDay', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT occurred_at, SUM(amount) AS total FROM txn'
        ' WHERE occurred_at >= ? AND occurred_at <= ?'
        '   AND direction = ?'
        ' GROUP BY occurred_at / 86400000'
        ' ORDER BY occurred_at ASC',
        <Object?>[
          from.millisecondsSinceEpoch,
          to.millisecondsSinceEpoch,
          TxnDirection.debit.name,
        ],
      );
      return rows
          .map(
            (Map<String, Object?> r) => DayTotal(
              dayStartMs: ((r['occurred_at']! as int) ~/ 86400000) * 86400000,
              debit: Money(r['total'] as int? ?? 0),
            ),
          )
          .toList(growable: false);
    });
  }

  /// Oldest `occurred_at` in the ledger (null when empty).
  Future<Result<DateTime?>> firstTxnDate() {
    return guardDb('txn.firstTxnDate', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT MIN(occurred_at) AS m FROM txn',
      );
      final Object? m = rows.isEmpty ? null : rows.first['m'];
      return m == null ? null : DateTime.fromMillisecondsSinceEpoch(m as int);
    });
  }

  /// Per-IST-day capture counts split by source, for the gap
  /// detector. The 19,800,000ms shift buckets epoch-ms into IST
  /// days (05:30 IST offset); manual/receipt/voice/pdf rows are
  /// deliberately excluded — the detector hunts CAPTURE gaps, not
  /// user-input gaps.
  Future<Result<List<DaySourceCount>>> countByDaySource({
    required DateTime fromIst,
    required DateTime toIst,
  }) {
    return guardDb('txn.countByDaySource', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT ((occurred_at + 19800000) / 86400000) * 86400000 '
        '- 19800000 AS day_start, '
        'SUM(CASE WHEN source = \'notification\' THEN 1 ELSE 0 END) '
        'AS notif, '
        'SUM(CASE WHEN source = \'sms\' THEN 1 ELSE 0 END) AS sms '
        'FROM txn '
        'WHERE occurred_at >= ? AND occurred_at < ? '
        'AND source IN (\'notification\', \'sms\') '
        'GROUP BY day_start '
        'ORDER BY day_start ASC',
        <Object?>[
          fromIst.millisecondsSinceEpoch,
          toIst.millisecondsSinceEpoch,
        ],
      );
      return rows
          .map(
            (Map<String, Object?> r) => DaySourceCount(
              dayStartMs: r['day_start']! as int,
              notification: r['notif']! as int,
              sms: r['sms']! as int,
            ),
          )
          .toList(growable: false);
    });
  }

  Future<Result<void>> updateCategory(String id, String? categoryId) {
    return guardDb('txn.updateCategory', () async {
      final Database db = await _db;
      await db.update(
        'txn',
        <String, Object?>{'category_id': categoryId},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  Future<Result<void>> updateNote(String id, String? note) {
    return guardDb('txn.updateNote', () async {
      final Database db = await _db;
      await db.update(
        'txn',
        <String, Object?>{'note': note},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  Future<Result<void>> deleteById(String id) {
    return guardDb('txn.deleteById', () async {
      final Database db = await _db;
      await db.delete('txn', where: 'id = ?', whereArgs: <Object?>[id]);
    });
  }

  /// Exact reference lookup — statement-import dedup leg 1. A ref
  /// already in the ledger means that payment is imported/captured,
  /// whatever its fingerprint says.
  Future<Result<bool>> refNoExists(String refNo) {
    return guardDb('txn.refNoExists', () async {
      final Database db = await _db;
      final List<Map<String, Object?>> rows = await db.rawQuery(
        'SELECT 1 FROM txn WHERE ref_no = ? LIMIT 1',
        <Object?>[refNo],
      );
      return rows.isNotEmpty;
    });
  }

  /// Statement-import batch: ALL-or-nothing. The whole file lands in
  /// one transaction — a mid-file failure rolls everything back, so
  /// an import never writes half a statement. Returns the number of
  /// rows actually inserted (dedup-unique index ignores repeats).
  Future<Result<int>> insertAllAtomic(List<Txn> txns) {
    return guardDb('txn.insertAllAtomic', () async {
      final Database db = await _db;
      int written = 0;
      await db.transaction((Transaction executor) async {
        final Batch batch = executor.batch();
        for (final Txn t in txns) {
          batch.insert(
            'txn',
            t.toRow(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        final List<Object?> results = await batch.commit();
        written =
            results.where((Object? r) => (r as int? ?? 0) > 0).length;
      });
      return written;
    });
  }

  // -- WHERE builders (shared by page/count) ---------------------------

  static String _whereFor({
    DateTime? from,
    DateTime? to,
    String? categoryId,
    TxnDirection? direction,
    TxnSource? source,
    String? search,
  }) {
    final List<String> parts = <String>[
      if (from != null) 'occurred_at >= ?',
      if (to != null) 'occurred_at <= ?',
      if (categoryId != null) 'category_id = ?',
      if (direction != null) 'direction = ?',
      if (source != null) 'source = ?',
      if (search != null) "merchant_clean LIKE '%' || ? || '%'",
    ];
    return parts.join(' AND ');
  }

  static List<Object?> _argsFor({
    DateTime? from,
    DateTime? to,
    String? categoryId,
    TxnDirection? direction,
    TxnSource? source,
    String? search,
  }) {
    return <Object?>[
      if (from != null) from.millisecondsSinceEpoch,
      if (to != null) to.millisecondsSinceEpoch,
      if (categoryId != null) categoryId,
      if (direction != null) direction.name,
      if (source != null) source.name,
      if (search != null) search,
    ];
  }
}
