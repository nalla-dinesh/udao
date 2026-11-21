// phase-02
import 'package:flutter_test/flutter_test.dart';
import 'package:udao/data/parsers/dedup_engine.dart';

void main() {
  // 18:40:00Z sits exactly on a 10-minute bucket edge (and is
  // UTC, so the test is timezone-proof): +9m59s stays inside the
  // same bucket, +10m crosses into the next.
  final DateTime t = DateTime.utc(2026, 10, 27, 18, 40);

  group('DedupEngine.fingerprint', () {
    test('identical inputs collide', () {
      expect(
        DedupEngine.fingerprint(
          refNo: '512345678901',
          amountPaise: 14800,
          counterparty: 'Swiggy',
          at: t,
        ),
        DedupEngine.fingerprint(
          refNo: '512345678901',
          amountPaise: 14800,
          counterparty: 'Swiggy',
          at: t,
        ),
      );
    });

    test('same 10-minute bucket collides', () {
      expect(
        DedupEngine.fingerprint(
          refNo: '512345678901',
          amountPaise: 14800,
          counterparty: 'Swiggy',
          at: t,
        ),
        DedupEngine.fingerprint(
          refNo: '512345678901',
          amountPaise: 14800,
          counterparty: 'Swiggy',
          at: t.add(const Duration(minutes: 9, seconds: 59)),
        ),
      );
    });

    test('different buckets do not collide', () {
      expect(
        DedupEngine.fingerprint(
          refNo: '512345678901',
          amountPaise: 14800,
          counterparty: 'Swiggy',
          at: t,
        ),
        isNot(
          DedupEngine.fingerprint(
            refNo: '512345678901',
            amountPaise: 14800,
            counterparty: 'Swiggy',
            at: t.add(const Duration(minutes: 10)),
          ),
        ),
      );
    });

    test('amount difference changes the key', () {
      expect(
        DedupEngine.fingerprint(
          refNo: 'r',
          amountPaise: 100,
          counterparty: 'X',
          at: t,
        ),
        isNot(
          DedupEngine.fingerprint(
            refNo: 'r',
            amountPaise: 101,
            counterparty: 'X',
            at: t,
          ),
        ),
      );
    });

    test('counterparty difference changes the key', () {
      expect(
        DedupEngine.fingerprint(
          refNo: 'r',
          amountPaise: 100,
          counterparty: 'X',
          at: t,
        ),
        isNot(
          DedupEngine.fingerprint(
            refNo: 'r',
            amountPaise: 100,
            counterparty: 'Y',
            at: t,
          ),
        ),
      );
    });

    test('ref difference changes the key', () {
      expect(
        DedupEngine.fingerprint(
          refNo: 'a',
          amountPaise: 100,
          counterparty: 'X',
          at: t,
        ),
        isNot(
          DedupEngine.fingerprint(
            refNo: 'b',
            amountPaise: 100,
            counterparty: 'X',
            at: t,
          ),
        ),
      );
    });

    test('null and empty refs normalise to the same key', () {
      expect(
        DedupEngine.fingerprint(
          refNo: null,
          amountPaise: 100,
          counterparty: 'X',
          at: t,
        ),
        DedupEngine.fingerprint(
          refNo: '',
          amountPaise: 100,
          counterparty: 'X',
          at: t,
        ),
      );
    });

    test('output is a 40-char hex sha1', () {
      final String k = DedupEngine.fingerprint(
        refNo: 'r',
        amountPaise: 1,
        counterparty: 'X',
        at: t,
      );
      expect(k.length, 40);
      expect(k, matches(RegExp('^[0-9a-f]{40}\$')));
    });

    test('bucket width is 10 minutes', () {
      expect(DedupEngine.bucketMs, 600000);
    });
  });
}
