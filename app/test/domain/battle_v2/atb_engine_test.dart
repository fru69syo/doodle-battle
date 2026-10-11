// PROTOTYPE v2 tests — ATB engine (§6).
import 'package:doodle_battle/domain/battle/rng.dart';
import 'package:doodle_battle/domain/battle_v2/battle_v2.dart';
import 'package:doodle_battle/domain/battle_v2/sim_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V2Spec();

  test('same seed → identical battle', () {
    final r = Mulberry32(1);
    final a = setupAt(s, randomKid(s, r), 20);
    final b = setupAt(s, randomKid(s, r), 20);
    AtbBattle run() {
      final x = newBattle(s, a, b, seed: 77, recordEvents: true);
      x.run(aiController(), aiController());
      return x;
    }

    final x = run();
    final y = run();
    expect(
      x.events.map((e) => e.toString()).toList(),
      y.events.map((e) => e.toString()).toList(),
    );
  });

  test('a full gauge waits for the choice; the foe keeps charging', () {
    final r = Mulberry32(2);
    final a = setupAt(s, randomKid(s, r), 10);
    final b = setupAt(s, randomKid(s, r), 10);
    final x = newBattle(s, a, b, seed: 5);
    int? never(AtbBattle _, int _) => null;
    while (x.fighters[0].phase != Phase.ready) {
      x.step(never, aiController());
    }
    // The ready tick itself counts as the first of the decisionTicks.
    final g = x.fighters[0].gauge;
    for (var i = 0; i < s.decisionTicks - 2; i++) {
      x.step(never, aiController());
      expect(x.fighters[0].gauge, g);
      expect(x.fighters[0].autoPicks, 0);
    }
    expect(x.fighters[1].actions, greaterThan(0));
    x.step(never, aiController()); // 50th tick → おまかせ
    expect(x.fighters[0].autoPicks, 1);
  });

  test('invalid inputs (cooldown / no SP / out of range) are ignored', () {
    final r = Mulberry32(3);
    final a = setupAt(s, randomKid(s, r), 50);
    final x = newBattle(s, a, a, seed: 9);
    int? bad(AtbBattle _, int _) => 99;
    while (!x.finished && x.tick < 400) {
      x.step(bad, bad);
    }
    expect(x.fighters[0].autoPicks, greaterThan(0));
  });

  test('every battle ends, before the 3-minute hard cap almost always', () {
    final r = Mulberry32(4);
    var cap = 0;
    for (var i = 0; i < 300; i++) {
      final lv = 1 + r.nextInt(100);
      final a = setupAt(s, randomKid(s, r), lv);
      final b = i.isEven ? a : setupAt(s, randomKid(s, r), lv);
      final x = newBattle(s, a, b, seed: r.nextUint32());
      x.run(aiController(tier: AiTier.weak), aiController(tier: AiTier.weak));
      expect(x.tick, lessThanOrEqualTo(s.hardCapTick));
      if (x.endReason == 'timeUp') cap++;
    }
    expect(cap, lessThan(6));
  });

  test('triangle chart', () {
    expect(typeChart(Attr.gu, Attr.choki, s), 150);
    expect(typeChart(Attr.choki, Attr.pa, s), 150);
    expect(typeChart(Attr.pa, Attr.gu, s), 150);
    expect(typeChart(Attr.choki, Attr.gu, s), 75);
    expect(typeChart(Attr.none, Attr.gu, s), 100);
    expect(typeChart(Attr.gu, Attr.gu, s), 100);
  });

  test('progression helpers', () {
    expect(xpToNext(s, 1), 80);
    expect(xpSinglePlayer(win: true, stage: 10, level: 35), 27);
    expect(
      xpSinglePlayer(win: true, stage: 10, level: 35, hiddenBloomer: true),
      272,
    );
    expect(eloDelta(1000, 1000, true, 48), 24);
    expect(eloDelta(610, 900, false, 48), -8);
    expect(eloDelta(605, 900, false, 48), -5); // rating floor 600
    expect(badgeFor(1000), 'たまご');
    expect(badgeFor(1460), 'ライオン');
    expect(stageTable(), hasLength(100));
    expect(stageTable().where((st) => st.boss), hasLength(10));
  });
}
