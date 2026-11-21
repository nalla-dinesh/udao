// phase-07
// TxnRow — THE transaction row, shared by Aaj and Ledger. Category
// tint comes from a stable merchant hash (same merchant, same color,
// forever), the glyph from the capture source. No raw TextStyle
// literals — everything derives from the theme (audit rule).
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/udao_spacing.dart';
import '../theme/udao_theme_extension.dart';
import '../../data/models/txn.dart';
import '../../core/utils/money.dart';

class TxnRow extends StatelessWidget {
  const TxnRow({required this.txn, this.onTap, super.key});

  final Txn txn;
  final VoidCallback? onTap;

  static const List<Color> _tints = <Color>[
    Color(0xFFFF5A3C), // flame
    Color(0xFFC9F24B), // lime
    Color(0xFFFFC94D), // gold
    Color(0xFF5AC8FA), // sky
    Color(0xFFA78BFA), // violet
  ];

  /// Stable 0..4 from the merchant name — same shop, same tint.
  static int tintIndex(String merchant) {
    int h = 0;
    for (final int c in merchant.codeUnits) {
      h = (h * 31 + c) % 100000;
    }
    return h % _tints.length;
  }

  IconData get _icon {
    switch (txn.source) {
      case TxnSource.sms:
        return PhosphorIconsBold.chatCircleText;
      case TxnSource.notification:
        return PhosphorIconsBold.bellRinging;
      case TxnSource.receipt:
        return PhosphorIconsBold.receipt;
      case TxnSource.voice:
        return PhosphorIconsBold.microphone;
      case TxnSource.pdf:
        return PhosphorIconsBold.fileText;
      case TxnSource.manual:
        return PhosphorIconsBold.pencilSimple;
    }
  }

  String get _merchant {
    final String clean = txn.merchantClean.trim();
    if (clean.isNotEmpty && clean != 'Unknown') {
      return clean;
    }
    final String raw = txn.merchantRaw.trim();
    return raw.isEmpty ? '—' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final UdaoSemantic sem = context.semantic;
    final bool credit = txn.direction == TxnDirection.credit;

    final Color tint = _tints[tintIndex(_merchant)];
    final String hh =
        txn.occurredAt.hour.toString().padLeft(2, '0');
    final String mm =
        txn.occurredAt.minute.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: UdaoSpacing.md,
        vertical: UdaoSpacing.sm,
      ),
      child: InkResponse(
        onTap: onTap,
        radius: UdaoRadius.lg,
        child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.14),
              border: Border.all(color: tint.withValues(alpha: 0.45)),
            ),
            child: Icon(_icon, size: 20, color: tint),
          ),
          const SizedBox(width: UdaoSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$hh:$mm · ${txn.source.name}',
                  maxLines: 1,
                  style: text.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: UdaoSpacing.md),
          Text(
            '${credit ? '+' : '−'}₹${_fmt(txn.amount)}',
            style: text.headlineSmall?.copyWith(
              color: credit ? sem.success : null,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          ],
        ),
      ),
    );
  }

  static String _fmt(Money m) {
    final int r = m.paise ~/ 100;
    final int p = m.paise % 100;
    return p == 0 ? '$r' : '$r.${p.toString().padLeft(2, '0')}';
  }
}
