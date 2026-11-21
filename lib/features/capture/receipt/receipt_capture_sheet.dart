// phase-04
// Receipt capture flow: camera/gallery → offline OCR → rules draft
// → EDITABLE form (always human-confirmed) → ledger write + sealed
// thumbnail in the vault. No spinner anywhere — skeleton blocks
// while OCR runs.
//
// Duplicate handling (honest, no silent skips): receipts carry no
// bank ref, so nothing fingerprint-safe exists to silently dedup
// on. Instead the form warns when the same amount + shop already
// exists that day and the user decides. The written dedupKey is
// instance-unique (`rcpt:<txnId>` prefix) — "add anyway" always
// works, and re-photographing is caught by the warning, not by a
// silent ignore.
//
// Vault delete-with-txn: the txn delete UI lands in Phase 07 —
// ReceiptVault.delete is the contract its call sites will honour.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:udao/core/log/udao_logger.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/data/parsers/dedup_engine.dart';
import 'package:udao/data/parsers/merchant_cleaner.dart';

import '../../../core/ui/skeleton.dart';
import '../../../core/ui/udao_button.dart';
import '../../../core/ui/udao_dialog.dart';
import '../../../core/ui/udao_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../capture_providers.dart' show txnDaoProvider;
import '../pipeline/categorizer.dart';
import '../ports/capture_ports_providers.dart';
import '../ports/receipt_camera.dart';
import 'receipt_parsed.dart';

final UdaoLogger _log = udaoLog.child('receipt');

/// Opens the full receipt flow as a bottom sheet. Returns when the
/// flow ends (saved or dismissed).
Future<void> showReceiptCaptureSheet(BuildContext context) {
  return UdaoDialog.show<void>(
    context: context,
    title: AppLocalizations.of(context).quickAddBillTab,
    child: const SizedBox(
      height: 420,
      child: _ReceiptCaptureBody(),
    ),
  );
}

class _ReceiptCaptureBody extends ConsumerStatefulWidget {
  const _ReceiptCaptureBody();

  @override
  ConsumerState<_ReceiptCaptureBody> createState() =>
      _ReceiptCaptureBodyState();
}

enum _RStage { pick, reading, form, saving }

class _ReceiptCaptureBodyState extends ConsumerState<_ReceiptCaptureBody> {
  _RStage _stage = _RStage.pick;
  String? _imagePath;
  ParsedReceipt? _draft;

  late final TextEditingController _merchant;
  late final TextEditingController _amount;
  bool _credit = false;
  bool _yesterday = false;
  bool? _dupWarned;

  @override
  void initState() {
    super.initState();
    _merchant = TextEditingController();
    _amount = TextEditingController();
  }

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _shoot(ReceiptCamera camera) async {
    final Result<String?> shot = await camera.shoot();
    await _onImage(shot);
  }

  Future<void> _gallery(ReceiptCamera camera) async {
    final Result<String?> picked = await camera.pickFromGallery();
    await _onImage(picked);
  }

  Future<void> _onImage(Result<String?> outcome) async {
    final String? path = outcome.valueOrNull;
    if (!mounted || path == null) {
      return; // cancelled or failed — back to pick
    }
    setState(() {
      _imagePath = path;
      _stage = _RStage.reading;
    });
    final Result<ParsedReceipt> parsed =
        await ref.read(receiptParserProvider).parse(path);
    if (!mounted) {
      return;
    }
    if (parsed is Err<ParsedReceipt>) {
      setState(() {
        _stage = _RStage.pick;
      });
      UdaoSnackBar.show(
        context,
        message: AppLocalizations.of(context).receiptOcrFailed,
      );
      return;
    }
    final ParsedReceipt draft = parsed.valueOrNull!;
    setState(() {
      _draft = draft;
      _merchant.text = draft.merchant ?? '';
      _amount.text = draft.total == null
          ? ''
          : _rupeesText(draft.total!.paise);
      _stage = _RStage.form;
    });
    unawaited(_checkDuplicate());
  }

  /// The honest duplicate warning (see file doc).
  Future<void> _checkDuplicate() async {
    final int? paise = _typedPaise();
    final String merchant = MerchantCleaner.clean(_merchant.text);
    if (paise == null || merchant.isEmpty) {
      return;
    }
    final DateTime when = _occurredAt();
    final Result<List<Txn>> near = await ref
        .read(txnDaoProvider)
        .findNear(
          around: when,
          amountPaise: paise,
          merchantClean: merchant == 'Unknown' ? null : merchant,
          window: const Duration(hours: 24),
        );
    if (!mounted) {
      return;
    }
    if ((near.valueOrNull ?? const <Txn>[]).isNotEmpty) {
      setState(() {
        _dupWarned = true;
      });
    }
  }

  int? _typedPaise() {
    final Money? m = Money.tryParse(_amount.text);
    return m == null || m.paise <= 0 ? null : m.paise;
  }

