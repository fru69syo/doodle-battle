import 'package:doodle_battle/features/spike25d/battle/battle_session25.dart';
import 'package:doodle_battle/features/spike25d/battle/director25d.dart';
import 'package:doodle_battle/features/spike25d/samples25d.dart';
import 'package:flutter_test/flutter_test.dart';

BattleSession25 session({
  int seed = 7,
  bool auto = true,
  bool bloomer = false,
}) {
  final sides = [
    Side25(png: sample25dPng(Sample25d.hero), name: 'a', genomeSeed: 11),
    Side25(
      png: sample25dPng(Sample25d.dog),
      name: 'b',
      genomeSeed: 5,
      bloomer: bloomer,
    ),
  ];
  return BattleSession25(
    sides: sides,
    characters: [for (final s in sides) buildSideCharacter(s)],
    seed: seed,
    alwaysAuto: auto,
  );
}

void main() {
  test('おまかせ battle runs to a KO; fighters stay on screen', () {
    final s = session();
    const dt = 1 / 30;
    var frames = 0, inView = 0;
    while (!s.over && frames < 30 * 200) {
      s.advance(dt);
      frames++;
      var ok = true;
      for (final f in s.director.fighters) {
        final (x, y, k) = s.director.camera.project(f.x, f.z, 393, 851);
        if (x - 0.3 * k < 0 ||
            x + 0.3 * k > 393 ||
            y > 851 ||
            y - 1.25 * k < 0) {
          ok = false;
        }
      }
      if (ok) inView++;
    }
    expect(s.over, isTrue);
    expect(s.engine.finished, isTrue);
    expect(s.director.winner, s.engine.winner);
    expect(inView / frames, greaterThan(0.97));
    // Shown HP matches the engine once everything has played out.
    for (var i = 0; i < 60; i++) {
      s.advance(dt);
    }
    for (var i = 0; i < 2; i++) {
      expect(s.director.fighters[i].shownHp, s.engine.fighters[i].hp);
    }
  });

  test('さきどり: a move tapped early fires on the tick the gauge fills', () {
    final s = session(auto: false);
    s.tap(0);
    while (s.engine.events
        .where((e) => e.type == 'choose' && e.data['side'] == 0)
        .isEmpty) {
      s.advance(0.05);
    }
    final ready = s.engine.events.firstWhere(
      (e) => e.type == 'ready' && e.data['side'] == 0,
    );
    final choose = s.engine.events.firstWhere(
      (e) => e.type == 'choose' && e.data['side'] == 0,
    );
    expect(choose.tick, ready.tick);
    expect(s.pending, isNull);
  });

  test('time-out: no tap → おまかせ after 5 s of a full gauge', () {
    final s = session(auto: false);
    while (s.engine.events
        .where((e) => e.type == 'autoPick' && e.data['side'] == 0)
        .isEmpty) {
      s.advance(0.1);
      expect(s.engine.tick, lessThan(600));
    }
    final ready = s.engine.events.firstWhere(
      (e) => e.type == 'ready' && e.data['side'] == 0,
    );
    final auto = s.engine.events.firstWhere(
      (e) => e.type == 'autoPick' && e.data['side'] == 0,
    );
    expect(auto.tick - ready.tick, s.engine.spec.decisionTicks - 1);
  });

  test('deterministic for a seed (director included)', () {
    String run() {
      final s = session(seed: 3);
      for (var i = 0; i < 600; i++) {
        s.advance(1 / 30);
      }
      final f = s.director.fighters;
      return '${s.engine.events.length} ${f[0].x.toStringAsFixed(4)} ${f[1].z.toStringAsFixed(4)}';
    }

    expect(run(), run());
  });

  test('hidden late bloomer below Lv50 gets the simplified look', () {
    final s = Side25(
      png: sample25dPng(Sample25d.hero),
      name: 'x',
      bloomer: true,
    );
    expect(buildSideCharacter(s).simplified, isTrue);
    final s50 = Side25(
      png: sample25dPng(Sample25d.hero),
      name: 'x',
      bloomer: true,
      level: 50,
    );
    expect(buildSideCharacter(s50).simplified, isFalse);
  });

  test('camera projection: nearer is lower and bigger', () {
    final c = StageCamera();
    final (_, yNear, kNear) = c.project(0, 0.3, 393, 851);
    final (_, yFar, kFar) = c.project(0, 2.5, 393, 851);
    expect(yNear, greaterThan(yFar));
    expect(kNear, greaterThan(kFar));
  });
}
