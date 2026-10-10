import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One-shot permission to import one picture from the album (SPEC §11.1).
///
/// Children capture their paper drawing with the camera. Only a parent, from
/// 「おうちのひと」 (behind the parental gate), can arm an album import; the
/// draw screen consumes the flag immediately, so it never stays open.
class AlbumImportArm extends Notifier<bool> {
  @override
  bool build() => false;

  void arm() => state = true;

  /// Returns whether an import was armed, and disarms it.
  bool consume() {
    final armed = state;
    state = false;
    return armed;
  }
}

final albumImportArmProvider = NotifierProvider<AlbumImportArm, bool>(
  AlbumImportArm.new,
);
