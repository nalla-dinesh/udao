import 'package:flutter_test/flutter_test.dart';
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';

void main() {
  group('guard', () {
    test('returns Ok on success', () {
      final result = Result.guard(() => 42);
      expect(result.isOk, isTrue);
      expect(result.valueOrNull, 42);
    });

    test('catches throws into UnexpectedFailure with cause + stack', () {
      final result = Result<int>.guard(() => throw StateError('boom'));
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      final failure = result.failureOrNull!;
      expect(failure, isA<UnexpectedFailure>());
      expect(failure.message, 'Guarded block failed');
      expect(failure.cause, isA<StateError>());
      expect(failure.stackTrace, isNotNull);
    });
  });

  group('map / fold / when', () {
    const ok = Ok<int>(10);
    const err = Err<int>(ParseFailure('bad amount'));

    test('map picks the right branch', () {
      expect(ok.map((v) => 'ok:$v', (f) => 'err:${f.message}'), 'ok:10');
      expect(
        err.map((v) => 'ok:$v', (f) => 'err:${f.message}'),
        'err:bad amount',
      );
    });

    test('fold picks the right branch (error-first convention)', () {
      expect(ok.fold((f) => -1, (v) => v + 1), 11);
      expect(err.fold((f) => -1, (v) => v + 1), -1);
    });

    test('when picks the right branch', () {
      expect(ok.when<int>(ok: (v) => v * 2, err: (f) => 0), 20);
      expect(err.when<int>(ok: (v) => v * 2, err: (f) => 0), 0);
    });
  });

  group('exhaustive switch (sealed)', () {
    test('pattern matching covers both cases', () {
      String describe(Result<String> result) => switch (result) {
            Ok(value: final v) => 'ok:$v',
            Err(failure: final f) => 'err:${f.runtimeType}',
          };
      expect(describe(const Ok<String>('hi')), 'ok:hi');
      expect(
        describe(const Err<String>(DatabaseFailure('locked'))),
        'err:DatabaseFailure',
      );
    });
  });

  group('accessors', () {
    test('isOk / isErr / nullables', () {
      const ok = Ok<int>(3);
      const err = Err<int>(CaptureFailure('listener dead'));
      expect(ok.isOk && !ok.isErr, isTrue);
      expect(err.isErr && !err.isOk, isTrue);
      expect(ok.failureOrNull, isNull);
      expect(err.valueOrNull, isNull);
      expect(err.failureOrNull, isA<CaptureFailure>());
    });
  });

  group('equality', () {
    test('Ok value equality', () {
      expect(const Ok<int>(1), const Ok<int>(1));
      expect(const Ok<int>(1).hashCode, const Ok<int>(1).hashCode);
      expect(const Ok<int>(1) == const Ok<int>(2), isFalse);
    });

    test('Err equality is failure equality (type + message)', () {
      expect(
        const Err<int>(PermissionFailure('denied')),
        const Err<int>(PermissionFailure('denied')),
      );
      expect(
        const Err<int>(PermissionFailure('denied')) ==
            const Err<int>(PermissionFailure('other')),
        isFalse,
      );
      expect(
        const Err<int>(PermissionFailure('denied')).hashCode,
        const Err<int>(PermissionFailure('denied')).hashCode,
      );
    });

    test('Ok never equals Err', () {
      const Result<int> ok = Ok<int>(0);
      const Result<int> err = Err<int>(UnexpectedFailure('x'));
      expect(ok == err, isFalse);
    });
  });

  group('toString', () {
    test('useful for logs', () {
      expect(const Ok<int>(5).toString(), 'Ok(5)');
      expect(
        const Err<int>(ModelFailure('no weights')).toString(),
        startsWith('Err(ModelFailure: no weights'),
      );
    });
  });
}
