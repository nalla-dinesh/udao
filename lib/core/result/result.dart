import '../errors/failure.dart';

/// UDAO's flow-control type.
///
/// Exceptions are for bugs; [Result] is for expected failure paths
/// (parse errors, missing permissions, DB hiccups). Repositories and
/// services return `Result<T>` — never throw across feature boundaries.
///
/// ```dart
/// final Result<Money> parsed = Result.guard(() => parseAmount(raw));
/// switch (parsed) {
///   case Ok(value: final v):
///     udaoLog.debug('parsed $v');
///   case Err(failure: final f):
///     udaoLog.warn('parse failed', error: f);
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// Runs [fn], converting any thrown [Object] (Error or Exception)
  /// into `Err(UnexpectedFailure)` carrying the cause and stack trace.
  factory Result.guard(T Function() fn) {
    try {
      return Ok<T>(fn());
    } on Object catch (e, s) {
      return Err<T>(
        UnexpectedFailure(
          'Guarded block failed',
          cause: e,
          stackTrace: s,
        ),
      );
    }
  }

  bool get isOk;
  bool get isErr;

  /// The value when [isOk], otherwise `null`.
  T? get valueOrNull;

  /// The failure when [isErr], otherwise `null`.
  Failure? get failureOrNull;

  /// Maps both branches to a common type.
  R map<R>(R Function(T value) ifOk, R Function(Failure failure) ifErr);

  /// Folds to a single value; the error branch is first by convention.
  R fold<R>(R Function(Failure failure) ifErr, R Function(T value) ifOk);

  /// Exhaustive branch. (Plain `switch` over the sealed type works too
  /// and is preferred at call sites that need exhaustiveness.)
  W when<W>({
    required W Function(T value) ok,
    required W Function(Failure failure) err,
  });
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool get isOk => true;

  @override
  bool get isErr => false;

  @override
  T? get valueOrNull => value;

  @override
  Failure? get failureOrNull => null;

  @override
  R map<R>(R Function(T value) ifOk, R Function(Failure failure) ifErr) =>
      ifOk(value);

  @override
  R fold<R>(R Function(Failure failure) ifErr, R Function(T value) ifOk) =>
      ifOk(value);

  @override
  W when<W>({
    required W Function(T value) ok,
    required W Function(Failure failure) err,
  }) =>
      ok(value);

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;

  @override
  bool get isOk => false;

  @override
  bool get isErr => true;

  @override
  T? get valueOrNull => null;

  @override
  Failure? get failureOrNull => failure;

  @override
  R map<R>(R Function(T value) ifOk, R Function(Failure failure) ifErr) =>
      ifErr(failure);

  @override
  R fold<R>(R Function(Failure failure) ifErr, R Function(T value) ifOk) =>
      ifErr(failure);

  @override
  W when<W>({
    required W Function(T value) ok,
    required W Function(Failure failure) err,
  }) =>
      err(failure);

  @override
  bool operator ==(Object other) =>
      other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(runtimeType, failure);

  @override
  String toString() => 'Err($failure)';
}
