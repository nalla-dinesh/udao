// phase-04
// permission_handler behind a seam. The SMS runtime permission only
// exists in the POWER flavor (play has no RECEIVE_SMS in its manifest,
// so Android will report it denied there no matter what) — callers
// gate on flavor before even asking. Everything above this file stays
// plugin-free, so widget tests run on fakes.
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:udao/core/errors/failure.dart';
import 'package:udao/core/result/result.dart';

/// Permissions UDAO ever asks for at runtime. Notification access is
/// NOT here — it is a special-access setting handled by
/// [CaptureBridge.openListenerSettings].
enum CapturePermission {
  /// RECEIVE_SMS — power flavor only.
  sms,
}

abstract class PermissionPort {
  /// Whether [permission] is currently granted (never prompts).
  Future<bool> isGranted(CapturePermission permission);

  /// Prompts once. `Err(PermissionFailure('permanently_denied'))`
  /// means the user must go to system settings.
  Future<Result<bool>> request(CapturePermission permission);

  /// Opens the app's system settings page (for permanently denied).
  Future<Result<bool>> openSystemSettings();
}

class PlatformPermissionPort implements PermissionPort {
  ph.Permission _map(CapturePermission permission) {
    switch (permission) {
      case CapturePermission.sms:
        return ph.Permission.sms;
    }
  }

  @override
  Future<bool> isGranted(CapturePermission permission) async {
    return (await _map(permission).status).isGranted;
  }

  @override
  Future<Result<bool>> request(CapturePermission permission) async {
    try {
      final ph.PermissionStatus status = await _map(permission).request();
      if (status.isPermanentlyDenied) {
        return const Err<bool>(PermissionFailure('permanently_denied'));
      }
      return Ok<bool>(status.isGranted);
    } on Object catch (e, s) {
      return Err<bool>(
        PermissionFailure('request_failed', cause: e, stackTrace: s),
      );
    }
  }

  @override
  Future<Result<bool>> openSystemSettings() async {
    try {
      return Ok<bool>(await ph.openAppSettings());
    } on Object catch (e, s) {
      return Err<bool>(
        PermissionFailure('settings_failed', cause: e, stackTrace: s),
      );
    }
  }
}
