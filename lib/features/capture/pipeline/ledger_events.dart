// phase-03
// Domain events out of the ledger. Features that react to money
// moving (roast micro-triggers, verdicts, subscription detection)
// subscribe to this broadcast stream instead of poking the DB or the
// pipeline. One event per AUTO-ACCEPTED txn — duplicates and drops
// stay internal (they are health metrics, not domain facts).
import 'dart:async';

class TxnCaptured {
  const TxnCaptured({
    required this.txnId,
    required this.amountPaise,
    required this.merchantClean,
    required this.direction,
    required this.confidence,
    required this.categoryId,
  });

  final String txnId;
  final int amountPaise;
  final String merchantClean;

  /// `'debit'` / `'credit'` (string form of TxnDirection).
  final String direction;

  final double confidence;

  /// Assigned category id; null = "Other" (unknown merchant).
  final String? categoryId;
}

class LedgerEvents {
  final StreamController<TxnCaptured> _controller =
      StreamController<TxnCaptured>.broadcast();

  /// Broadcast stream — safe for many listeners, no replay buffer.
  Stream<TxnCaptured> get stream => _controller.stream;

  bool get hasListener => _controller.hasListener;

  void emit(TxnCaptured event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  /// Called when the owning provider is disposed.
  void dispose() {
    _controller.close();
  }
}
