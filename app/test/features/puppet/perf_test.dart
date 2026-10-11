import 'dart:ui' as ui;

import 'package:doodle_battle/features/battle_stage/adapters/battle_v2_feed.dart';
import 'package:doodle_battle/features/battle_stage/battle_stage.dart';
import 'package:doodle_battle/features/battle_stage/debug/demo_battle.dart';
import 'package:doodle_battle/features/battle_stage/stage_background.dart';
import 'package:doodle_battle/features/battle_stage/stage_painter.dart';
import 'package:doodle_battle/features/battle_stage/stage_vfx.dart';
import 'package:doodle_battle/features/puppet/anim/clips.dart';
import 'package:doodle_battle/features/puppet/puppet_builder.dart';
import 'package:doodle_battle/features/puppet/render/puppet_sprite.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// CPU cost per frame (JIT, desktop x86) of what runs on the UI thread
/// every frame for 2 characters + stage: engine + director, skinning, the
/// Vertices, and recording the whole stage picture. Numbers go to
/// docs/PUPPET.md §5. Raster (GPU) cost is not measured here (software
/// Skia in tests is not representative of a phone GPU).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, double>> measure(String label, StageQuality q) async {
    final sides = [
      DemoSide(png: samplePng(Sample.hero), name: 'a', genomeSeed: 11),
      DemoSide(png: samplePng(Sample.dog), name: 'b', genomeSeed: 5),
    ];
    final sw0 = Stopwatch()..start();
    final meshes = [
      for (final s in sides) buildPuppetSync(s.puppet(quality: q.puppet)),
    ];
    final buildMs = sw0.elapsedMilliseconds / 2;
    final sprites = [for (final m in meshes) await PuppetSprite.create(m)];
    final feed = BattleV2Feed(demoEngine(sides), alwaysAuto: true);
    final c = BattleStageController(feed: feed)
      ..attach(meshes, [for (final s in sides) s.look]);
    final painter = StagePainter(
      director: c.director!,
      sprites: sprites,
      background: StageBackground(StageTheme.meadow),
      vfx: StageVfx(),
      quality: q,
    );
    const size = Size(393, 851);
    const dt = 1 / 60;
    for (var i = 0; i < 300; i++) {
      c.advance(dt);
      final r = ui.PictureRecorder();
      painter.paint(Canvas(r), size);
      r.endRecording().dispose();
    }
    final sim = Stopwatch(), skin = Stopwatch(), paint = Stopwatch();
    const n = 1200;
    for (var i = 0; i < n; i++) {
      sim.start();
      c.advance(dt);
      sim.stop();
      skin.start();
      for (final sp in sprites) {
        sp.prepare(Anim.walk, i * dt, 1);
        sp.skinner.skin(sp.pose, sp.placement(const Offset(200, 600), 0.5));
      }
      skin.stop();
      paint.start();
      final r = ui.PictureRecorder();
      painter.paint(Canvas(r), size);
      r.endRecording().dispose();
      paint.stop();
    }
    final tris = meshes.fold<int>(0, (a, m) => a + m.triangleCount);
    final kb = meshes.fold<int>(0, (a, m) => a + m.bytes) / 1024;
    final out = {
      'tris': tris.toDouble(),
      'buildMs': buildMs,
      'simUs': sim.elapsedMicroseconds / n,
      'skinUs': skin.elapsedMicroseconds / n,
      'frameUs': paint.elapsedMicroseconds / n,
      'cpuKiB': kb,
    };
    // ignore: avoid_print
    print(
      '$label: tris(2)=$tris build/char=${buildMs.toStringAsFixed(0)}ms '
      'engine+director=${out['simUs']!.toStringAsFixed(0)}µs '
      'skin(2)=${out['skinUs']!.toStringAsFixed(0)}µs '
      'record stage=${out['frameUs']!.toStringAsFixed(0)}µs '
      'cpu-mem=${kb.toStringAsFixed(0)}KiB',
    );
    for (final sp in sprites) {
      sp.dispose();
    }
    painter.background.dispose();
    return out;
  }

  test('frame cost and memory budget: 2 characters + stage', () async {
    final high = await measure('high', StageQuality.high);
    final low = await measure('low', StageQuality.low);
    // Budgets with wide margins (CI machines vary): a frame's CPU work
    // stays far below 16 ms, and the low tier is cheaper.
    expect(high['frameUs']!, lessThan(8000));
    expect(low['tris']!, lessThan(high['tris']!));
    expect(low['frameUs']!, lessThan(high['frameUs']! * 1.2));
    // Memory budget: 2 puppets' CPU side (textures + meshes + weights).
    expect(high['cpuKiB']!, lessThan(4 * 1024));
  });

  test('builder cache stays inside its memory budget', () async {
    final b = PuppetBuilder(runner: syncRunner, maxBytes: 2 << 20);
    for (final s in Sample.values) {
      await b.mesh(PuppetSpec(png: samplePng(s)));
    }
    expect(b.cachedBytes, lessThanOrEqualTo(2 << 20));
    expect(b.cachedCount, greaterThanOrEqualTo(1));
    // A hit returns the same mesh without rebuilding.
    final m1 = await b.mesh(PuppetSpec(png: samplePng(Sample.car)));
    final m2 = await b.mesh(PuppetSpec(png: samplePng(Sample.car)));
    expect(identical(m1, m2), isTrue);
  });
}
