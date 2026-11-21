// phase-04
// The rules-based receipt parser — pure text heuristics over ML Kit
// OCR output, fully unit-testable. Amount: the LARGEST
// currency-marked number on a keyword line (total/amount/payable);
// fallback: the largest currency-marked number anywhere. Merchant:
// first non-numeric line (GSTIN-bearing line backs off to the line
// above it). Date: first plausible dd/mm/yyyy, dd-mm-yyyy,
// yyyy-mm-dd or `dd MMM yyyy`. Items: first lines carrying a label +
// trailing amount.
//
// Confidence rubric (drives the ensemble's model leg):
//   base 0.40 + 0.25 total + 0.20 merchant + 0.10 date
// A clean receipt lands ~0.95; anything without a keyword-anchored
// total stays ≤0.65 → the ensemble escalates (Phase 06's model leg).
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/parsers/merchant_cleaner.dart';

import 'receipt_parsed.dart';

abstract final class ReceiptRulesParser {
  /// Lines whose presence marks a total-ish line.
  static final RegExp _totalKeywords = RegExp(
    r'\b(?:grand\s+total|net\s+payable|total(?:\s+amount)?|amount\s+payable|bill\s+amount|payable|subtotal|sub\s+total)\b',
    caseSensitive: false,
  );

  /// `₹ 1,23,456.78` / `Rs. 999` / `INR 45` / `Rs:250`.
  static final RegExp _markedAmount = RegExp(
    r'(?:₹|rs\.?|inr)\s*(\d{1,3}(?:,\d{2,3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// Bare trailing amount on a keyword line (`TOTAL 250.00`).
  static final RegExp _trailingAmount =
      RegExp(r'(\d{1,3}(?:,\d{2,3})*(?:\.\d{1,2})?)\s*$');

  static final RegExp _gstin = RegExp(
    r'\b\d{2}[A-Z]{5}\d{4}[A-Z]\d[A-Z\d]Z[A-Z\d]\b',
  );

  static final List<RegExp> _dateShapes = <RegExp>[
    RegExp(r'\b(\d{2})[/\-.](\d{2})[/\-.](\d{4})\b'),
    RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b'),
    RegExp(
      r'\b(\d{1,2})[\s-]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[\s-](\d{2,4})\b',
      caseSensitive: false,
    ),
  ];

  /// Mostly-digits lines (invoice numbers, GSTIN, phones, totals).
  /// The digit lookahead is the point: without it this class ate ANY
  /// short all-caps word (`IRCTC`, `SALON`) as noise.
  static final RegExp _mostlyNumeric =
      RegExp(r'^(?=.*\d)[\d\s,.\-/:₹#*A-Z]{0,6}$|^\d{6,}$');

  static ParsedReceipt parse(String ocrText) {
    final List<String> lines = ocrText
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList(growable: false);

    final Money? total = _findTotal(lines);
    final String? merchant = _findMerchant(lines);
    final DateTime? date = _findDate(lines);
    final List<ReceiptLineItem> items = _findItems(lines);

    double confidence = 0.40;
    if (total != null) {
      confidence += 0.25;
    }
    if (merchant != null) {
      confidence += 0.20;
    }
    if (date != null) {
      confidence += 0.10;
    }

    return ParsedReceipt(
      rawText: ocrText,
      confidence: confidence.clamp(0.0, 1.0),
      merchant: merchant,
      total: total,
      date: date,
      items: items,
    );
  }

  // ---- total --------------------------------------------------------

  static Money? _findTotal(List<String> lines) {
    // Pass 1: keyword lines — largest currency-marked amount there.
    Money? best;
    for (final String line in lines) {
      if (!_totalKeywords.hasMatch(line)) {
        continue;
      }
      for (final RegExpMatch m in _markedAmount.allMatches(line)) {
        final Money? v = Money.tryParse(m.group(1)!);
        if (v != null && (best == null || v.paise > best.paise)) {
          best = v;
        }
      }
      // `TOTAL 250.00` (no currency mark on receipts that print a
      // ₹ header only).
      if (best == null) {
        final RegExpMatch? t = _trailingAmount.firstMatch(line);
        if (t != null) {
          best = Money.tryParse(t.group(1)!);
        }
      }
    }
    if (best != null) {
      return best;
    }
    // Pass 2: largest currency-marked amount anywhere in the text.
    for (final RegExpMatch m in _markedAmount.allMatches(lines.join('\n'))) {
      final Money? v = Money.tryParse(m.group(1)!);
      if (v != null && (best == null || v.paise > best.paise)) {
        best = v;
      }
    }
    return best;
  }

  // ---- merchant -----------------------------------------------------

  static String? _findMerchant(List<String> lines) {
    int gstinIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (_gstin.hasMatch(lines[i])) {
        gstinIndex = i;
        break;
      }
    }
    if (gstinIndex > 0) {
      // GSTIN receipts put the legal/shop name ABOVE the GSTIN line,
      // sometimes with an address between. A KNOWN alias wins over
      // the address line sitting right on top of the GSTIN.
      for (int i = gstinIndex - 1; i >= 0 && i >= gstinIndex - 3; i--) {
        final String? alias = MerchantCleaner.aliasOf(lines[i]);
        if (alias != null) {
          return alias;
        }
      }
      final String? above = _merchantCandidate(lines[gstinIndex - 1]);
      if (above != null) {
        return above;
      }
    }
    for (final String line in lines) {
      final String? c = _merchantCandidate(line);
      if (c != null) {
        return c;
      }
    }
    return null;
  }

