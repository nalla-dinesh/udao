// phase-04
// file_picker behind a seam. Statement import starts with ONE user
// gesture that picks exactly one PDF or CSV from storage — no
// background file scanning, ever. file_picker copies the selection
// into the app cache; the import service reads it there and the
// temp copy dies with the OS cache eviction (plus explicit clear).
import 'package:file_picker/file_picker.dart' as fp;
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';

enum StatementFormat { pdf, csv }

/// One user-picked statement file.
class PickedStatement {
  const PickedStatement({required this.path, required this.displayName});

  /// Absolute path of the cache copy file_picker materialized.
  final String path;

  /// Human name (sans directory) for the review screen.
  final String displayName;
}

abstract class StatementSource {
  /// Opens the picker for one [format]. `Ok(null)` = the user
  /// cancelled (never an error, never a toast).
  Future<Result<PickedStatement?>> pick(StatementFormat format);
}

class FilePickerStatementSource implements StatementSource {
  @override
  Future<Result<PickedStatement?>> pick(StatementFormat format) async {
    try {
      final fp.FilePickerResult? result =
          await fp.FilePicker.platform.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: switch (format) {
          StatementFormat.pdf => const <String>['pdf'],
          StatementFormat.csv => const <String>['csv'],
        },
        allowMultiple: false,
        withData: false,
      );
      final fp.PlatformFile? file = result?.files.singleOrNull;
      if (file == null || file.path == null) {
        return const Ok<PickedStatement?>(null);
      }
      return Ok<PickedStatement?>(
        PickedStatement(
          path: file.path!,
          displayName: file.name,
        ),
      );
    } on Object catch (e, s) {
      return Err<PickedStatement?>(
        CaptureFailure('pick_failed', cause: e, stackTrace: s),
      );
    }
  }
}
