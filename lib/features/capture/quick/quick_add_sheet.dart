// phase-04
// QuickAdd — the global FAB sheet with three tabs: Bolo (voice),
// Likho (manual), Bill (receipt). Everything lands in the ledger
// ONLY after an explicit user confirm; nothing here auto-writes.
//
// Manual flow is a ≤3-tap save: type amount (big pad) → category
// pre-selected by merchant autocomplete → Save. Occurred-at is
// today/yesterday (statements/voice carry no time either).
//
// dedup keys for user-entered txns are instance-unique
// (`quick:<id>`): the same reasoning as receipts — there is no bank
// reference to fingerprint, and silently swallowing a user's
// deliberate second entry is worse than a possible duplicate.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/date_utils.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/category.dart';
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
import '../receipt/receipt_capture_sheet.dart';
import 'hinglish_amount_parser.dart';

/// Opens QuickAdd. The Bill tab pops this sheet and hands over to
/// the receipt flow (one sheet at a time).
Future<void> showQuickAddSheet(BuildContext context) {
  return UdaoDialog.show<void>(
    context: context,
    title: AppLocalizations.of(context).quickAddTitle,
    child: const SizedBox(
      // 520: the Likho tab's natural content measures ~431px + ~60px
      // of sheet chrome — 460 clipped the SAVE button under the fold.
      height: 520,
      child: _QuickAddBody(),
    ),
  );
}

class _QuickAddBody extends ConsumerStatefulWidget {
  const _QuickAddBody();

  @override
  ConsumerState<_QuickAddBody> createState() => _QuickAddBodyState();
}

enum _QATab { bolo, likho, bill }

class _QuickAddBodyState extends ConsumerState<_QuickAddBody> {
  _QATab _tab = _QATab.bolo;

  // voice
  bool _listening = false;
  HinglishDraft? _voiceDraft;
  bool _voiceCredit = false;

  // manual
  String _amountText = '';
  final TextEditingController _merchant = TextEditingController();
  String? _categoryId;
  bool _yesterday = false;
  bool _manualCredit = false;
  List<String> _suggestions = <String>[];

  @override
  void dispose() {
    _merchant.dispose();
    super.dispose();
  }

  // ---- shared write -------------------------------------------------

