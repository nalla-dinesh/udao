// phase-04
// image_picker behind a seam. The picker ALSO does the thumbnail
// job: maxWidth/imageQuality mean the plugin itself returns a
// ~720-1080px JPEG — full-res originals are deliberately never
// kept (smaller attack surface, smaller vault, nothing to leak).
import 'package:image_picker/image_picker.dart' as ip;
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';

abstract class ReceiptCamera {
  /// Camera capture. `Ok(null)` = user cancelled (never an error).
  Future<Result<String?>> shoot();

  /// Gallery pick. `Ok(null)` = user cancelled.
  Future<Result<String?>> pickFromGallery();
}

class ImagePickerReceiptCamera implements ReceiptCamera {
  const ImagePickerReceiptCamera();

  static const double _maxWidthPx = 1080;
  static const int _imageQuality = 72;

  @override
  Future<Result<String?>> shoot() => _pick(ip.ImageSource.camera);

  @override
  Future<Result<String?>> pickFromGallery() =>
      _pick(ip.ImageSource.gallery);

  Future<Result<String?>> _pick(ip.ImageSource source) async {
    try {
      final ip.XFile? file = await ip.ImagePicker().pickImage(
        source: source,
        maxWidth: _maxWidthPx,
        maxHeight: _maxWidthPx,
        imageQuality: _imageQuality,
      );
      return Ok<String?>(file?.path);
    } on Object catch (e, s) {
      return Err<String>(
        CaptureFailure('image_pick_failed', cause: e, stackTrace: s),
      );
    }
  }
}
