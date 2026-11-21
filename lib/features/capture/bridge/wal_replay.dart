// phase-03
// WAL replay — the "zero loss" half of the contract.
//
// Flow (app start, after the DB is warm):
//   readWAL() -> run every entry through the pipeline -> ackWAL(maxTs)
//
// Semantics are AT-LEAST-ONCE: if the process dies mid-replay, the
// un-acked tail replays again next start. That is safe because the
// dedup engine absorbs replays (fingerprint + findNear) — this is
// WHY the dedup engine exists, and why the replay never filters.
// Known skew: a crash between "drop recorded" and "ack" re-inserts
// the drop's health row (metrics only, never a double txn).
import 'package:udao/core/log/udao_logger.dart';
import 'package:udao/core/result/result.dart';

import '../pipeline/capture_pipeline.dart';
import 'capture_bridge.dart';
import 'capture_raw_event.dart';

final UdaoLogger _log = udaoLog.child('capture');

/// Replays every pending WAL entry through [pipeline], then acks up
/// to the newest replayed timestamp. Returns the number of entries
/// processed (drops and duplicates included — they were "handled").
Future<Result<int>> replayWal({
  required CaptureBridge bridge,
  required CapturePipeline pipeline,
}) async {
  final Result<List<CaptureRawEvent>> wal = await bridge.readWAL();
  if (wal is Err<List<CaptureRawEvent>>) {
    return Err(wal.failure);
  }
  final List<CaptureRawEvent> events = wal.valueOrNull ?? const <CaptureRawEvent>[];
  if (events.isEmpty) {
    _log.debug('replay: WAL empty');
    return const Ok(0);
  }

  _log.debug('replay: ${events.length} entries');
  int maxTs = 0;
  for (final CaptureRawEvent event in events) {
    // Result ignored on purpose: drops/duplicates are handled outcomes,
    // and the ack must advance past them either way.
    await pipeline.run(event);
    if (event.ts > maxTs) {
      maxTs = event.ts;
    }
  }

  final Result<int> ack = await bridge.ackWAL(maxTs);
  if (ack is Err<int>) {
    _log.warn('replay: ack failed — tail will replay next start (safe)');
  } else {
    _log.debug('replay: acked up to $maxTs, ${ack.valueOrNull ?? 0} survive');
  }
  return Ok(events.length);
}