  static String? _merchantCandidate(String line) {
    if (line.length < 3 || _mostlyNumeric.hasMatch(line)) {
      return null;
    }
    final int letters =
        line.replaceAll(RegExp(r'[^A-Za-z]'), '').length;
    if (letters < 3) {
      return null;
    }
    // Keyword lines are not the shop's name.
    if (_totalKeywords.hasMatch(line) ||
        RegExp(
          r'\b(?:invoice|receipt|bill|tax|gstin|date|phone|tel|order|table|token|cashier|cash|card|upi|no\.?)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
      return null;
    }
    return MerchantCleaner.clean(line);
  }

  // ---- date ---------------------------------------------------------

  static DateTime? _findDate(List<String> lines) {
    const List<String> months = <String>[
      'jan', 'feb', 'mar', 'apr', 'may', 'jun',
      'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
    ];
    for (final String line in lines) {
      for (int shape = 0; shape < _dateShapes.length; shape++) {
        final RegExpMatch? m = _dateShapes[shape].firstMatch(line);
        if (m == null) {
          continue;
        }
        int? day;
        int? month;
        int? year;
        if (shape == 0) {
          day = int.tryParse(m.group(1)!);
          month = int.tryParse(m.group(2)!);
          year = int.tryParse(m.group(3)!);
        } else if (shape == 1) {
          year = int.tryParse(m.group(1)!);
          month = int.tryParse(m.group(2)!);
          day = int.tryParse(m.group(3)!);
        } else {
          day = int.tryParse(m.group(1)!);
          month = months.indexOf(m.group(2)!.toLowerCase().substring(0, 3)) + 1;
          year = int.tryParse(m.group(3)!);
          if (year != null && year < 100) {
            year = 2000 + year;
          }
        }
        if (day == null || month == null || year == null) {
          continue;
        }
        if (year < 2020 || year > 2035 || month < 1 || month > 12 ||
            day < 1 || day > 31) {
          continue;
        }
        try {
          return DateTime.utc(year, month, day, 6, 30);
        } on Object {
          continue;
        }
      }
    }
    return null;
  }

  // ---- items ---------------------------------------------------------

  static List<ReceiptLineItem> _findItems(List<String> lines) {
    final List<ReceiptLineItem> out = <ReceiptLineItem>[];
    for (final String line in lines) {
      if (out.length == 3) {
        break;
      }
      if (_totalKeywords.hasMatch(line) || _gstin.hasMatch(line)) {
        continue;
      }
      // Timestamps are not items: `12-06-2026 18:42` would otherwise
      // donate its trailing `42`.
      if (_dateShapes.any((RegExp r) => r.hasMatch(line))) {
        continue;
      }
      final RegExpMatch? m = _trailingAmount.firstMatch(line);
      if (m == null) {
        continue;
      }
      final String label = line.substring(0, m.start).trim();
      if (label.length < 2) {
        continue;
      }
      out.add(ReceiptLineItem(label, Money.tryParse(m.group(1)!)));
    }
    return out;
  }
}
