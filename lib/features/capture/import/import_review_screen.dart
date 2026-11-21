// phase-04
// Statement import review: pick (PDF / CSV) → parse (skeleton, never
// a spinner) → summary card + honest skipped bucket → ONE confirm
// that writes the whole file atomically or nothing at all.
//
// Password handling: the password lives only in the sheet's
// TextEditingController while the user types and crosses to the
// extractor as a call argument; it is cleared the moment the flow
// ends (success, cancel, failure) and never logged.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/models/txn.dart' show TxnDirection;

import '../../../core/ui/section_header.dart';
import '../../../core/ui/skeleton.dart';
import '../../../core/ui/udao_button.dart';
import '../../../core/ui/udao_card.dart';
import '../../../core/ui/udao_dialog.dart';
import '../../../core/ui/udao_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../ports/capture_ports_providers.dart';
import '../ports/statement_source.dart';
import 'statement_import_service.dart';
import 'statement_row.dart';

class ImportReviewScreen extends ConsumerStatefulWidget {
  const ImportReviewScreen({super.key});

  @override
  ConsumerState<ImportReviewScreen> createState() =>
      _ImportReviewScreenState();
}

enum _Stage { idle, parsing, preview, writing, done }

class _ImportReviewScreenState extends ConsumerState<ImportReviewScreen> {
  _Stage _stage = _Stage.idle;
  ImportFormat _format = ImportFormat.pdf;

  ImportPreview? _preview;
  String? _pickedPath;
  String? _pickedName;
  String? _failure;

  /// Password-sheet input. State-owned on purpose: disposing a local
  /// right after `UdaoDialog.show` returns races the sheet's exit
  /// animation (the still-mounted TextField rebuilds against a
  /// disposed controller). The VALUE is zeroed on both exits; the
  /// controller itself dies with the State.
  late final TextEditingController _pwController = TextEditingController();

  @override
  void dispose() {
    _pwController.dispose();
    super.dispose();
  }

  StatementImportService get _service =>
      ref.read(statementImportServiceProvider);

