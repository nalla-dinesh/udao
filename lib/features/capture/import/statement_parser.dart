// phase-04
// Statement text → rows, for the top-5 Indian banks' e-statement PDF
// text extractions. One column ENGINE plus five thin profiles: every
// profile only declares (a) the header signature that detects the
// bank, (b) its date style, (c) narration-level ref patterns and
// debit/credit vocabulary. The engine never GUESSES direction — a
// row it cannot pin goes to the skipped bucket and the review screen
// says so.
//
// Column conventions handled (real-world shapes):
//   HDFC   dd/mm/yy  narr  [ref]  amount  balance
//   SBI    dd-mm-yy  narr  [ref]  amount  balance  DR|CR(balance dir)
//   ICICI  dd-mm-yy  narr  Dr|Cr  amount  balance
//   AXIS   dd-mm-yy  narr  amount  balance  DR|CR(balance dir)
//   KOTAK  dd-mm-yy  narr  amount  D|C  balance
//   (any)  dd-mm-yy  narr  debit  credit  balance   (3-money split,
//                                                    zero column side)
//
// The trailing DR/CR on SBI/Axis marks the BALANCE's sign, NOT the
// txn direction — treating it as the txn direction inverts credits.
// Direction precedence, in order: 3-money split > marker before
// first money (ICICI) > marker between monies (Kotak) > narration
// vocabulary > skipped(direction_unknown).
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/core/utils/money.dart';
import 'package:udao/data/models/txn.dart' show TxnDirection;

import 'statement_row.dart';

class _BankProfile {
  const _BankProfile({
    required this.id,
    required this.detect,
    required this.debitPhrases,
    required this.creditPhrases,
  });

  final String id;

  /// Header signature (matched case-insensitively on the whole doc).
  final RegExp detect;

  /// Narration vocabulary that means money LEFT (UPI/DR, NEFT DR-,
  /// TO TRANSFER, PAYMENT TO, ATM withdrawal, …).
  final List<RegExp> debitPhrases;

  /// Narration vocabulary that means money ARRIVED.
  final List<RegExp> creditPhrases;
}

abstract final class StatementParser {
  /// Shared across banks: UPI/NEFT/IMPS refs inside narrations
  /// (including the SBI-style `UPI/DR/<ref>` segment) and bare
  /// 12-digit UTRs. Order matters (specific first).
  static final List<RegExp> _refPatterns = <RegExp>[
    RegExp(r'(?:UPI|NEFT|IMPS|MMI|P2A|P2M)[/-](?:DR|CR)?[/-]?(\d{6,12})'),
    RegExp(r'\b(\d{12})\b'), // UTR / chq serial
    RegExp(
      r'\bref(?:\.|no)?\s*(?:no\.?\s*)?(\d{6,12})',
      caseSensitive: false,
    ),
  ];

