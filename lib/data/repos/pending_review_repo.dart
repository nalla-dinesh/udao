// phase-02
// Review-queue semantics: list pending, approve (→ ledger txn) or
// dismiss (→ resolved, discarded).
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/pending_review_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/pending_review_entry.dart';
import 'package:udao/data/models/txn.dart';

class PendingReviewRepo {
  PendingReviewRepo(this._database);
  final UdaoDatabase _database;

  PendingReviewDao? _reviewDao;
  TxnDao? _txnDao;

  Future<(PendingReviewDao, TxnDao)> _daos() async {
    final Future<Database> db = _database.db;
    return (_reviewDao ??= PendingReviewDao(db), _txnDao ??= TxnDao(db));
  }

  Future<Result<List<PendingReviewEntry>>> pending({
    int limit = 50,
    int offset = 0,
  }) async {
    final (PendingReviewDao reviews, _) = await _daos();
    return reviews.pending(limit: limit, offset: offset);
  }

  Future<Result<int>> pendingCount() async {
    final (PendingReviewDao reviews, _) = await _daos();
    return reviews.pendingCount();
  }

  /// Phase-06: updates an unresolved entry's parse fields (the
  /// LLM-fallback re-read). Entry stays pending — approval remains
  /// a human act, always.
  Future<Result<String>> updateEntry(PendingReviewEntry entry) async {
    final (PendingReviewDao reviews, _) = await _daos();
    final Result<int> updated = await reviews.updateParse(entry);
    if (updated.isErr) {
      return Err<String>(updated.failureOrNull!);
    }
    if ((updated.valueOrNull ?? 0) == 0) {
      return const Err<String>(
        DatabaseFailure('review entry not found or already resolved'),
      );
    }
    return Ok<String>(entry.id);
  }

  /// Approves an entry → converts to a txn row (dedup-keyed, so a
  /// bank SMS for the same payment still won't double-write).
  Future<Result<String>> approve(String entryId) async {
    final (PendingReviewDao reviews, TxnDao txns) = await _daos();

    final Result<List<PendingReviewEntry>> list =
        await reviews.pending(limit: 500);
    if (list is Err<List<PendingReviewEntry>>) {
      return Err(list.failure);
    }
    PendingReviewEntry? entry;
    for (final PendingReviewEntry e in list.valueOrNull!) {
      if (e.id == entryId) {
        entry = e;
        break;
      }
    }
    if (entry == null) {
      return const Err(
        DatabaseFailure('review entry not found or already resolved'),
      );
    }
    if (entry.amount == null || entry.direction == null) {
      return const Err(
        ParseFailure('review entry lacks amount/direction'),
      );
    }

    final Txn txn = Txn(
      id: TxnId.newId(),
      amount: entry.amount!,
      direction: entry.direction!,
      source: entry.source == 'notification'
          ? TxnSource.notification
          : TxnSource.sms,
      rawText: entry.rawText,
      merchantRaw: entry.merchantRaw ?? 'Unknown',
      merchantClean: entry.merchantClean ?? 'Unknown',
      bankOrApp: entry.bankOrApp ?? 'unknown',
      occurredAt: entry.receivedAt,
      capturedAt: entry.receivedAt,
      confidence: entry.confidence,
      dedupKey: entry.dedupKey ??
          'review-${entry.id}',
    );
    final Result<bool> inserted = await txns.upsertByDedupKey(txn);
    if (inserted is Err<bool>) {
      return Err(inserted.failure);
    }
    final Result<void> resolved =
        await reviews.resolve(entryId, 'approved');
    if (resolved is Err<void>) {
      return Err(resolved.failure);
    }
    return Ok(txn.id);
  }

  /// Dismisses an entry — recorded, not deleted (analytics on user
  /// precision per parser).
  Future<Result<void>> dismiss(String entryId) async {
    final (PendingReviewDao reviews, _) = await _daos();
    return reviews.resolve(entryId, 'dismissed');
  }

  /// Housekeeping: delete resolved rows older than [days].
  Future<Result<int>> cleanupResolved({int days = 30}) async {
    final (PendingReviewDao reviews, _) = await _daos();
    final DateTime cutoff = DateTime.now().subtract(Duration(days: days));
    return reviews.deleteResolvedBefore(cutoff);
  }
}
