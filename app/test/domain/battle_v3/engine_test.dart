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

  test('bars keep filling up to max bars, then stop; the foe never waits', () {
    final r = Mulberry32(2);
    final a = setupAt(s, randomKid(s, r), 10);
    final b = setupAt(s, randomKid(s, r), 10);
    final x = Battle(s, a, b, seed: 5);
    final f = x.fighters[0];
    var bars = 0;
    var steps = 0;
    while (f.bars < f.maxBars) {
      final ev = x.step(a: never, b: aiController());
      steps++;
      for (final e in ev.where((e) => e.type == 'bar' && e.i('side') == 0)) {
        expect(e.i('bars'), ++bars);
      }
    }
    expect(bars, f.maxBars);
    expect(f.gauge, f.maxBars * s.gaugeMax);
    expect(steps, greaterThan(f.maxBars * 30));
    expect(x.fighters[1].actions, greaterThan(0));
    // Idle at the cap: nothing more fills, nothing is picked for the kid.
    for (var i = 0; i < 80 && !x.finished; i++) {
      final ev = x.step(a: never, b: aiController());
      expect(f.gauge, f.maxBars * s.gaugeMax);
      expect(ev.where((e) => e.type == 'select' && e.i('side') == 0), isEmpty);
    }
    expect(f.actions, 0);
    expect(f.waitTicks, greaterThan(80));
  });

  test('a move costs its bars; the rest of the gauge stays', () {
    final r = Mulberry32(14);
    final a = setupAt(s, randomKid(s, r), 20);
    final x = Battle(s, a, a, seed: 3);
    final f = x.fighters[0];
    while (f.bars < 2) {
      x.step(a: never, b: never);
    }
    final before = f.gauge;
    x.queueInput(0, 0); // slot 0 costs 1 bar
    final ev = x.step(a: never, b: never);
    final sel = ev.where((e) => e.type == 'select' && e.i('side') == 0).single;
    expect(sel.i('cost'), 1);
    expect(f.gauge, before + x.fillRate(0) - s.gaugeMax);
  });

  test('さきどり: a queued move fires on the tick its bars are there', () {
    final r = Mulberry32(6);
    final g = randomKid(s, r);
    final a = setupAt(s, g, 60);
    final x = Battle(s, a, setupAt(s, randomKid(s, r), 60), seed: 8);
    final big = a.moves.length - 1; // ひっさつ: costs max bars
    expect(a.moves[big].bars, a.maxBars);
    x.queueInput(0, big); // tapped with an empty gauge
    while (x.fighters[0].actions == 0) {
      final ev = x.step(b: aiController());
      final sel = ev.where((e) => e.type == 'select' && e.i('side') == 0);
      if (sel.isNotEmpty) {
        expect(sel.single.i('slot'), big);
        expect(
          ev.where((e) => e.type == 'bar' && e.i('side') == 0),
          isNotEmpty,
        );
        expect(x.fighters[0].gauge, lessThan(s.gaugeMax));
      }
    }
    expect(x.fighters[0].queued, isNull);
  });

  test('a later tap replaces the queued one; an impossible one is dropped', () {
    final r = Mulberry32(7);
    final a = setupAt(s, randomKid(s, r), 50);
    final x = Battle(s, a, a, seed: 9);
    x.queueInput(0, 3);
    x.queueInput(0, 9); // replaces slot 3; out of range
    x.step(b: aiController());
    expect(x.events.where((e) => e.type == 'inputIgnored'), hasLength(1));
    expect(x.fighters[0].queued, isNull);
    x.queueInput(0, 1);
    x.queueInput(0, 0); // the newer input wins
    while (x.fighters[0].actions == 0) {
      x.step(b: aiController());
    }
    expect(
      x.events
          .firstWhere((e) => e.type == 'select' && e.i('side') == 0)
          .i('slot'),
      0,
    );
  });

  test('a move costing more than max bars can never be queued or used', () {
    final r = Mulberry32(8);
    final f = setupAt(s, randomKid(s, r), 20);
    expect(
      () => Battle(
        s,
        FighterSetup(
          stats: f.stats,
          attr: f.attr,
          maxBars: 2,
          moves: [f.moves[0], f.moves[1].copyWith(bars: 3)],
        ),
        f,
        seed: 1,
      ),
      throwsArgumentError,
    );
  });

  test('invalid controller answers are ignored; no timer picks for anyone', () {
    final r = Mulberry32(3);
    final a = setupAt(s, randomKid(s, r), 50);
    final x = Battle(s, a, a, seed: 9);
    int? bad(Battle _, int _) => 99;
    while (!x.finished && x.tick < 400) {
      x.step(a: bad, b: bad);
    }
    expect(x.fighters[0].actions, 0);
    expect(x.fighters[1].actions, 0);
  });

  test('おまかせ: random eligible plan, waits for its bars, picks again', () {
    final r = Mulberry32(15);
    final a = setupAt(s, randomKid(s, r), 60);
    final x = Battle(s, a, setupAt(s, randomKid(s, r), 60), seed: 4);
    final om = omakaseController();
    final used = <int>{};
    while (!x.finished && x.tick < 1200) {
      final plan = x.fighters[0].aiPlan;
      final ev = x.step(a: om, b: aiController());
      for (final e in ev.where((e) => e.type == 'select' && e.i('side') == 0)) {
        expect(e.i('slot'), plan ?? e.i('slot'));
        used.add(e.i('slot')!);
        expect(x.fighters[0].aiPlan, isNull);
      }
    }
    expect(used.length, greaterThan(1));
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
        'bar',
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
