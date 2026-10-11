import 'dart:ui' as ui;

import 'package:doodle_battle/features/spike25d/anim/clips.dart';
import 'package:doodle_battle/features/spike25d/battle/battle_session25.dart';
import 'package:doodle_battle/features/spike25d/battle/stage_painter.dart';
import 'package:doodle_battle/features/spike25d/render/character_sprite.dart';
import 'package:doodle_battle/features/spike25d/rig/rigged_character.dart';
import 'package:doodle_battle/features/spike25d/samples25d.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// CPU cost per frame (JIT, desktop x86) of the parts that run on the UI
/// thread every frame: engine + director, skinning 2 characters, building
/// the Vertices, and recording the whole stage picture. Numbers go to
/// docs/V2_25D_TECH.md §6. Raster cost is GPU work on a phone and is not
/// measured here (software Skia in tests is not representative).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> measure(String label, BuildOptions o) async {
    final sides = [
      Side25(png: sample25dPng(Sample25d.hero), name: 'a', genomeSeed: 11),
      Side25(png: sample25dPng(Sample25d.dog), name: 'b', genomeSeed: 5),
    ];
    final sw0 = Stopwatch()..start();
    final chars = [
      for (final s in sides) buildRiggedCharacterFromPng(s.png, options: o),
    ];
    final buildMs = sw0.elapsedMilliseconds / 2;
    final sprites = [for (final c in chars) await CharacterSprite.create(c)];
    final s = BattleSession25(
      sides: sides,
      characters: chars,
      alwaysAuto: true,
    );
    final painter = StagePainter(
      director: s.director,
      sprites: sprites,
      repaintSignal: ValueNotifier(0),
    );
    const size = Size(393, 851);
    const dt = 1 / 60;
    // Warm-up (JIT).
    for (var i = 0; i < 300; i++) {
      s.advance(dt);
      final r = ui.PictureRecorder();
      painter.paint(Canvas(r), size);
      r.endRecording().dispose();
    }
    final sim = Stopwatch(), skin = Stopwatch(), paint = Stopwatch();
    const n = 1200;
    for (var i = 0; i < n; i++) {
      sim.start();
      s.advance(dt);
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
    final tris = chars.fold<int>(0, (a, c) => a + c.triangleCount);
    final kb = chars.fold<int>(0, (a, c) => a + c.bytes) ~/ 1024;
    // ignore: avoid_print
    print(
      '$label: tris(2 chars)=$tris build/char=${buildMs.toStringAsFixed(0)}ms '
      'sim+director=${(sim.elapsedMicroseconds / n).toStringAsFixed(0)}µs '
      'skin(2)=${(skin.elapsedMicroseconds / n).toStringAsFixed(0)}µs '
      'record stage (incl. skin+Vertices)=${(paint.elapsedMicroseconds / n).toStringAsFixed(0)}µs '
      'cpu-mem=${kb}KiB',
    );
    for (final sp in sprites) {
      sp.dispose();
    }
  }

  test('frame cost', () async {
    await measure('grid 64 (default)', const BuildOptions());
    await measure('grid 96 (dense)', const BuildOptions(gridCells: 96));
    await measure('grid 40 (low tier)', const BuildOptions(gridCells: 40));
  });
}
