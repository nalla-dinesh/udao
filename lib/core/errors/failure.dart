// UDAO's failure hierarchy — one sealed family, no exceptions for
// expected failure paths (that's `Result`'s job).
//
// Equality is by runtime type + message, so `Result` values holding
// failures compare the way tests and dedup logic expect them to.
sealed class Failure {
  const Failure(this.message, {this.cause, this.stackTrace});

  /// Human-readable description (safe to log / show in diagnostics).
  final String message;

  /// The underlying error, if any (exception, platform code, …).
  final Object? cause;

  /// Where it happened, if captured.
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) =>
      other is Failure &&
      other.runtimeType == runtimeType &&
      other.message == message;

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// SQLite / SQLCipher layer failures.
final class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message, {super.cause, super.stackTrace});
}

/// Bank SMS / notification / receipt text could not be parsed.
final class ParseFailure extends Failure {
  const ParseFailure(super.message, {super.cause, super.stackTrace});
}

/// Capture pipeline failures (listener dead, WAL write, replay, …).
final class CaptureFailure extends Failure {
  const CaptureFailure(super.message, {super.cause, super.stackTrace});
}

/// User-facing permission problems (notification access, SMS, …).
final class PermissionFailure extends Failure {
  const PermissionFailure(super.message, {super.cause, super.stackTrace});
}

/// On-device AI model loading / inference problems.
final class ModelFailure extends Failure {
  const ModelFailure(super.message, {super.cause, super.stackTrace});
}

/// Anything unexpected — the wrapper `Result.guard` produces.
final class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message, {super.cause, super.stackTrace});
}
