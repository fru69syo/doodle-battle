import 'dart:math' as math;

import 'package:doodle_battle/features/spike3d/battle/atb.dart';
import 'package:doodle_battle/features/spike3d/battle/battle_director.dart';
import 'package:doodle_battle/features/spike3d/battle/spike_battle_setup.dart';
import 'package:doodle_battle/features/spike3d/inflate/procedural_rig.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// True when [p] is inside the camera's view cone with a margin.
bool inView(CameraView c, Vector3 p, {double aspect = 393 / 851}) {
  final f = (c.target - c.eye).normalized();
  final right = Vector3(0, 1, 0).cross(f).normalized();
  final up = f.cross(right);
  final d = p - c.eye;
  final z = d.dot(f);
  if (z <= 0) return false;
  final tanY = math.tan(c.fovY * math.pi / 360);
  final x = d.dot(right) / (z * tanY * aspect);
  final y = d.dot(up) / (z * tanY);
  return x.abs() < 1 && y.abs() < 1;
}

void main() {
  group('ATB', () {
    test('gauges fill by AGI and never pause for the other side', () {
      final b = spikeBattle(playerAgi: 20, cpuAgi: 10);
      // Player full after ~2 s (AGI 20 of mean 15 → 3 s / 1.333).
      var t = 0.0;
      while (!b.playerCanChoose) {
        b.tick(0.05);
        t += 0.05;
      }
      expect(t, closeTo(2.25, 0.1));
      // While the player thinks, the CPU keeps filling.
      final before = b.fighters[1].gauge;
      b.tick(0.5);
      expect(b.fighters[1].gauge, greaterThan(before));
      // The player's own gauge does not grow beyond full.
      expect(b.fighters[0].gauge, 1);
    });

    test('おまかせ after the 5 s time-out', () {
      final b = spikeBattle();
      final events = <AtbEvent>[];
      while (!b.playerCanChoose) {
        events.addAll(b.tick(0.05));
      }
      for (var i = 0; i < 160; i++) {
        events.addAll(b.tick(0.05));
      }
      final mine = events.whereType<ActionStarted>().where((a) => a.side == 0);
      expect(mine, isNotEmpty);
      expect(mine.first.auto, isTrue);
    });

    test('player choice is used; deterministic with a seed', () {
      List<int> run() {
        final b = spikeBattle(seed: 9);
        final dmg = <int>[];
        while (!b.over) {
          if (b.playerCanChoose) b.choose(1);
          for (final e in b.tick(1 / 30)) {
            if (e is ActionStarted) dmg.add(e.damage);
          }
        }
        return dmg;
      }

      expect(run(), run());
    });
  });

  group('director', () {
    test('a whole auto battle: stays in the ring, camera frames both, '
        'every hit lands, loser faints', () {
      final b = spikeBattle(seed: 4)..alwaysAuto = true;
      final d = BattleDirector(seed: 4);
      var hits = 0, actions = 0;
      var minSep = double.infinity;
      var outOfView = 0, frames = 0;
      final clips = <String>{};
      for (var i = 0; i < 30 * 120 && !(b.over && d.fighters.any((f) => f.mode == StageMode.fainted)); i++) {
        for (final e in b.tick(1 / 30)) {
          if (e is ActionStarted) actions++;
          d.handle(e);
        }
        d.update(1 / 30);
        hits += d.takeCues().length;
        for (final f in d.fighters) {
          expect(f.position.length, lessThanOrEqualTo(d.arenaRadius + 1e-5));
          clips.add(f.clip);
        }
        minSep = math.min(minSep, d.fighters[0].position.distanceTo(d.fighters[1].position));
        frames++;
        final c = d.camera;
        // While fighting both must be framed; after the KO the camera
        // orbits the winner.
        for (final f in d.fighters) {
          if (b.over && f.side != b.winner) continue;
          if (!inView(c, f.position + Vector3(0, 0.5, 0))) outOfView++;
        }
      }
      expect(b.over, isTrue);
      expect(hits, actions);
      expect(minSep, greaterThanOrEqualTo(BattleDirector.minDistance - 1e-5));
      expect(outOfView / (2 * frames), lessThan(0.01));
      expect(clips, containsAll([RigClips.idle, RigClips.hop, RigClips.attack, RigClips.hit, RigClips.faint]));
      final loser = d.fighters[1 - b.winner!];
      expect(loser.mode, StageMode.fainted);
    });

    test('the player stays on the left of the screen while fighting', () {
      final b = spikeBattle(seed: 2)..alwaysAuto = true;
      final d = BattleDirector(seed: 2);
      var left = 0, total = 0;
      for (var i = 0; i < 30 * 20 && !b.over; i++) {
        for (final e in b.tick(1 / 30)) {
          d.handle(e);
        }
        d.update(1 / 30);
        final c = d.camera;
        final f = (c.target - c.eye).normalized();
        final right = Vector3(0, 1, 0).cross(f);
        final p0 = (d.fighters[0].position - c.eye).dot(right);
        final p1 = (d.fighters[1].position - c.eye).dot(right);
        if (p0 < p1) left++;
        total++;
      }
      expect(left / total, greaterThan(0.95));
    });
  });
}
