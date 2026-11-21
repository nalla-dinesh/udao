// phase-04
// In-memory TxnDao for WIDGET tests.
//
// Why not the real FFI DB here: sqflite's query pipeline contains
// zero-delay timers internally; inside testWidgets' fake-async zone
// those timers only fire while the clock is being pumped. A bare
// `await dao.count()` in a test body therefore deadlocks (nothing
// pumps), and widget-internal chains advance one timer-hop per pump —
// slow and budget-dependent. Real DB semantics (dedup legs, atomic
// batches, SQL filters) are fully covered by the plain DAO and
// statement-import service tests; the widget tests exercise the UI
// FLOW, which this fake serves with pure microtask futures that
// settle under any pump.
//
// Anything not explicitly implemented below fails LOUDLY via
// noSuchMethod — a widget flow that starts calling an unfaked query
// fails the test immediately instead of hanging.
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/models/txn.dart';

class FakeTxnDao implements TxnDao {
  /// Everything "written" so far, in insert order.
  final List<Txn> rows = <Txn>[];

  @override
  Future<Result<bool>> upsertByDedupKey(Txn txn) async {
    final bool fresh = !rows.any((Txn t) => t.dedupKey == txn.dedupKey);
    if (fresh) {
      rows.add(txn);
    }
    return Ok(fresh);
  }

  @override
  Future<Result<bool>> refNoExists(String refNo) async {
    return Ok(rows.any((Txn t) => t.refNo == refNo));
  }

  @override
  Future<Result<Txn?>> findByDedupKey(String dedupKey) async {
    for (final Txn t in rows) {
      if (t.dedupKey == dedupKey) {
        return Ok(t);
      }
    }
    return const Ok<Txn?>(null);
  }

  @override
  Future<Result<List<Txn>>> findNear({
    required DateTime around,
    required int amountPaise,
    String? merchantClean,
    Duration window = const Duration(minutes: 10),
  }) async {
    return Ok<List<Txn>>(
      rows
          .where(
            (Txn t) =>
                t.amount.paise == amountPaise &&
                !t.occurredAt.isBefore(around.subtract(window)) &&
                !t.occurredAt.isAfter(around.add(window)) &&
                (merchantClean == null || t.merchantClean == merchantClean),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<Result<int>> insertAllAtomic(List<Txn> txns) async {
    rows.addAll(txns);
    return Ok<int>(txns.length);
  }

  @override
  Future<Result<int>> count({
    DateTime? from,
    DateTime? to,
    String? categoryId,
    TxnDirection? direction,
    TxnSource? source,
    String? search,
  }) async {
    return Ok<int>(rows.length);
  }

  @override
  Future<Result<List<Txn>>> page({
    int limit = 50,
    int offset = 0,
    DateTime? from,
    DateTime? to,
    String? categoryId,
    TxnDirection? direction,
    TxnSource? source,
    String? search,
  }) async {
    final List<Txn> sorted = <Txn>[...rows]
      ..sort((Txn a, Txn b) => b.occurredAt.compareTo(a.occurredAt));
    return Ok<List<Txn>>(
      sorted.skip(offset).take(limit).toList(growable: false),
    );
  }

  // Un-exercised members (sums, category edits, deletes, day-source
  // buckets, …) hit this and fail the test with a clear message.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        'FakeTxnDao.${invocation.memberName} is not implemented — '
        'implement it if a widget flow needs it.',
      );
}
