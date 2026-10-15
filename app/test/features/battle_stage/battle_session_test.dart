import 'package:doodle_battle/domain/battle_v3/battle_v3.dart' show typeChart;
import 'package:doodle_battle/features/battle_stage/adapters/battle_v3_feed.dart';
import 'package:doodle_battle/features/battle_stage/battle_stage.dart';
import 'package:doodle_battle/features/battle_stage/debug/demo_battle.dart';
import 'package:doodle_battle/features/battle_stage/stage_director.dart';
import 'package:doodle_battle/features/puppet/puppet_builder.dart';
import 'package:doodle_battle/features/puppet/samples.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stage controller over the prototype engine, without widgets.
(BattleStageController, BattleV3Feed) stage({
  int seed = 7,
  bool auto = true,
  bool bloomer = false,
  int level = 12,
  List<double> sizes = const [1, 1],
}) {
  final sides = [
    DemoSide(
      png: samplePng(Sample.hero),
      name: 'a',
      genomeSeed: 11,
      level: level,
    ),
    DemoSide(
      png: samplePng(Sample.dog),
      name: 'b',
      genomeSeed: 5,
      lateBloomer: bloomer,
      level: level,
    ),
  ];
  final feed = BattleV3Feed(demoEngine(sides, seed: seed), alwaysAuto: auto);
  final c = BattleStageController(feed: feed, seed: seed);
  c.attach(
    [for (final s in sides) buildPuppetSync(s.puppet())],
    [for (final s in sides) s.look],
    sizes: sizes,
  );
  return (c, feed);
}