  Future<void> _save({
    required int amountPaise,
    required String merchantText,
    required bool credit,
    required TxnSource source,
    String? categoryId,
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String merchantClean = MerchantCleaner.clean(merchantText);
    final String txnId = TxnId.newId();
    final DateTime occurredAt = _occurredAt();
    final Txn txn = Txn(
      id: txnId,
      amount: Money(amountPaise),
      direction: credit ? TxnDirection.credit : TxnDirection.debit,
      source: source,
      rawText: source == TxnSource.voice ? _lastSpoken ?? '' : '',
      merchantRaw: merchantText,
      merchantClean: merchantClean,
      bankOrApp: source.name,
      categoryId: categoryId,
      occurredAt: occurredAt,
      capturedAt: IstDates.nowIst(),
      // Explicit user confirm = top trust.
      confidence: 0.98,
      dedupKey: DedupEngine.fingerprint(
        refNo: 'quick:$txnId',
        amountPaise: amountPaise,
        counterparty: merchantClean,
        at: occurredAt,
      ),
    );
    final Result<bool> written =
        await ref.read(txnDaoProvider).upsertByDedupKey(txn);
    if (!mounted) {
      return;
    }
    if (written.valueOrNull == true) {
      UdaoSnackBar.show(context, message: l10n.quickAddSaved);
      Navigator.of(context).pop();
    } else {
      UdaoSnackBar.show(context, message: l10n.quickAddSaveFailed);
    }
  }

  DateTime _occurredAt() {
    final DateTime now = IstDates.nowIst();
    final DateTime day =
        _yesterday ? now.subtract(const Duration(days: 1)) : now;
    return DateTime.utc(day.year, day.month, day.day, 6, 30)
        .add(IstDates.istOffset);
  }

  int? _manualPaise() {
    if (_amountText.isEmpty) {
      return null;
    }
    final Money? m = Money.tryParse(_amountText);
    return m == null || m.paise <= 0 ? null : m.paise;
  }

  String? _lastSpoken;

  // ---- Bolo ----------------------------------------------------------

  Future<void> _listen() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _listening = true;
      _voiceDraft = null;
    });
    final Result<String> heard = await ref
        .read(voiceInputProvider)
        .listenOnce(localeId: 'en-IN');
    if (!mounted) {
      return;
    }
    setState(() {
      _listening = false;
    });
    final String? text = heard.valueOrNull;
    if (text == null || text.trim().isEmpty) {
      UdaoSnackBar.show(
        context,
        message: heard.failureOrNull?.message == 'voice_unavailable'
            ? l10n.quickAddVoiceUnavailable
            : l10n.quickAddVoiceHeardNothing,
      );
      return;
    }
    _lastSpoken = text;
    setState(() {
      _voiceDraft = HinglishAmountParser.parse(text);
      _voiceCredit = _voiceDraft!.credit;
      _yesterday = false;
    });
  }

  Widget _boloBody(AppLocalizations l10n) {
    final HinglishDraft? draft = _voiceDraft;
    if (_listening) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(l10n.quickAddListening),
          const SizedBox(height: 16),
          const SkeletonLine(width: 180),
        ],
      );
    }
    if (draft == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(l10n.quickAddBoloBlurb, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          UdaoButton(
            label: l10n.quickAddMicCta,
            size: UdaoButtonSize.lg,
            onTap: _listen,
          ),
        ],
      );
    }
    // The confirm card — "Kya ye sahi hai? ₹125 · Auto".
    final int? paise = draft.amountPaise;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          paise == null
              ? l10n.quickAddVoiceNoAmount
              : l10n.quickAddConfirmQuestion(
                  _rupees(paise),
                  draft.merchantHint ?? '…',
                ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (draft.unknownTail.isNotEmpty)
          Text(
            l10n.quickAddUnknownWords(draft.unknownTail.join(', ')),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (draft.unknownTail.isNotEmpty) const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            ChoiceChip(
              label: Text(
                draft.credit
                    ? l10n.receiptCredit
                    : l10n.receiptDebit,
              ),
              selected: draft.credit,
              onSelected: (bool v) =>
                  setState(() => _voiceCredit = v),
            ),
          ],
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: UdaoButton(
            label: l10n.quickAddSaveCta,
            size: UdaoButtonSize.lg,
            onTap: paise == null
                ? null
                : () => unawaited(
                      _save(
                        amountPaise: paise,
                        merchantText: draft.merchantHint ?? '',
                        credit: _voiceCredit,
                        source: TxnSource.voice,
                        categoryId: draft.categoryId,
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  // ---- Likho ---------------------------------------------------------

  Future<void> _onMerchantChanged(String value) async {
    if (value.trim().length < 2) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = <String>[]);
      }
      return;
    }
    final Result<List<Txn>> page = await ref.read(txnDaoProvider).page(
          limit: 5,
          search: value.trim(),
        );
    if (!mounted) {
      return;
    }
    final List<String> names = (page.valueOrNull ?? <Txn>[])
        .map((Txn t) => t.merchantClean)
        .toSet()
        .toList(growable: false);
    setState(() => _suggestions = names);
  }

  void _pickSuggestion(String name) {
    _merchant.text = name;
    setState(() {
      _suggestions = <String>[];
      _categoryId = Categorizer.assign(name) ?? _categoryId;
    });
  }

  Widget _likhoBody(AppLocalizations l10n) {
    final int? paise = _manualPaise();
    // SAVE is pinned OUTSIDE the scrollable middle: it stays visible
    // and tappable at any sheet height / OS text scale. The middle
    // scrolls instead of overflowing (a single fixed Column here
    // overflowed ~31px and pushed SAVE under the fold).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // The big amount display (tap-free, updates as you
                // type on the pad below).
                Text(
                  _amountText.isEmpty ? '\u20b90' : '\u20b9$_amountText',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                _AmountPad(
                  value: _amountText,
                  onChanged: (String v) => setState(() => _amountText = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _merchant,
                  onChanged: (String v) => unawaited(_onMerchantChanged(v)),
                  decoration:
                      InputDecoration(labelText: l10n.quickAddMerchantLabel),
                ),
                if (_suggestions.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: _suggestions
                        .map(
                          (String s) => ActionChip(
                            label: Text(s),
                            onPressed: () => _pickSuggestion(s),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: <Widget>[
                      for (final Category c in kSeedCategories)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(c.name),
                            selected: _categoryId == c.id,
                            onSelected: (_) =>
                                setState(() => _categoryId = c.id),
                          ),
                        ),
                    ],
                  ),
                ),
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
                    // Credit/Debit stays right-aligned via Expanded +
                    // Align instead of a Spacer: on narrow phones
                    // (~362px of sheet body) the three chips' natural
                    // width overflowed a Spacer Row by ~16px —
                    // Expanded absorbs the slack and can never
                    // overflow.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ChoiceChip(
                          label: Text(
                            _manualCredit
                                ? l10n.receiptCredit
                                : l10n.receiptDebit,
                          ),
                          selected: _manualCredit,
                          onSelected: (bool v) =>
                              setState(() => _manualCredit = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: UdaoButton(
            label: l10n.quickAddSaveCta,
            size: UdaoButtonSize.lg,
            onTap: paise == null
                ? null
                : () => unawaited(
                      _save(
                        amountPaise: paise,
                        merchantText: _merchant.text,
                        credit: _manualCredit,
                        source: TxnSource.manual,
                        categoryId: _categoryId,
                      ),
                    ),
          ),
        ),
      ],
    );
  }

  // ---- Bill ----------------------------------------------------------

  Widget _billBody(AppLocalizations l10n) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(l10n.quickAddBillBlurb, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        UdaoButton(
          label: l10n.quickAddBillCta,
          size: UdaoButtonSize.lg,
          // Nested sheet (not pop-then-push): reusing a context
          // whose route is mid-pop is a deactivated-widget race.
          onTap: () => unawaited(showReceiptCaptureSheet(context)),
        ),
      ],
    );
  }

  String _rupees(int paise) {
    final int r = paise ~/ 100;
    final int p = paise % 100;
    return p == 0 ? '$r' : '$r.${p.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final _QATab t in _QATab.values) ...<Widget>[
              Expanded(
                child: ChoiceChip(
                  label: Text(
                    switch (t) {
                      _QATab.bolo => l10n.quickAddBoloTab,
                      _QATab.likho => l10n.quickAddLikhoTab,
                      _QATab.bill => l10n.quickAddBillTab,
                    },
                  ),
                  selected: _tab == t,
                  onSelected: (_) => setState(() => _tab = t),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: switch (_tab) {
            _QATab.bolo => _boloBody(l10n),
            _QATab.likho => _likhoBody(l10n),
            _QATab.bill => _billBody(l10n),
          },
        ),
      ],
    );
  }
}

/// Big-button numeric pad: digits, dot, backspace — the ≤3-tap
/// manual flow's input surface (no OS keyboard).
class _AmountPad extends StatelessWidget {
  const _AmountPad({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const List<String> _keys = <String>[
    '1', '2', '3',
    '4', '5', '6',
    '7', '8', '9',
    '.', '0', '<',
  ];

  void _tap(String k) {
    if (k == '<') {
      if (value.isNotEmpty) {
        onChanged(value.substring(0, value.length - 1));
      }
      return;
    }
    if (k == '.') {
      if (value.contains('.')) {
        return;
      }
      onChanged(value.isEmpty ? '0.' : '$value.');
      return;
    }
    // Max 2 decimals, 9 chars.
    final int dot = value.indexOf('.');
    if (dot != -1 && value.length - dot > 2) {
      return;
    }
    if (value.length >= 9) {
      return;
    }
    onChanged(value == '0' ? k : value + k);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: GridView.count(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        physics: const NeverScrollableScrollPhysics(),
        children: <Widget>[
          for (final String k in _keys)
            OutlinedButton(
              onPressed: () => _tap(k),
              child: Text(
                k == '<' ? '\u232b' : k,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
        ],
      ),
    );
  }
}
