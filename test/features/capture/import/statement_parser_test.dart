// phase-04
// Statement text → rows, per bank profile, against synthetic
// extracted-text fixtures (real PDFs are the local-verify job). The
// fixtures mirror the column conventions documented in the parser:
// HDFC dashed dates + trailing ref column, SBI trailing balance
// marker, ICICI pre-amount Dr/Cr, Axis trailing DR/CR, Kotak D/C
// between the monies, and the 3-money debit/credit split.
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/result/result.dart';
import 'package:udao/data/models/txn.dart';
import 'package:udao/features/capture/import/statement_parser.dart';
import 'package:udao/features/capture/import/statement_row.dart';

const String hdfcText = '''
HDFC BANK LIMITED
Statement of account  01/06/26 to 30/06/26
Account No: 50100123456767    IFSC: HDFC0000123

Date        Narration                                        Chq./Ref.No.    Value Dt    Withdrawal    Deposit    Balance

01/06/26    UPI/401234567890/SWIGGY/YESB0PTX                 401234567890    01/06/26    349.00                    45,678.90
02/06/26    NEFT CR-HDFC0000123-ACME CORP-SALARY             123456789012    02/06/26                 65,000.00    1,10,678.90
03/06/26    ATM WD 400123 MAIN BR                            567890123456    03/06/26    2,000.00                   1,08,678.90

Statement generated 30/06/26
''';

const String sbiText = '''
STATE BANK OF INDIA
Statement 01-06-2026 to 30-06-2026

01-06-2025  TO TRANSFER-UPI/DR/401234567890/SWIGGY/PAYTM      01-06-2025    349.00    45,678.00    DR
02-06-2025  BY TRANSFER-UPI/CR/512345678901/ACME/SALARY       02-06-2025    65,000.00    1,10,678.00    CR
03-06-2025  POS 523456XXXXXX DEBIT                            03-06-2025    1,200.00    1,09,478.00    DR
''';

const String iciciText = '''
ICICI Bank Limited
Statement of Transactions

01-06-2026    UPI-401234567890-SWIGGY-ICIC       Dr    349.00    45,678.90
02-06-2026    UPI-512345678901-ACME-SALARY       Cr    65,000.00    1,10,678.90
03-06-2026    ATM WD 123456 MG ROAD              Dr    2,000.00    1,08,678.90
''';

const String axisText = '''
AXIS BANK
Statement of Account

01-06-2026    UPI/P2M/401234567890/SWIGGY/ICIC        349.00    45,678.90    DR
02-06-2026    NEFT CR-ACME CORP-SALARY                65,000.00    1,10,678.90    CR
''';

const String kotakText = '''
KOTAK MAHINDRA BANK
Account Statement

01-06-2026    UPI-401234567890-SWIGGY-AXIS            349.00    D    45,678.90
02-06-2026    NEFT CR-ACME CORP-SALARY                65,000.00    C    1,10,678.90
''';

const String threeMoneyText = '''
STATE BANK OF INDIA
Hinjewadi branch
01-06-2026    UPI/DR/401234567890/SWIGGY/PAYTM         349.00    0.00    45,678.00
02-06-2026    UPI/CR/512345678901/ACME/PAYTM           0.00    65,000.00    1,10,678.00
''';

void main() {
  test('unknown bank is an honest error', () {
    final Result<StatementParse> r =
        StatementParser.parseText('Some random PDF text\nabout nothing');
    expect(r, isA<Err<StatementParse>>());
    expect(
      (r as Err<StatementParse>).failure.message,
      'unknown_statement_bank',
    );
  });

  test('HDFC: dashed dates, ref column, 2-money rows', () {
    final StatementParse p = StatementParser.parseText(hdfcText).valueOrNull!;
    expect(p.bankId, 'hdfc');
    expect(p.rows, hasLength(3));
    expect(p.rows[0].amountPaise, 34900);
    expect(p.rows[0].direction, TxnDirection.debit);
    expect(p.rows[0].refNo, '401234567890');
    expect(p.rows[0].balancePaise, 4567890);
    expect(p.rows[0].date.month, 6);
    expect(p.rows[1].amountPaise, 6500000);
    expect(p.rows[1].direction, TxnDirection.credit);
    expect(p.rows[2].amountPaise, 200000);
  });

  test('SBI: trailing DR/CR is the BALANCE marker, not direction', () {
    final StatementParse p = StatementParser.parseText(sbiText).valueOrNull!;
    expect(p.bankId, 'sbi');
    expect(p.rows, hasLength(3));
    // The DR after the balance must NOT invert the credit.
    expect(p.rows[1].amountPaise, 6500000);
    expect(p.rows[1].direction, TxnDirection.credit);
    expect(p.rows[0].direction, TxnDirection.debit);
    expect(p.rows[2].direction, TxnDirection.debit);
  });

  test('ICICI: Dr/Cr before the amount sets direction', () {
    final StatementParse p = StatementParser.parseText(iciciText).valueOrNull!;
    expect(p.bankId, 'icici');
    expect(p.rows, hasLength(3));
    expect(p.rows[0].direction, TxnDirection.debit);
    expect(p.rows[1].direction, TxnDirection.credit);
    expect(p.rows[2].direction, TxnDirection.debit);
    expect(p.rows[1].amountPaise, 6500000);
  });

  test('Axis: trailing DR/CR consumed as balance marker', () {
    final StatementParse p = StatementParser.parseText(axisText).valueOrNull!;
    expect(p.bankId, 'axis');
    expect(p.rows, hasLength(2));
    expect(p.rows[0].direction, TxnDirection.debit);
    expect(p.rows[1].direction, TxnDirection.credit);
  });

  test('Kotak: D/C between the monies sets direction', () {
    final StatementParse p = StatementParser.parseText(kotakText).valueOrNull!;
    expect(p.bankId, 'kotak');
    expect(p.rows, hasLength(2));
    expect(p.rows[0].direction, TxnDirection.debit);
    expect(p.rows[1].direction, TxnDirection.credit);
    expect(p.rows[1].amountPaise, 6500000);
  });

  test('3-money split: zero column side picks the direction', () {
    final StatementParse p =
        StatementParser.parseText(threeMoneyText).valueOrNull!;
    expect(p.rows, hasLength(2));
    expect(p.rows[0].direction, TxnDirection.debit);
    expect(p.rows[1].direction, TxnDirection.credit);
    expect(p.rows[0].amountPaise, 34900);
  });

  test('narration refs are extracted when no ref column exists', () {
    final StatementParse p = StatementParser.parseText(iciciText).valueOrNull!;
    expect(p.rows[0].refNo, '401234567890');
  });

  test('directionless rows land in the skipped bucket, never guessed', () {
    const String ambiguous = '''
HDFC BANK
01/06/26    SOME OPAQUE NARRATION      500.00    12,000.00
''';
    final StatementParse p =
        StatementParser.parseText(ambiguous).valueOrNull!;
    expect(p.rows, isEmpty);
    expect(p.skipped, hasLength(1));
    expect(p.skipped.first.reason, StatementSkipReason.directionUnknown);
  });

  test('date range spans oldest..newest', () {
    final StatementParse p = StatementParser.parseText(hdfcText).valueOrNull!;
    final (DateTime?, DateTime)? range = p.dateRange;
    expect(range, isNotNull);
    expect(range!.$1!.day, 1);
    expect(range.$2.day, 3);
  });
}