  // RegExp has no const constructor, so the profile table (and the
  // regexes it carries) must be `final`, not `const`.
  static final List<_BankProfile> _profiles = <_BankProfile>[
    _BankProfile(
      id: 'hdfc',
      detect: RegExp(r'hdfc\s+bank', caseSensitive: false),
      debitPhrases: <RegExp>[
        RegExp(r'\bNEFT\s*DR\b', caseSensitive: false),
        RegExp(r'\bUPI/DR\b', caseSensitive: false),
        RegExp(r'\bTO\s+TRANSFER\b', caseSensitive: false),
        RegExp(r'\bPAYMENT\s+TO\b', caseSensitive: false),
        RegExp(r'\bATM\s+WD\b', caseSensitive: false),
        RegExp(r'\bPURCHASE\b', caseSensitive: false),
        RegExp(r'\bUPI[-/]', caseSensitive: false), // generic UPI out (credit vocab outranks)
      ],
      creditPhrases: <RegExp>[
        RegExp(r'\bNEFT\s*CR\b', caseSensitive: false),
        RegExp(r'\bUPI/CR\b', caseSensitive: false),
        RegExp(r'\bBY\s+TRANSFER\b', caseSensitive: false),
        RegExp(r'\bSALARY\b', caseSensitive: false),
        RegExp(
          r'\bINTEREST\s+(?:CREDIT|CAPITALISED)\b',
          caseSensitive: false,
        ),
        RegExp(r'\bRECEIVED\s+FROM\b', caseSensitive: false),
      ],
    ),
    _BankProfile(
      id: 'sbi',
      detect: RegExp(r'state\s+bank\s+of\s+india', caseSensitive: false),
      debitPhrases: <RegExp>[
        RegExp(r'\bTO\s+TRANSFER\b', caseSensitive: false),
        RegExp(r'\bUPI/DR\b', caseSensitive: false),
        RegExp(r'\bATM\s+W\b', caseSensitive: false),
        RegExp(r'\bPOS\b.*\bDEBIT\b', caseSensitive: false),
        RegExp(r'\bUPI[-/]', caseSensitive: false), // generic UPI out (credit vocab outranks)
      ],
      creditPhrases: <RegExp>[
        RegExp(r'\bBY\s+TRANSFER\b', caseSensitive: false),
        RegExp(r'\bUPI/CR\b', caseSensitive: false),
        RegExp(r'\bSALARY\b', caseSensitive: false),
        RegExp(r'\bINTEREST\b', caseSensitive: false),
      ],
    ),
    _BankProfile(
      id: 'icici',
      detect: RegExp(
        r'industrial\s+credit|icici\s+bank',
        caseSensitive: false,
      ),
      debitPhrases: <RegExp>[
        RegExp(r'\bUPI/DR\b', caseSensitive: false),
        RegExp(r'\bPAYMENT\s+TO\b', caseSensitive: false),
        RegExp(r'\bATM\s+WD\b', caseSensitive: false),
        RegExp(r'\bUPI[-/]', caseSensitive: false), // generic UPI out (credit vocab outranks)
      ],
      creditPhrases: <RegExp>[
        RegExp(r'\bUPI/CR\b', caseSensitive: false),
        RegExp(r'\bRECEIVED\s+FROM\b', caseSensitive: false),
        RegExp(r'\bSALARY\b', caseSensitive: false),
        RegExp(r'\bINTEREST\b', caseSensitive: false),
      ],
    ),
    _BankProfile(
      id: 'axis',
      detect: RegExp(r'axis\s+bank', caseSensitive: false),
      debitPhrases: <RegExp>[
        RegExp(r'\bUPI/DR\b', caseSensitive: false),
        RegExp(r'\bPAYMENT\s+TO\b', caseSensitive: false),
        RegExp(r'\bPURCHASE\b', caseSensitive: false),
        RegExp(r'\bUPI[-/]', caseSensitive: false), // generic UPI out (credit vocab outranks)
      ],
      creditPhrases: <RegExp>[
        RegExp(r'\bUPI/CR\b', caseSensitive: false),
        RegExp(r'\bRECEIVED\s+FROM\b', caseSensitive: false),
        RegExp(r'\bSALARY\b', caseSensitive: false),
        RegExp(r'\bINTEREST\b', caseSensitive: false),
      ],
    ),
    _BankProfile(
      id: 'kotak',
      detect: RegExp(r'kotak\s+mahindra\s+bank', caseSensitive: false),
      debitPhrases: <RegExp>[
        RegExp(r'\bUPI/DR\b', caseSensitive: false),
        RegExp(r'\bPAYMENT\s+TO\b', caseSensitive: false),
        RegExp(r'\bATM\s+WD\b', caseSensitive: false),
        RegExp(r'\bUPI[-/]', caseSensitive: false), // generic UPI out (credit vocab outranks)
      ],
      creditPhrases: <RegExp>[
        RegExp(r'\bUPI/CR\b', caseSensitive: false),
        RegExp(r'\bRECEIVED\s+FROM\b', caseSensitive: false),
        RegExp(r'\bSALARY\b', caseSensitive: false),
        RegExp(r'\bINTEREST\s+PAID\b', caseSensitive: false),
      ],
    ),
  ];

  /// Row starter: a leading date, either `dd/mm/yy(yy)` or
  /// `dd-mm-yy(yy)`. Value-date as a second leading date is allowed.
  static final RegExp _dateToken =
      RegExp(r'^(\d{2})([/-])(\d{2})\2(\d{2}|\d{4})$');

  /// Standalone balance-direction markers (NOT txn direction).
  static final RegExp _balanceMarker = RegExp(r'^(DR|CR)$', caseSensitive: false);

  /// ICICI/Kotak txn-direction markers around the amount columns.
  static final RegExp _txnMarker = RegExp(r'^(Dr|Cr|D|C)$', caseSensitive: false);

  /// A money column: `1,23,456.78`, `999.00`, `12,34,567`, `1,200`.
  /// Bare integers WITHOUT decimals are deliberately NOT money —
  /// they are ref/chq columns (a bare-digit branch here once ate
  /// `401234567890` as a three-lakh-rupee debit).
  static final RegExp _moneyToken =
      RegExp(r'^\d{1,3}(?:,\d{2,3})*(?:\.\d{1,2})?$|^\d+\.\d{1,2}$');

