// phase-02
// What `LedgerRepo.ingest` decided for one capture.
import 'package:udao/data/models/pending_review_entry.dart';

enum IngestStatus { autoAccepted, pendingReview, duplicate }

class IngestOutcome {
  const IngestOutcome({
    required this.status,
    this.txnId,
    this.reviewEntry,
  });
  final IngestStatus status;

  /// Set when [IngestStatus.autoAccepted] (or the pre-existing txn id
  /// when [IngestStatus.duplicate]).
  final String? txnId;
  final PendingReviewEntry? reviewEntry;
}
