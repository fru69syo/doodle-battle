import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:doodle_battle/features/spike3d/battle/battle_stage.dart';
import 'package:doodle_battle/features/spike3d/inflate/inflated_glb.dart';
import 'package:doodle_battle/features/spike3d/samples.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// Guards the coordinate mapping between the director (face along
/// (sin yaw, 0, cos yaw)) and flutter_scene's importer (glTF +Z → engine
/// −Z): with yaw 0 the bright, non-mirrored front must face +Z.
/// GPU only: flutter test --enable-impeller --enable-flutter-gpu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the drawing faces the direction the director asks for', () async {
    await Scene.initializeStaticResources();
    final glb = buildInflatedGlb(buildLargeSampleCutoutPng());
    final scene = Scene();
    final model = await Node.fromGlbBytes(glb.glb);
    scene.add(Node()..add(model));
    // Same mapping as BattleStage.apply with yaw = 0.
    model.parent!.rotation = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi);
    Future<double> brightnessFrom(double z) async {
      final r = ui.PictureRecorder();
      scene.render(
        PerspectiveCamera(
          position: Vector3(0, 0.5, z),
          target: Vector3(0, 0.5, 0),
        ),
        ui.Canvas(r),
        viewport: ui.Offset.zero & const ui.Size(96, 96),
        pixelRatio: 1,
      );
      final im = await r.endRecording().toImage(96, 96);
      final b = (await im.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var sum = 0, n = 0;
      for (var i = 0; i < b.lengthInBytes; i += 4) {
        if (b.getUint8(i + 3) == 0) continue;
        sum += b.getUint8(i) + b.getUint8(i + 1) + b.getUint8(i + 2);
        n++;
      }
      return sum / n;
    }

    final front = await brightnessFrom(3);
    final back = await brightnessFrom(-3);
    expect(front, greaterThan(back * 1.15));
  }, skip: flutterGpuAvailable() ? false : 'needs --enable-flutter-gpu');
}
