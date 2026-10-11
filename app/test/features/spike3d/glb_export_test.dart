import 'dart:io';

import 'package:doodle_battle/features/ar/sample_cutout.dart';
import 'package:doodle_battle/features/spike3d/inflate/inflate_mesh.dart';
import 'package:doodle_battle/features/spike3d/inflate/inflated_glb.dart';
import 'package:doodle_battle/features/spike3d/samples.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes inflated GLBs for the Khronos glTF validator (see
/// gltf_validate.sh). Skipped unless SPIKE3D_GLB_EXPORT_DIR is set.
void main() {
  final dir = Platform.environment['SPIKE3D_GLB_EXPORT_DIR'];
  test('export inflated GLBs', () {
    final out = Directory(dir!)..createSync(recursive: true);
    final cases = {
      'inflated_sample': (buildSampleCutoutPng(), const InflateOptions()),
      'inflated_512': (buildLargeSampleCutoutPng(), const InflateOptions()),
      'simplified_sample': (
        buildSampleCutoutPng(),
        const InflateOptions.simplified(),
      ),
      'simplified_512': (
        buildLargeSampleCutoutPng(),
        const InflateOptions.simplified(),
      ),
    };
    for (final MapEntry(key: name, value: (png, options)) in cases.entries) {
      final r = buildInflatedGlb(png, options: options);
      File('${out.path}/$name.glb').writeAsBytesSync(r.glb);
    }
  }, skip: dir == null ? 'set SPIKE3D_GLB_EXPORT_DIR to export' : false);
}