  DateTime _occurredAt() {
    final DateTime now = IstDates.nowIst();
    final DateTime day =
        _yesterday ? now.subtract(const Duration(days: 1)) : now;
    // Noon IST — the date-granular convention shared with imports.
    return DateTime.utc(day.year, day.month, day.day, 6, 30)
        .add(IstDates.istOffset);
  }

  Future<void> _save() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final int? paise = _typedPaise();
    final String merchant = MerchantCleaner.clean(_merchant.text);
    if (paise == null) {
      UdaoSnackBar.show(context, message: l10n.receiptAmountInvalid);
      return;
    }
    setState(() {
      _stage = _RStage.saving;
    });

    final String txnId = TxnId.newId();
    final DateTime occurredAt = _occurredAt();
    final Txn txn = Txn(
      id: txnId,
      amount: Money(paise),
      direction:
          _credit ? TxnDirection.credit : TxnDirection.debit,
      source: TxnSource.receipt,
      rawText: _draft?.rawText ?? '',
      merchantRaw: _merchant.text,
      merchantClean: merchant,
      bankOrApp: 'receipt',
      categoryId: Categorizer.assign(merchant),
      occurredAt: occurredAt,
      capturedAt: IstDates.nowIst(),
      // Human-confirmed receipt: top capture trust.
      confidence: 0.98,
      dedupKey: DedupEngine.fingerprint(
        // Instance-unique by construction (file doc).
        refNo: 'rcpt:$txnId',
        amountPaise: paise,
        counterparty: merchant,
        at: occurredAt,
      ),
    );

    final Result<bool> written =
        await ref.read(txnDaoProvider).upsertByDedupKey(txn);
    if (!mounted) {
      return;
    }
    if (written.valueOrNull != true) {
      setState(() {
        _stage = _RStage.form;
      });
      UdaoSnackBar.show(context, message: l10n.receiptSaveFailed);
      return;
    }

    // Seal the thumbnail AFTER the ledger row exists; if sealing
    // fails the txn still stands (a missing thumbnail must never
    // eat a confirmed expense).
    if (_imagePath != null) {
      final Result<String> sealed = await ref
          .read(receiptVaultProvider)
          .save(txnId, await File(_imagePath!).readAsBytes());
      if (sealed is Err<String>) {
        _log.warn('vault seal failed: ${sealed.failure.message}');
      }
    }

    if (!mounted) {
      return;
    }
    UdaoSnackBar.show(
      context,
      message: l10n.receiptSaved('\u20b9${_rupeesText(paise)}'),
    );
    Navigator.of(context).pop();
  }

  String _rupeesText(int paise) {
    final int rupees = paise ~/ 100;
    final int rem = paise % 100;
    return rem == 0 ? '$rupees' : '$rupees.${rem.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    switch (_stage) {
      case _RStage.pick:
        return _pickBody(l10n);
      case _RStage.reading:
        return const _OcrSkeleton();
      case _RStage.form:
        return _formBody(l10n);
      case _RStage.saving:
        return const _OcrSkeleton();
    }
  }

  Widget _pickBody(AppLocalizations l10n) {
    final ReceiptCamera camera = ref.read(receiptCameraProvider);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        UdaoButton(
          label: l10n.receiptCameraCta,
          size: UdaoButtonSize.lg,
          onTap: () => unawaited(_shoot(camera)),
        ),
        const SizedBox(height: 12),
        UdaoButton(
          label: l10n.receiptGalleryCta,
          variant: UdaoButtonVariant.glass,
          onTap: () => unawaited(_gallery(camera)),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.receiptOfflineNote,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _formBody(AppLocalizations l10n) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_dupWarned == true) ...<Widget>[
          Text(l10n.receiptDupWarning, style: text.bodySmall),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _merchant,
          decoration: InputDecoration(labelText: l10n.receiptMerchantLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.receiptAmountLabel,
            prefixText: '\u20b9',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            ChoiceChip(
              label: Text(l10n.receiptToday),
              selected: !_yesterday,
              onSelected: (_) => setState(() => _yesterday = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(l10n.receiptYesterday),
              selected: _yesterday,
              onSelected: (_) => setState(() => _yesterday = true),
            ),
            const Spacer(),
            ChoiceChip(
              label: Text(_credit ? l10n.receiptCredit : l10n.receiptDebit),
              selected: _credit,
              onSelected: (bool v) => setState(() => _credit = v),
            ),
          ],
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: UdaoButton(
            label: l10n.receiptConfirmCta,
            size: UdaoButtonSize.lg,
            onTap: _save,
          ),
        ),
      ],
    );
  }
}

class _OcrSkeleton extends StatelessWidget {
  const _OcrSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SkeletonBlock(height: 72),
        SizedBox(height: 12),
        SkeletonLine(width: double.infinity),
        SizedBox(height: 8),
        SkeletonLine(width: 240),
        SizedBox(height: 8),
        SkeletonLine(width: 300),
      ],
    );
  }
}
