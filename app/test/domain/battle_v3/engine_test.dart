// Engine v3 tests — ATB engine (docs/GAME_DESIGN_V2.md §6, BATTLE_V3.md).
import 'dart:io';

import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V3Spec();
  int? never(Battle _, int _) => null;

  test('same seed → identical battle', () {
    final r = Mulberry32(1);
    final a = setupAt(s, randomKid(s, r), 20);
    final b = setupAt(s, randomKid(s, r), 20);
    Battle run() =>
        Battle(s, a, b, seed: 77)..run(aiController(), aiController());
    final x = run();
    final y = run();
    expect(x.events.map((e) => e.line), y.events.map((e) => e.line));
    expect(x.stateHash(), y.stateHash());
  });

  test('a full gauge waits for the choice; the foe keeps charging', () {
    final r = Mulberry32(2);
    final a = setupAt(s, randomKid(s, r), 10);
    final b = setupAt(s, randomKid(s, r), 10);
    final x = Battle(s, a, b, seed: 5);
    while (x.fighters[0].phase != Phase.ready) {
      x.step(a: never, b: aiController());
    }
    // The ready tick itself counts as the first of the decisionTicks.
    final g = x.fighters[0].gauge;
    expect(x.fighters[0].decisionTicksLeft(s), s.decisionTicks - 1);
    for (var i = 0; i < s.decisionTicks - 2; i++) {
      x.step(a: never, b: aiController());
      expect(x.fighters[0].gauge, g);
      expect(x.fighters[0].autoPicks, 0);
    }
    expect(x.fighters[1].actions, greaterThan(0));
    final ev = x.step(a: never, b: aiController()); // 50th tick → おまかせ
    expect(x.fighters[0].autoPicks, 1);
    expect(
      ev.where((e) => e.type == 'select' && e.i('side') == 0).single.i('auto'),
      1,
    );
  });

  test('さきどり: a queued move fires on the tick the gauge fills', () {
    final r = Mulberry32(6);
    final a = setupAt(s, randomKid(s, r), 10);
    final b = setupAt(s, randomKid(s, r), 10);
    final x = Battle(s, a, b, seed: 8);
    x.queueInput(0, 0); // tapped while charging
    List<BattleEvent> ev = const [];
    while (x.fighters[0].actions == 0) {
      ev = x.step(b: aiController());
    }
    final ready = ev.where((e) => e.type == 'ready' && e.i('side') == 0);
    final select = ev.where((e) => e.type == 'select' && e.i('side') == 0);
    expect(ready, hasLength(1));
    expect(select.single.i('slot'), 0);
    expect(select.single.i('auto'), 0);
    expect(x.fighters[0].queued, isNull);
  });

  test('a later tap replaces the queued one; an unusable one is ignored', () {
    final r = Mulberry32(7);
    final a = setupAt(s, randomKid(s, r), 50);
    final x = Battle(s, a, a, seed: 9);
    x.queueInput(0, 3);
    x.queueInput(0, 9); // replaces slot 3; out of range
    while (x.fighters[0].phase == Phase.charging) {
      x.step(b: aiController());
    }
    expect(x.events.where((e) => e.type == 'inputIgnored'), hasLength(1));
    expect(x.fighters[0].phase, Phase.ready); // still waiting for a choice
  });

  test('invalid controller answers are ignored (timeout picks)', () {
    final r = Mulberry32(3);
    final a = setupAt(s, randomKid(s, r), 50);
    final x = Battle(s, a, a, seed: 9);
    int? bad(Battle _, int _) => 99;
    while (!x.finished && x.tick < 400) {
      x.step(a: bad, b: bad);
    }
    expect(x.fighters[0].autoPicks, greaterThan(0));
  });

  test('renderer events carry hits, misses, crits, effectiveness and KO', () {
    final r = Mulberry32(12);
    final types = <String>{};
    for (var i = 0; i < 40; i++) {
      final g = randomKid(s, r);
      final at = Attr.values[r.nextInt(3)];
      final x = Battle(
        s,
        setupAt(s, g, 30, attr: at),
        setupAt(s, randomKid(s, r), 30, attr: at.beats),
        seed: i,
      )..run(aiController(), aiController());
      types.addAll(x.events.map((e) => e.type));
      final last = x.events.last;
      expect(last.type, 'end');
      if (last.s('reason') == 'ko') {
        expect(x.events[x.events.length - 2].type, 'faint');
      }
      for (final e in x.events.where((e) => e.type == 'hit')) {
        expect(e.i('amount'), greaterThan(0));
        expect(e.i('crit'), anyOf(0, 1));
      }
    }
    expect(
      types,
      containsAll([
        'ready',
        'select',
        'moveStart',
        'hit',
        'miss',
        'effective',
        'faint',
        'end',
      ]),
    );
  });

  test('every battle ends, before the 3-minute hard cap almost always', () {
    final r = Mulberry32(4);
    var cap = 0;
    for (var i = 0; i < 300; i++) {
      final lv = 1 + r.nextInt(100);
      final a = setupAt(s, randomKid(s, r), lv);
      final b = i.isEven ? a : setupAt(s, randomKid(s, r), lv);
      final x = Battle(s, a, b, seed: r.nextUint32(), recordEvents: false);
      x.run(aiController(tier: AiTier.weak), aiController(tier: AiTier.weak));
      expect(x.tick, lessThanOrEqualTo(s.hardCapTick));
      expect(x.winner, anyOf(0, 1)); // no draws
      if (x.endReason == 'timeUp') cap++;
    }
    expect(cap, lessThan(6));
  });

  test('heat-up starts after 60 s and the cap decides by HP ratio', () {
    final r = Mulberry32(13);
    var timeUps = 0;
    for (var i = 0; i < 20 && timeUps < 3; i++) {
      final f = setupAt(s, randomKid(s, r), 60);
      final st = List.of(f.stats);
      st[Stat.str.index] = 2;
      st[Stat.intl.index] = 2;
      st[Stat.def.index] = 999;
      st[Stat.res.index] = 999;
      final t = f.withStats(st);
      final x = Battle(s, t, t, seed: i)..run(aiController(), aiController());
      expect(x.events.where((e) => e.type == 'heatUp').single.tick, 601);
      if (x.endReason != 'timeUp') continue;
      timeUps++;
      expect(x.tick, s.hardCapTick);
      expect(x.heatPct(), 100 + 3 * 120);
      final a = x.fighters[0];
      final b = x.fighters[1];
      if (a.hp * b.maxHp != b.hp * a.maxHp) {
        expect(x.winner, a.hp * b.maxHp > b.hp * a.maxHp ? 0 : 1);
      }
    }
    expect(timeUps, greaterThan(0));
  });

  test('snapshot / restore continues bit-exactly', () {
    final r = Mulberry32(5);
    final a = setupAt(s, randomKid(s, r), 40);
    final b = setupAt(s, randomKid(s, r), 40);
    final full = Battle(s, a, b, seed: 11)
      ..run(aiController(), aiController(tier: AiTier.strong));
    final half = Battle(s, a, b, seed: 11);
    for (var i = 0; i < 150; i++) {
      half.step(
        a: aiController(),
        b: aiController(tier: AiTier.strong),
      );
    }
    final resumed = Battle(s, a, b, seed: 11)..restore(half.snapshot());
    expect(resumed.stateHash(), half.stateHash());
    resumed.run(aiController(), aiController(tier: AiTier.strong));
    expect(resumed.winner, full.winner);
    expect(resumed.tick, full.tick);
    expect(resumed.stateHash(), full.stateHash());
  });

  test('triangle chart', () {
    expect(typeChart(Attr.gu, Attr.choki, s), 150);
    expect(typeChart(Attr.choki, Attr.pa, s), 150);
    expect(typeChart(Attr.pa, Attr.gu, s), 150);
    expect(typeChart(Attr.choki, Attr.gu, s), 75);
    expect(typeChart(Attr.none, Attr.gu, s), 100);
    expect(typeChart(Attr.gu, Attr.gu, s), 100);
  });

  test('the engine is pure Dart (no Flutter imports)', () {
    for (final f in Directory('lib/domain/battle_v3').listSync()) {
      if (f is! File) continue;
      expect(f.readAsStringSync(), isNot(contains('package:flutter')));
    }
  });
}