  /// Parses extracted statement text. Unknown bank →
  /// `Err(ParseFailure('unknown_statement_bank'))`.
  static Result<StatementParse> parseText(String text) {
    final _BankProfile? profile = _detect(text);
    if (profile == null) {
      return const Err(ParseFailure('unknown_statement_bank'));
    }

    final List<StatementRow> rows = <StatementRow>[];
    final List<SkippedLine> skipped = <SkippedLine>[];

    final List<String> lines = text.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) {
        continue;
      }
      final List<String> cols = _columns(line);
      if (cols.isEmpty) {
        continue; // prose (header/footer) — not a row candidate
      }
      final RegExpMatch? firstDate = _dateToken.firstMatch(cols.first);
      if (firstDate == null) {
        continue; // not a row line
      }
      final DateTime? date = _parseDate(firstDate);
      if (date == null) {
        skipped.add(SkippedLine(i + 1, StatementSkipReason.badDate, line));
        continue;
      }

      final _RowParse? parsed = _parseRow(cols, profile);
      if (parsed == null) {
        continue; // structure not a txn row (column headers etc.)
      }
      if (parsed.skipReason != null) {
        skipped.add(
          SkippedLine(i + 1, parsed.skipReason!, line),
        );
        continue;
      }
      if (parsed.amountPaise <= 0) {
        skipped.add(SkippedLine(i + 1, StatementSkipReason.zeroAmount, line));
        continue;
      }
      rows.add(
        StatementRow(
          date: date,
          narration: parsed.narration,
          amountPaise: parsed.amountPaise,
          direction: parsed.direction!,
          refNo: _refFrom(parsed.narration, parsed.refColumn),
          balancePaise: parsed.balancePaise,
          lineNumber: i + 1,
        ),
      );
    }

    return Ok(
      StatementParse(bankId: profile.id, rows: rows, skipped: skipped),
    );
  }

  static _BankProfile? _detect(String text) {
    // First ~40 lines carry the letterhead; scanning the whole text
    // is fine too (narrations rarely contain another bank's name in
    // the detect form).
    for (final _BankProfile p in _profiles) {
      if (p.detect.hasMatch(text)) {
        return p;
      }
    }
    return null;
  }

  /// Splits on 2+ spaces/tabs (column boundaries); single spaces stay
  /// inside a column (that is where narration lives).
  static List<String> _columns(String line) =>
      <String>[
        for (final String c in line.split(RegExp(r'\s{2,}|\t+')))
          c.trim(),
      ]..removeWhere((String c) => c.isEmpty);

  /// dd/mm|dd-mm, yy or yyyy. Two-digit years are 20xx (Indian
  /// e-statements in print are this century). Statements carry no
  /// time, so rows land at NOON IST — a ±12h dedup window then covers
  /// exactly the calendar day.
  static DateTime? _parseDate(RegExpMatch m) {
    final int day = int.tryParse(m.group(1)!)!;
    final int month = int.tryParse(m.group(3)!)!;
    String year = m.group(4)!;
    if (year.length == 2) {
      year = '20$year';
    }
    final int y = int.tryParse(year)!;
    if (day < 1 || day > 31 || month < 1 || month > 12) {
      return null;
    }
    try {
      return DateTime.utc(y, month, day, 6, 30);
    } on Object {
      return null;
    }
  }

  static _RowParse? _parseRow(List<String> cols, _BankProfile profile) {
    // Leading date(s): txn date, optionally a value date.
    int start = 0;
    if (_dateToken.hasMatch(cols.first)) {
      start = 1;
      if (start < cols.length && _dateToken.hasMatch(cols[start])) {
        start++;
      }
    }
    if (start >= cols.length) {
      return null;
    }

    // Walk from the right: money columns trail the line, with an
    // optional Dr/Cr/D/C marker interleaved (ICICI: `narr Dr amount
    // balance`; Kotak: `narr amount D balance`). Consuming the marker
    // lets the walk CONTINUE to the amount on its other side.
    int idx = cols.length - 1;

    // Trailing balance marker (SBI/Axis): balance's sign, ignored for
    // txn direction (documented above).
    if (idx > start && _balanceMarker.hasMatch(cols[idx])) {
      idx--;
    }

    final List<String> money = <String>[];
    String? marker;
    int? markerIdx;
    while (idx > start) {
      final String c = cols[idx];
      if (_moneyToken.hasMatch(c)) {
        money.insert(0, c);
        idx--;
        continue;
      }
      if (marker == null && money.isNotEmpty && _txnMarker.hasMatch(c)) {
        marker = c;
        markerIdx = idx;
        idx--;
        continue;
      }
      break;
    }
    if (money.isEmpty) {
      return null; // dated line without money — not a txn row
    }

    // Narration boundary: the walk stopped at the first non-money
    // column from the right. Whether that column belongs to the
    // narration depends on what it is:
    //   - a consumed marker → narration ends AT the marker;
    //   - the walk ran down to `start` → narration is that column;
    //   - a date token → value date, narration ends before it;
    //   - anything else → the narration's last (multi-)column.
    int narrEnd;
    if (markerIdx != null) {
      narrEnd = markerIdx;
    } else if (idx == start) {
      narrEnd = start + 1;
    } else if (_dateToken.hasMatch(cols[idx])) {
      narrEnd = idx; // value date between narration and money
    } else {
      narrEnd = idx + 1; // multi-column narration tail
    }

    // An explicit ref column can sit right after the narration
    // (HDFC chq/ref), before any value date.
    String? refColumn;
    if (idx - 1 >= start && _looksLikeRef(cols[idx - 1])) {
      refColumn = cols[idx - 1];
      final int afterRef = idx - 1;
      if (afterRef < narrEnd) {
        narrEnd = afterRef;
      }
    }

    if (narrEnd <= start) {
      return null;
    }
    final String narration =
        cols.sublist(start, narrEnd).join(' ').trim();
    if (narration.isEmpty || _txnMarker.hasMatch(narration)) {
      return null;
    }

    // ---- money semantics --------------------------------------------
    final List<int> paise =
        money.map((String m) => _toPaise(m)).toList(growable: false);
    int amountPaise = 0;
    int? balancePaise;
    TxnDirection? direction;

    if (paise.length >= 3) {
      // debit | credit | balance with one side zero.
      balancePaise = paise.last;
      final int debit = paise[paise.length - 3];
      final int credit = paise[paise.length - 2];
      if (debit == 0 && credit > 0) {
        amountPaise = credit;
        direction = TxnDirection.credit;
      } else if (credit == 0 && debit > 0) {
        amountPaise = debit;
        direction = TxnDirection.debit;
      }
    } else if (paise.length == 2) {
      amountPaise = paise.first;
      balancePaise = paise.last;
      direction = _markerDirection(marker) ??
          _vocabDirection(narration, profile);
    } else {
      amountPaise = paise.first;
      direction = _markerDirection(marker) ??
          _vocabDirection(narration, profile);
    }

    return _RowParse(
      narration: narration,
      refColumn: refColumn,
      amountPaise: amountPaise,
      balancePaise: balancePaise,
      direction: direction,
      skipReason:
          direction == null ? StatementSkipReason.directionUnknown : null,
    );
  }

  static TxnDirection? _markerDirection(String? marker) {
    switch (marker?.toUpperCase()) {
      case 'DR':
      case 'D':
        return TxnDirection.debit;
      case 'CR':
      case 'C':
        return TxnDirection.credit;
    }
    return null;
  }

  static TxnDirection? _vocabDirection(
    String narration,
    _BankProfile profile,
  ) {
    // Credit vocabulary is checked FIRST: the specific markers
    // (`UPI/CR`, `NEFT CR`, SALARY) must outrank the generic
    // `UPI/<digits>` debit phrase below, or a credit narration that
    // merely contains a UPI ref would be read as a debit.
    for (final RegExp re in profile.creditPhrases) {
      if (re.hasMatch(narration)) {
        return TxnDirection.credit;
      }
    }
    for (final RegExp re in profile.debitPhrases) {
      if (re.hasMatch(narration)) {
        return TxnDirection.debit;
      }
    }
    return null;
  }

  static bool _looksLikeRef(String col) =>
      RegExp(r'^\d{6,12}$').hasMatch(col);

  static String? _refFrom(String narration, String? refColumn) {
    if (refColumn != null) {
      return refColumn;
    }
    for (final RegExp re in _refPatterns) {
      final RegExpMatch? m = re.firstMatch(narration);
      if (m != null) {
        return m.group(1);
      }
    }
    return null;
  }

  static int _toPaise(String token) =>
      Money.tryParse(token)?.paise ?? 0;
}

/// Internal per-row parse state.
class _RowParse {
  const _RowParse({
    required this.narration,
    required this.refColumn,
    required this.amountPaise,
    required this.balancePaise,
    required this.direction,
    required this.skipReason,
  });

  final String narration;
  final String? refColumn;
  final int amountPaise;
  final int? balancePaise;
  final TxnDirection? direction;
  final StatementSkipReason? skipReason;
}
