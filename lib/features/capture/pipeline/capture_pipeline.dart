// phase-03
// The capture orchestrator — one raw notification in, one ledger
// outcome out, plus metrics and a domain event. PURE with respect to
// the platform: everything native is behind the injected
// [CaptureBridge], which this class never touches. That is what makes
// the 40-event e2e test possible without a device.
//
// The heavy lifting (filters -> parse -> confidence gate -> dedup ->
// write -> health row) already lives in Phase-02's LedgerRepo.ingest;
// this layer adds: raw-event adaptation, category assignment, kv
// metrics and the TxnCaptured broadcast.
import 'package:udao/core/log/udao_logger.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/kv_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/parser_types.dart';
import 'package:udao/data/repos/capture_pipeline_result.dart';
import 'package:udao/data/repos/ledger_repo.dart';

import '../bridge/capture_raw_event.dart';
import 'categorizer.dart';
import 'ledger_events.dart';

final UdaoLogger _log = udaoLog.child('capture');

class CapturePipeline {
  CapturePipeline({
    required LedgerRepo repo,
    required TxnDao txnDao,
    required KvDao kvDao,
    required LedgerEvents events,
  })  : _repo = repo,
        _txnDao = txnDao,
        _kv = kvDao,
        _events = events;

  final LedgerRepo _repo;
  final TxnDao _txnDao;
  final KvDao _kv;
  final LedgerEvents _events;

  /// Ingests one raw capture. Idempotent by construction: replays are
  /// absorbed by the dedup engine (fingerprint + findNear), which is
  /// exactly what the WAL's at-least-once delivery needs.
  Future<Result<IngestOutcome>> run(CaptureRawEvent raw) async {
    // SMS events encode the sender in `pkg` (`sms:VM-HDFCBK`); the
    // parsers' contract wants packageKey NULL for SMS (that is what
    // labels the written txn TxnSource.sms, not notification).
    final bool isSms = raw.pkg.startsWith('sms:');
    final ParserInput input = ParserInput(
      text: raw.fullText,
      receivedAt: raw.receivedAt,
      packageKey: isSms ? null : raw.pkg,
      sender: raw.sender,
    );

    final Result<IngestOutcome> outcome = await _repo.ingest(input);

    switch (outcome) {
      case final Ok<IngestOutcome> ok:
        return _onOutcome(ok.value);
      case final Err<IngestOutcome> err:
        // Drop paths (otp_security / promo_marketing / low_confidence /
        // no_parser_match): the health row is already written by the
        // repo; here we only count the reason. No raw text — privacy.
        await _bump('cap_drop_${err.failure.message}');
        return outcome;
    }
  }

  Future<Result<IngestOutcome>> _onOutcome(IngestOutcome value) async {
    switch (value.status) {
      case IngestStatus.autoAccepted:
        await _bump('cap_txn');
        await _categorize(value.txnId);
        return Ok(value);
      case IngestStatus.duplicate:
        await _bump('cap_dup');
        return Ok(value);
      case IngestStatus.pendingReview:
        await _bump('cap_review');
        return Ok(value);
    }
  }

  /// Assigns the alias-map category to a freshly written txn and
  /// emits [TxnCaptured]. Unknown merchants keep a null category
  /// (rendered "Other") and bump the `cat_unknown` counter.
  Future<void> _categorize(String? txnId) async {
    if (txnId == null) {
      return;
    }
    final Result<Txn?> found = await _txnDao.findById(txnId);
    final Txn? txn = found.valueOrNull;
    if (txn == null) {
      _log.warn('categorize: txn vanished before assignment');
      return;
    }
    final String? categoryId = Categorizer.assign(txn.merchantClean);
    if (categoryId == null) {
      await _bump('cat_unknown');
    } else {
      final Result<void> updated = await _txnDao.updateCategory(txnId, categoryId);
      if (updated is Err<void>) {
        _log.warn('categorize: assignment failed');
      }
    }
    _events.emit(
      TxnCaptured(
        txnId: txnId,
        amountPaise: txn.amount.paise,
        merchantClean: txn.merchantClean,
        direction: txn.direction.name,
        confidence: txn.confidence,
        categoryId: categoryId,
      ),
    );
  }

  Future<void> _bump(String key) async {
    final Result<String?> current = await _kv.get(key);
    final int value = int.tryParse(current.valueOrNull ?? '0') ?? 0;
    await _kv.set(key, '${value + 1}');
  }
}
