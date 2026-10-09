import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the device can run the ARCore experience.
enum ArSupport {
  /// ARCore is installed and up to date: use the real AR view.
  supported,

  /// The device supports ARCore but "Google Play Services for AR" is missing
  /// or too old. [requestArCoreInstall] can fix it (needs Play Store).
  needsInstall,

  /// Device not capable (or no OpenGL ES 3.0, or not Android):
  /// use 「かんたん AR」.
  unsupported,

  /// Could not determine (e.g. offline on first check). Treat like
  /// [unsupported] for now; checking again later may succeed.
  unknown,
}

/// Result of [requestArCoreInstall].
enum ArInstallResult {
  /// Installed / already up to date: AR can start.
  installed,

  /// The Play Store flow was started. Call [requestArCoreInstall] again with
  /// `userRequested: false` when the app is resumed.
  requested,

  /// The user declined the installation.
  declined,

  /// Anything else (no activity, Play Store missing, ...).
  error,
}

/// Camera permission state.
enum CameraPermission { granted, denied, permanentlyDenied }

const MethodChannel arChannel = MethodChannel('doodle_battle/ar');

/// Checks ARCore availability (fast; does not start the camera).
Future<ArSupport> checkArSupport() => ArPlatform.instance.checkArSupport();

/// Asks Google Play Services for AR to install or update.
Future<ArInstallResult> requestArCoreInstall({bool userRequested = true}) =>
    ArPlatform.instance.requestArCoreInstall(userRequested: userRequested);

/// Platform services used by the AR feature. Replaceable in tests via
/// [ArPlatform.instance].
class ArPlatform {
  const ArPlatform();

  static ArPlatform instance = const ArPlatform();

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<ArSupport> checkArSupport() async {
    if (!_isAndroid) return ArSupport.unsupported;
    try {
      final r = await arChannel.invokeMethod<String>('checkAvailability');
      return switch (r) {
        'supported' => ArSupport.supported,
        'needsInstall' => ArSupport.needsInstall,
        'unsupported' => ArSupport.unsupported,
        _ => ArSupport.unknown,
      };
    } on PlatformException {
      return ArSupport.unknown;
    } on MissingPluginException {
      return ArSupport.unsupported;
    }
  }

  Future<ArInstallResult> requestArCoreInstall({
    bool userRequested = true,
  }) async {
    if (!_isAndroid) return ArInstallResult.error;
    try {
      final r = await arChannel.invokeMethod<String>('requestInstall', {
        'userRequested': userRequested,
      });
      return switch (r) {
        'installed' => ArInstallResult.installed,
        'requested' => ArInstallResult.requested,
        'declined' => ArInstallResult.declined,
        _ => ArInstallResult.error,
      };
    } on PlatformException {
      return ArInstallResult.error;
    } on MissingPluginException {
      return ArInstallResult.error;
    }
  }

  /// Current CAMERA permission without showing any dialog.
  Future<CameraPermission> checkCameraPermission() async {
    if (!_isAndroid) return CameraPermission.granted;
    try {
      final r = await arChannel.invokeMethod<String>('cameraPermission');
      return r == 'granted'
          ? CameraPermission.granted
          : CameraPermission.denied;
    } on PlatformException {
      return CameraPermission.denied;
    } on MissingPluginException {
      return CameraPermission.denied;
    }
  }

  /// Requests the CAMERA runtime permission (shows the system dialog when
  /// needed).
  Future<CameraPermission> requestCameraPermission() async {
    if (!_isAndroid) return CameraPermission.granted; // camera plugin asks
    try {
      final r = await arChannel.invokeMethod<String>('requestCameraPermission');
      return switch (r) {
        'granted' => CameraPermission.granted,
        'permanentlyDenied' => CameraPermission.permanentlyDenied,
        _ => CameraPermission.denied,
      };
    } on PlatformException {
      return CameraPermission.denied;
    } on MissingPluginException {
      return CameraPermission.denied;
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await arChannel.invokeMethod<bool>('openAppSettings') ?? false;
    } on Exception {
      return false;
    }
  }
}