void main() {
  test('おまかせ battle runs to a KO; fighters stay on screen', () {
    final (s, feed) = stage();
    const dt = 1 / 30;
    var frames = 0, inView = 0;
    while (!s.over && frames < 30 * 200) {
      s.advance(dt);
      frames++;
      var ok = true;
      for (final f in s.director!.fighters) {
        final (x, y, k) = s.director!.camera.project(f.x, f.z, 393, 851);
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
    expect(feed.engine.finished, isTrue);
    expect(s.winner, feed.engine.winner);
    expect(inView / frames, greaterThan(0.97));
    // Shown HP matches the engine once everything has played out.
    for (var i = 0; i < 60; i++) {
      s.advance(dt);
    }
    for (var i = 0; i < 2; i++) {
      expect(s.shownHp(i), feed.engine.fighters[i].hp);
    }
    // The adapter turned the engine log into stage events.
    expect(s.log.whereType<StageAction>(), isNotEmpty);
    expect(s.log.whereType<StageEnd>().single.winner, feed.engine.winner);
  });

  test('a bigger boss stays in the shot, head below the panels', () {
    final (s, feed) = stage(sizes: const [1, kBossSize]);
    final (n, nFeed) = stage();
    final d = s.director!;
    const w = 393.0, h = 851.0;
    const dt = 1 / 30;
    var frames = 0, inView = 0;
    var bossFx = 0.0, normalFx = 0.0;
    while (!s.over && frames < 30 * 200) {
      s.advance(dt);
      n.advance(dt);
      frames++;
      var ok = true;
      for (final f in d.fighters) {
        final (x, y, k) = d.camera.project(f.x, f.z, w, h);
        final size = d.size[f.side];
        final half = d.halfWidth[f.side] * k;
        final top = y - StageDirector.charHeight * size * k;
        if (x - half < 0 || x + half > w || y > h || top < h * 0.12) {
          ok = false;
        }
      }
      if (ok) inView++;
      for (final e in d.fx.where((e) => e.kind == 'number' && e.side == 1)) {
        bossFx = e.y;
      }
      for (final e in n.director!.fx.where(
        (e) => e.kind == 'number' && e.side == 1,
      )) {
        normalFx = e.y;
      }
    }
    expect(s.over, isTrue);
    expect(inView / frames, greaterThan(0.97));
    // Damage numbers float over the boss's (higher) head.
    expect(normalFx, greaterThan(0));
    expect(bossFx, closeTo(normalFx * kBossSize, 1e-9));
    // Visual only: the same battle as with normal sizes.
    expect(feed.engine.winner, nFeed.engine.winner);
    expect(d.halfWidth[1], greaterThan(n.director!.halfWidth[1]));
  });

  test('actions carry hits, crits and effectiveness from the engine', () {
    final (s, feed) = stage(seed: 5);
    while (!s.over) {
      s.advance(1 / 20);
    }
    final hits = s.log
        .whereType<StageAction>()
        .expand((a) => a.hits)
        .where((h) => !h.missed)
        .length;
    final damage = feed.engine.events.where((e) => e.type == 'hit').length;
    expect(hits, damage);
    // Every hit's matchup is what the engine's type chart says.
    for (final a in s.log.whereType<StageAction>()) {
      final m = feed.engine.fighters[a.side].moves[a.slot];
      final pct = typeChart(
        m.attr,
        feed.engine.fighters[1 - a.side].attr,
        feed.engine.spec,
      );
      for (final h in a.hits.where((h) => !h.missed)) {
        expect(
          h.effectiveness,
          pct > 100
              ? StageEffectiveness.strong
              : (pct < 100
                    ? StageEffectiveness.weak
                    : StageEffectiveness.normal),
        );
      }
    }
  });

  test('さきどり: a move tapped early fires on the tick the gauge fills', () {
    final (s, feed) = stage(auto: false);
    expect(feed.tap(0), isTrue);
    final e = feed.engine;
    while (e.events
        .where((x) => x.type == 'select' && x.data['side'] == 0)
        .isEmpty) {
      s.advance(0.05);
    }
    final ready = e.events.firstWhere(
      (x) => x.type == 'bar' && x.data['side'] == 0,
    );
    final choose = e.events.firstWhere(
      (x) => x.type == 'select' && x.data['side'] == 0,
    );
    expect(choose.tick, ready.tick);
    expect(feed.pending, isNull);
  });

  test('no timer: an idle player caps at max bars, nothing is picked', () {
    final (s, feed) = stage(auto: false);
    final e = feed.engine;
    while (e.tick < 300) {
      s.advance(0.1);
    }
    expect(
      e.events.where((x) => x.type == 'select' && x.data['side'] == 0),
      isEmpty,
    );
    final f = e.fighters[0];
    expect(f.bars, f.maxBars);
    expect(feed.fighter(0).full, isTrue);
    expect(
      s.log.whereType<StageReady>().where((r) => r.side == 0).length,
      f.maxBars,
    );
  });

  test('deterministic for a seed (director included)', () {
    String run() {
      final (s, feed) = stage(seed: 3);
      for (var i = 0; i < 600; i++) {
        s.advance(1 / 30);
      }
      final f = s.director!.fighters;
      return '${feed.engine.events.length} ${f[0].x.toStringAsFixed(4)} '
          '${f[1].z.toStringAsFixed(4)}';
    }

    expect(run(), run());
  });

  test('hidden late bloomer: simple look below Lv50, でんせつ at 50', () {
    final low = DemoSide(
      png: samplePng(Sample.hero),
      name: 'x',
      lateBloomer: true,
    );
    expect(buildPuppetSync(low.puppet()).simplified, isTrue);
    expect(low.look.fxScale, 0.5);
    final at50 = DemoSide(
      png: samplePng(Sample.hero),
      name: 'x',
      lateBloomer: true,
      level: 50,
    );
    expect(buildPuppetSync(at50.puppet()).simplified, isFalse);
    expect(at50.look.legend, isTrue);
    final kid50 = DemoSide(png: samplePng(Sample.hero), name: 'y', level: 50);
    expect(at50.look, kid50.look, reason: 'same look as everyone at Lv50');
  });

  test('camera projection: nearer is lower and bigger', () {
    final c = StageCamera();
    final (_, yNear, kNear) = c.project(0, 0.3, 393, 851);
    final (_, yFar, kFar) = c.project(0, 2.5, 393, 851);
    expect(yNear, greaterThan(yFar));
    expect(kNear, greaterThan(kFar));
  });

  test('stage themes cover the 10 worlds', () {
    final ids = {for (var w = 1; w <= 10; w++) StageTheme.forWorld(w).id};
    expect(ids.length, greaterThanOrEqualTo(7));
    for (final t in StageTheme.all) {
      expect(t.props, isNotEmpty);
      expect(StageTheme.byId(t.id), t);
    }
  });

  test('adaptive quality drops to low after sustained slow frames only', () {
    final q = AdaptiveQuality();
    for (var i = 0; i < 300; i++) {
      q.addFrame(i % 50 == 0 ? 60 : 9); // occasional hitch: stays high
    }
    expect(q.quality, StageQuality.high);
    StageQuality? changed;
    final q2 = AdaptiveQuality(onChange: (v) => changed = v);
    for (var i = 0; i < 200; i++) {
      q2.addFrame(i.isEven ? 28 : 12); // half the frames over budget
    }
    expect(q2.quality, StageQuality.low);
    expect(changed, StageQuality.low);
    for (var i = 0; i < 400; i++) {
      q2.addFrame(5);
    }
    expect(q2.quality, StageQuality.low, reason: 'no flapping back');
  });
}