  Future<void> _pick() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Result<PickedStatement?> picked = await ref
        .read(statementSourceProvider)
        .pick(
          _format == ImportFormat.pdf
              ? StatementFormat.pdf
              : StatementFormat.csv,
        );
    if (!mounted) {
      return;
    }
    final PickedStatement? file = picked.valueOrNull;
    if (picked is Err<PickedStatement?> || file == null) {
      if (picked is Err<PickedStatement?>) {
        setState(() {
          _failure = l10n.importPickFailed;
        });
      }
      return; // user cancelled — stay idle, no toast
    }
    _pickedPath = file.path;
    _pickedName = file.displayName;
    await _parse();
  }

  Future<void> _parse({String? password}) async {
    setState(() {
      _stage = _Stage.parsing;
      _failure = null;
    });
    final Result<ImportPreview> preview = _format == ImportFormat.pdf
        ? await _service.previewPdf(
            _pickedPath!,
            _pickedName!,
            extractor: ref.read(pdfTextExtractorProvider),
            password: password,
          )
        : await _service.previewCsv(_pickedPath!, _pickedName!);
    if (!mounted) {
      return;
    }
    if (preview is Err<ImportPreview>) {
      if (preview.failure.message == 'pdf_password') {
        setState(() {
          _stage = _Stage.idle;
        });
        await _askPassword();
        return;
      }
      setState(() {
        _stage = _Stage.idle;
        _failure = _failureCopy(preview.failure.message);
      });
      return;
    }
    setState(() {
      _preview = preview.valueOrNull!;
      _stage = _Stage.preview;
    });
  }

  Future<void> _askPassword() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // UdaoDialog's CTA pops the sheet itself before invoking onCta,
    // so the callback starts the parse (no second pop, no return
    // value through the navigator). The controller is State-owned —
    // see its field comment — and the value is zeroed on BOTH exits.
    await UdaoDialog.show<void>(
      context: context,
      title: l10n.importPasswordTitle,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: TextField(
          controller: _pwController,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(hintText: l10n.importPasswordHint),
        ),
      ),
      ctaLabel: l10n.importPasswordOpen,
      onCta: () {
        final String password = _pwController.text;
        // Zeroize: the value dies with this frame.
        _pwController.clear();
        if (password.isNotEmpty) {
          unawaited(_parse(password: password));
        }
      },
    );
    // Dismissed without CTA — zeroize here too.
    _pwController.clear();
  }

  String _failureCopy(String code) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    switch (code) {
      case 'unknown_statement_bank':
        return l10n.importErrUnsupportedBank;
      case 'unknown_csv_format':
        return l10n.importErrUnsupportedCsv;
      case 'pdf_open_failed':
        return l10n.importErrPdfOpen;
      case 'csv_read_failed':
        return l10n.importErrCsvRead;
      default:
        return l10n.importErrGeneric;
    }
  }

  Future<void> _confirm() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _stage = _Stage.writing;
    });
    final Result<ImportSummary> summary =
        await _service.confirm(_preview!);
    if (!mounted) {
      return;
    }
    final ImportSummary? value = summary.valueOrNull;
    setState(() {
      _stage = _Stage.done;
      _preview = null;
      _pickedPath = null;
      _pickedName = null;
    });
    if (value != null) {
      UdaoSnackBar.show(
        context,
        message: l10n.importDoneSummary(
          value.inserted,
          value.duplicates,
        ),
      );
    } else {
      setState(() {
        _failure = l10n.importErrWrite;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _formatTabs(l10n),
          const SizedBox(height: 16),
          if (_failure != null) ...<Widget>[
            Text(_failure!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
          ],
          switch (_stage) {
            _Stage.idle || _Stage.done => _idleBody(l10n),
            _Stage.parsing => _parsingBody(),
            _Stage.preview => _previewBody(l10n),
            _Stage.writing => _parsingBody(),
          },
        ],
      ),
    );
  }

  Widget _formatTabs(AppLocalizations l10n) {
    return Row(
      children: <Widget>[
        Expanded(
          child: UdaoButton(
            label: 'PDF',
            variant: _format == ImportFormat.pdf
                ? UdaoButtonVariant.flameFilled
                : UdaoButtonVariant.glass,
            onTap: _stage == _Stage.idle
                ? () => setState(() => _format = ImportFormat.pdf)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: UdaoButton(
            label: 'CSV',
            variant: _format == ImportFormat.csv
                ? UdaoButtonVariant.flameFilled
                : UdaoButtonVariant.glass,
            onTap: _stage == _Stage.idle
                ? () => setState(() => _format = ImportFormat.csv)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _idleBody(AppLocalizations l10n) {
    return UdaoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _format == ImportFormat.pdf
                ? l10n.importPdfBlurb
                : l10n.importCsvBlurb,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          UdaoButton(
            label: l10n.importPickCta,
            size: UdaoButtonSize.lg,
            onTap: _pick,
          ),
        ],
      ),
    );
  }

  /// Skeleton parse state — no spinners anywhere in UDAO.
  Widget _parsingBody() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SkeletonBlock(height: 96),
        SizedBox(height: 12),
        SkeletonLine(width: double.infinity),
        SizedBox(height: 8),
        SkeletonLine(width: 280),
        SizedBox(height: 8),
        SkeletonLine(width: 320),
      ],
    );
  }

  Widget _previewBody(AppLocalizations l10n) {
    final ImportPreview preview = _preview!;
    final (DateTime?, DateTime)? range = preview.dateRange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        UdaoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                preview.fileName,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                range == null
                    ? preview.bankId
                    : '${preview.bankId} · '
                        '${_shortDate(range.$1!)} – ${_shortDate(range.$2)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  _stat(l10n.importStatNew, '${preview.newCount}'),
                  _stat(l10n.importStatDup, '${preview.duplicateCount}'),
                  _stat(l10n.importStatSkipped, '${preview.skipped.length}'),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.importDupExplainer,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        UdaoButton(
          label: l10n.importConfirmCta(
            preview.newCount,
          ),
          size: UdaoButtonSize.lg,
          onTap: preview.newCount > 0 && _stage == _Stage.preview
              ? _confirm
              : null,
        ),
        const SizedBox(height: 24),
        SectionHeader(label: l10n.importRowsHeader),
        ..._rowLines(preview),
        if (preview.skipped.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          SectionHeader(label: l10n.importSkippedHeader),
          ...preview.skipped.map(
            (SkippedLine s) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${s.reason.code} · ${s.text}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _dupCopy(DupReason reason) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    switch (reason) {
      case DupReason.inSet:
        return l10n.importDupInSet;
      case DupReason.refNo:
        return l10n.importDupRef;
      case DupReason.fingerprint:
        return l10n.importDupFingerprint;
      case DupReason.fuzzy:
        return l10n.importDupFuzzy;
    }
  }

  List<Widget> _rowLines(ImportPreview preview) {
    final TextTheme text = Theme.of(context).textTheme;
    return preview.rows.map((ImportPreviewRow r) {
      final int rupees = r.txn.amount.paise ~/ 100;
      final String dir =
          r.txn.direction == TxnDirection.credit ? '+' : '\u2212';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    r.txn.merchantClean,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                  Text(
                    _shortDate(r.txn.occurredAt) +
                        (r.dupReason == null
                            ? ''
                            : ' · ${_dupCopy(r.dupReason!)}'),
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              '$dir\u20b9$rupees',
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _stat(String label, String value) {
    final TextTheme text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value, style: text.titleLarge),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
  }

  String _shortDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year % 100}';
}
