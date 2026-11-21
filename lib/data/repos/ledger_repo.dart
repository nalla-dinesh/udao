// phase-02
// The capture pipeline brain: filter → parse → confidence gate →
// dedup → ledger/review, with a capture_event health row for every
// input no matter the outcome.
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/db/dao/capture_health_dao.dart';
import 'package:udao/data/db/dao/pending_review_dao.dart';
import 'package:udao/data/db/dao/txn_dao.dart';
import 'package:udao/data/db/udao_database.dart';
import 'package:udao/data/models/capture_event.dart';
import 'package:udao/data/models/pending_review_entry.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/dedup_engine.dart';
import 'package:udao/data/parsers/filters.dart';
import 'package:udao/data/parsers/parser_registry.dart';
import 'package:udao/data/parsers/parser_types.dart';
import 'package:udao/data/repos/capture_pipeline_result.dart';

class LedgerRepo {
  LedgerRepo(this._database);

  final UdaoDatabase _database;
  final OtpFilter _otpFilter = OtpFilter();
  final PromoFilter _promoFilter = PromoFilter();

  TxnDao? _txnDao;
  CaptureHealthDao? _captureDao;
  PendingReviewDao? _reviewDao;

  /// DAOs materialise with the first DB open (they only need the
  /// `Future<Database>`, never a live handle).
  Future<(TxnDao, CaptureHealthDao, PendingReviewDao)> _daos() async {
    final Future<Database> db = _database.db;
    return (
      _txnDao ??= TxnDao(db),
      _captureDao ??= CaptureHealthDao(db),
      _reviewDao ??= PendingReviewDao(db),
    );
  }

  /// Opens the DB (and runs migrations) — call once at boot so the
  /// first user action never pays the open cost.
  Future<void> warmUp() async {
    await _database.db;
  }

  /// Full pipeline for one raw capture.
  Future<Result<IngestOutcome>> ingest(ParserInput input) async {
    final (TxnDao txns, CaptureHealthDao health, PendingReviewDao reviews) =
        await _daos();

    // ---- 1. Pre-parser filters (OTP, promo). ----------------------
    final FilterVerdict otp = _otpFilter.check(input);
    if (otp.isDrop) {
      await _recordDrop(health, input, otp.dropReason!);
      return const Err(ParseFailure('otp_security'));
    }
    final FilterVerdict promo = _promoFilter.check(input);
    if (promo.isDrop) {
      await _recordDrop(health, input, promo.dropReason!);
      return const Err(ParseFailure('promo_marketing'));
    }

    // ---- 2. Parser chain. -----------------------------------------
    final Result<ParsedTxn> parsed = runParserChain(input);
    if (parsed is Err<ParsedTxn>) {
      final String code = parsed.failure.message;
      await _recordDrop(health, input, 'no_parser_match');
      return Err(ParseFailure(code));
    }
    final ParsedTxn p = parsed.valueOrNull!;

    // ---- 3. Confidence gate. --------------------------------------
    if (p.confidence < ConfidencePolicy.reviewMin) {
      await _recordDrop(health, input, 'low_confidence');
      return const Err(ParseFailure('low_confidence'));
    }

    // ---- 4. Fingerprint. ------------------------------------------
    final String dedupKey = DedupEngine.fingerprint(
      refNo: p.refNo,
      amountPaise: p.amount.paise,
      counterparty: p.merchantClean,
      at: p.occurredAt,
    );

    // ---- 5. Route. ------------------------------------------------
    if (p.confidence >= ConfidencePolicy.autoAcceptMin) {
      // Cross-source duplicate check BEFORE any write: GPay +
      // bank SMS for the same payment carry different refs (and so
      // different fingerprints) — a near match within 10 minutes is
      // the same money, reported twice.
      final Result<List<Txn>> near = await txns.findNear(
        around: p.occurredAt,
        amountPaise: p.amount.paise,
        merchantClean: p.merchantClean == 'Unknown' ? null : p.merchantClean,
      );
      final bool alreadyNear = near is Ok<List<Txn>> && near.value.isNotEmpty;
      if (alreadyNear) {
        await _record(health, input, p, deduped: true);
        return const Ok(IngestOutcome(status: IngestStatus.duplicate));
      }

      final Txn txn = Txn(
        id: TxnId.newId(),
        amount: p.amount,
        direction: p.direction,
        source: input.packageKey != null ? TxnSource.notification : TxnSource.sms,
        rawText: input.text,
        merchantRaw: p.merchantRaw,
        merchantClean: p.merchantClean,
        bankOrApp: p.bankOrApp,
        occurredAt: p.occurredAt,
        capturedAt: input.receivedAt,
        confidence: p.confidence,
        dedupKey: dedupKey,
      );
      final Result<bool> inserted = await txns.upsertByDedupKey(txn);
      final bool wrote = inserted is Ok<bool> ? inserted.value : false;
      if (wrote) {
        await _record(health, input, p, deduped: false);
        return Ok(
          IngestOutcome(status: IngestStatus.autoAccepted, txnId: txn.id),
        );
      }
      // Insert ignored: an identical fingerprint replay (same
      // bucket) that findNear somehow missed — still a duplicate.
      await _record(health, input, p, deduped: true);
      return const Ok(IngestOutcome(status: IngestStatus.duplicate));
    }

    // ---- 6. Review band. -------------------------------------------
    final PendingReviewEntry entry = PendingReviewEntry(
      id: TxnId.newId(),
      source: input.packageKey != null ? 'notification' : 'sms',
      receivedAt: input.receivedAt,
      rawText: input.text,
      amount: p.amount,
      direction: p.direction,
      merchantRaw: p.merchantRaw,
      merchantClean: p.merchantClean,
      bankOrApp: p.bankOrApp,
      refNo: p.refNo,
      vpa: p.vpa,
      confidence: p.confidence,
      parserId: p.parserId,
      dedupKey: dedupKey,
    );
    final Result<void> queued = await reviews.insert(entry);
    if (queued is Err<void>) {
      return Err(queued.failure);
    }
    await _record(health, input, p, deduped: false);
    return Ok(
      IngestOutcome(status: IngestStatus.pendingReview, reviewEntry: entry),
    );
  }

  // ------------------------------------------------------------------
  // Health-row helpers.
  // ------------------------------------------------------------------

  Future<void> _record(
    CaptureHealthDao health,
    ParserInput input,
    ParsedTxn parsed, {
    required bool deduped,
  }) async {
    await health.insert(
      CaptureEvent(
        id: TxnId.newId(),
        source: input.packageKey != null ? 'notification' : 'sms',
        receivedAt: input.receivedAt,
        parsed: true,
        deduped: deduped,
        confidence: parsed.confidence,
        rawHash: DedupEngine.rawHash(input.text),
        rawText: input.text,
        parserId: parsed.parserId,
      ),
    );
  }

  Future<void> _recordDrop(
    CaptureHealthDao health,
    ParserInput input,
    String reason,
  ) async {
    await health.insert(
      CaptureEvent(
        id: TxnId.newId(),
        source: input.packageKey != null ? 'notification' : 'sms',
        receivedAt: input.receivedAt,
        parsed: false,
        deduped: false,
        confidence: 0,
        rawHash: DedupEngine.rawHash(input.text),
        dropReason: reason,
      ),
    );
  }
}
