// phase-02
// Shared DAO plumbing: every DAO call returns `Result` and logs its
// own scope on failure — the UI never sees a raw sqlite exception.
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/log/udao_logger.dart';
import 'package:udao/core/result/result.dart';

final UdaoLogger _daoLog = udaoLog.child('dao');

/// Runs [action], mapping any throw to `Err(DatabaseFailure)`.
Future<Result<T>> guardDb<T>(String scope, Future<T> Function() action) async {
  try {
    return Ok<T>(await action());
  } on Object catch (e, s) {
    _daoLog.warn('$scope failed: $e');
    return Err<T>(
      DatabaseFailure('$scope failed', cause: e, stackTrace: s),
    );
  }
}
