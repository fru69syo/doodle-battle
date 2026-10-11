import 'dart:io';
import 'dart:ui' as ui;

import 'package:doodle_battle/features/ar/sample_cutout.dart';
import 'package:doodle_battle/features/spike3d/battle/atb.dart';
import 'package:doodle_battle/features/spike3d/battle/battle_director.dart';
import 'package:doodle_battle/features/spike3d/battle/battle_stage.dart';
import 'package:doodle_battle/features/spike3d/battle/spike_battle_setup.dart';
import 'package:doodle_battle/features/spike3d/inflate/inflate_mesh.dart';
import 'package:doodle_battle/features/spike3d/inflate/inflated_glb.dart';
import 'package:doodle_battle/features/spike3d/samples.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the battle stage headlessly with Flutter GPU (Impeller on
/// SwiftShader Vulkan inside flutter_tester):
///   flutter test --enable-impeller --enable-flutter-gpu \
///     test/features/spike3d/battle_render_test.dart
/// Skipped when no GPU context exists (plain `flutter test`). Set
/// SPIKE3D_RENDER_DIR to keep the PNG frames.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final gpu = flutterGpuAvailable();

  test('renders two inflated fighters on the stage', () async {
    final out = Platform.environment['SPIKE3D_RENDER_DIR'];
    final player = buildInflatedGlb(buildLargeSampleCutoutPng());
    final simplified = Platform.environment['SPIKE3D_CPU_SIMPLIFIED'] == '1';
    final cpu = buildInflatedGlb(
      buildSampleCutoutPng(),
      options: simplified
          ? const InflateOptions.simplified()
          : const InflateOptions(),
    );
    final stage = await BattleStage.create(
      playerGlb: player.glb,
      cpuGlb: cpu.glb,
    );
    final battle = spikeBattle(seed: 4)..alwaysAuto = true;
    final director = BattleDirector(seed: 4);
    const size = ui.Size(393, 851);
    final shots = {0.5, 3.0, 3.6, 4.4, 6.0, 9.0, 14.0, 24.0};
    const dt = 1 / 30;
    var t = 0.0;
    var rendered = 0;
    final sw = Stopwatch();
    var renderUs = 0;
    var stepUs = 0, steps = 0;
    while (t < 24.0 + dt / 2) {
      final step = Stopwatch()..start();
      for (final e in battle.tick(dt)) {
        director.handle(e);
      }
      director.update(dt);
      stage.apply(director, dt, director.takeCues());
      stage.scene.update(dt);
      stepUs += step.elapsedMicroseconds;
      steps++;
      t += dt;
      if (shots.any((s) => (s - t).abs() < dt / 2)) {
        final recorder = ui.PictureRecorder();
        sw
          ..reset()
          ..start();
        stage.scene.render(
          stage.cameraFor(director.camera),
          ui.Canvas(recorder),
          viewport: ui.Offset.zero & size,
          pixelRatio: 1,
        );
        final image = await recorder.endRecording().toImage(393, 851);
        renderUs += sw.elapsedMicroseconds;
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        // Not a blank frame: the sky alone would be a smooth gradient.
        final raw = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final colours = <int>{};
        for (var i = 0; i < raw.lengthInBytes; i += 4 * 97) {
          colours.add(raw.getUint32(i));
        }
        expect(colours.length, greaterThan(200));
        if (out != null) {
          Directory(out).createSync(recursive: true);
          File('$out/battle_${t.toStringAsFixed(1)}s.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        }
        rendered++;
      }
    }
    expect(rendered, shots.length);
    expect(battle.over, isTrue);
    // ignore: avoid_print
    print(
      'rendered $rendered frames, mean ${renderUs ~/ rendered ~/ 1000} ms '
      '(SwiftShader CPU rasteriser, not representative of a phone); '
      'sim+director+apply+scene.update '
      '${(stepUs / steps).toStringAsFixed(0)} µs/frame (desktop JIT)',
    );
    // Silence unused warning for AtbEvent import in some analyzers.
    expect(GaugeFull(0).side, 0);
  }, skip: gpu ? false : 'needs --enable-impeller --enable-flutter-gpu');
}
