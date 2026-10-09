import 'dart:io';

import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/features/ar/ar_effects.dart';
import 'package:doodle_battle/features/ar/glb/standee_glb.dart';
import 'package:doodle_battle/features/ar/sample_cutout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Writes sample GLBs for external validation with the Khronos glTF
/// validator (see gltf_validator/run.sh). Skipped unless AR_GLB_EXPORT_DIR
/// is set.
void main() {
  final dir = Platform.environment['AR_GLB_EXPORT_DIR'];
  test('export sample GLBs', () {
    final out = Directory(dir!)..createSync(recursive: true);
    final png = buildSampleCutoutPng();
    final wide = img.Image(width: 500, height: 80, numChannels: 4);
    img.fill(wide, color: img.ColorRgba8(30, 140, 230, 255));
    final cases = {
      'lv1_fire': (png, ArEffects.forStage(EvolutionStage.normal, ElementType.fire)),
      'lv10_water': (png, ArEffects.forStage(EvolutionStage.kagayaki, ElementType.water)),
      'lv20_rainbow': (png, ArEffects.forStage(EvolutionStage.densetsu, ElementType.rainbow)),
      'wide_lv1': (img.encodePng(wide), ArEffects.none),
    };
    for (final MapEntry(key: name, value: (bytes, effects)) in cases.entries) {
      final r = buildStandeeGlb(bytes, options: StandeeGlbOptions(effects: effects));
      File('${out.path}/$name.glb').writeAsBytesSync(r.glb);
    }
  }, skip: dir == null ? 'set AR_GLB_EXPORT_DIR to export' : false);
}
