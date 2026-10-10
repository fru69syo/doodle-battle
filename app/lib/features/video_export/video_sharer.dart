/// Saving / sharing the finished video (parent-gated by the screen).
library;

import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

enum VideoSaveResult { saved, noPermission, noSpace, failed }

abstract interface class VideoSharer {
  /// Saves the mp4 at [path] to the device gallery (Movies, no album).
  Future<VideoSaveResult> saveToGallery(String path);

  /// Opens the system share sheet. True unless it failed to open.
  Future<bool> share(String path);
}

/// `gal` (MediaStore; no permission on Android 10+, WRITE_EXTERNAL_STORAGE
/// with maxSdkVersion 28 below) and `share_plus` (system share sheet).
class PlatformVideoSharer implements VideoSharer {
  const PlatformVideoSharer();

  @override
  Future<VideoSaveResult> saveToGallery(String path) async {
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) return VideoSaveResult.noPermission;
      }
      await Gal.putVideo(path);
      return VideoSaveResult.saved;
    } on GalException catch (e) {
      return switch (e.type) {
        GalExceptionType.accessDenied => VideoSaveResult.noPermission,
        GalExceptionType.notEnoughSpace => VideoSaveResult.noSpace,
        _ => VideoSaveResult.failed,
      };
    } on Exception {
      return VideoSaveResult.failed;
    }
  }

  @override
  Future<bool> share(String path) async {
    try {
      final r = await SharePlus.instance.share(
        ShareParams(files: [XFile(path, mimeType: 'video/mp4')]),
      );
      return r.status != ShareResultStatus.unavailable;
    } on Exception {
      return false;
    }
  }
}
