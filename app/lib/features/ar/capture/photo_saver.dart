import 'dart:typed_data';

import 'package:gal/gal.dart';

/// Outcome of saving a photo to the device gallery.
enum SaveResult { saved, noPermission, noSpace, failed }

/// Saves AR photos to the device gallery.
///
/// Android 10+ (API 29+) writes through MediaStore without any permission
/// (we save without a custom album, which on API 29 would need storage
/// permission). Android 7–9 asks for WRITE_EXTERNAL_STORAGE (declared with
/// maxSdkVersion=28).
class PhotoSaver {
  const PhotoSaver();

  Future<SaveResult> save(Uint8List jpeg, {DateTime? now}) async {
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) return SaveResult.noPermission;
      }
      await Gal.putImageBytes(jpeg, name: photoFileName(now ?? DateTime.now()));
      return SaveResult.saved;
    } on GalException catch (e) {
      return switch (e.type) {
        GalExceptionType.accessDenied => SaveResult.noPermission,
        GalExceptionType.notEnoughSpace => SaveResult.noSpace,
        _ => SaveResult.failed,
      };
    } on Exception {
      return SaveResult.failed;
    }
  }
}

/// `rakugaki_ar_20261009_153012` (extension added by the gallery plugin).
String photoFileName(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'rakugaki_ar_${t.year}${two(t.month)}${two(t.day)}_'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}
