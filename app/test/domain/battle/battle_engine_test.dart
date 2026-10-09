import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:flutter_test/flutter_test.dart';

import '_support.dart';

FighterSetup fs(ElementType e, {int level = 1, int spd = 90, int hp = 90}) =>
    FighterSetup(
      element: e,
      level: level,
      stats: Stats(hp: hp, atk: 90, def: 90, spd: spd),
    );

void main() {
  final spec = loadSpecFromFile();
  const t = BattleAction.tackle;
  const el = BattleAction.element;
  const g = BattleAction.guard;
  const sp = BattleAction.special;

  test('initBattle applies the HP multiplier and evolution bonus', () {
    final s = initBattle(
      spec,
      fs(ElementType.fire, level: 20),
      fs(ElementType.leaf, level: 9),
    );
    expect(s.a.maxHp, 90 * spec.hpMultiplier);
    expect(s.a.hp, s.a.maxHp);
    expect(s.a.specialPower, 140);
    expect(s.b.specialPower, 120);
    expect(s.turn, 0);
    expect(s.isOver, isFalse);
  });

  test('resolveTurn is deterministic and does not mutate its input', () {
    final s = initBattle(spec, fs(ElementType.fire), fs(ElementType.water));
    final before = s.toJson();
    final r1 = resolveTurn(spec, s, el, el, Mulberry32(7));
    final r2 = resolveTurn(spec, s, el, el, Mulberry32(7));
    expect(r1.state, r2.state);
    expect(r1.events, r2.events);
    expect(s.toJson(), before);
  });

  test('faster fighter acts first; KO prevents the second actor', () {
    var s = initBattle(
      spec,
      fs(ElementType.fire, spd: 200),
      fs(ElementType.leaf, spd: 10),
    );
    s = s.withFighter(Side.b, s.b.copyWith(hp: 1));
    final r = resolveTurn(spec, s, t, t, Mulberry32(1));
    final moves = r.events.whereType<MoveEvent>().toList();
    expect(moves.single.side, Side.a);
    expect(r.events.whereType<FaintEvent>().single.side, Side.b);
    expect(r.events.last, const BattleEndEvent(Side.a, EndReason.ko));
    expect(r.state.winner, Side.a);
    expect(r.state.endReason, EndReason.ko);
    expect(
      () => resolveTurn(spec, r.state, t, t, Mulberry32(1)),
      throwsStateError,
    );
  });

  test('guard: 50% then diminishing on consecutive use', () {
    var s = initBattle(
      spec,
      fs(ElementType.fire, spd: 100),
      fs(ElementType.water, spd: 80),
    );
    final rng = Mulberry32(3);
    final pcts = <int>[];
    for (var i = 0; i < 4; i++) {
      final r = resolveTurn(spec, s, t, g, rng);
      final guard = r.events.whereType<GuardEvent>().single;
      pcts.add(guard.damageTakenPct);
      expect(guard.weakened, i > 0);
      expect(r.events.whereType<DamageEvent>().single.guarded, isTrue);
      s = r.state;
    }
    expect(pcts, [50, 75, 100, 100]);
    expect(s.b.guardStreak, 4);
    s = resolveTurn(spec, s, t, t, rng).state;
    expect(s.b.guardStreak, 0);
  });

  test('guard reduces damage versus an identical unguarded hit', () {
    final s = initBattle(
      spec,
      fs(ElementType.fire, spd: 100),
      fs(ElementType.water, spd: 80),
    );
    // Same rng seed => same rolls for a's attack (b's move draws nothing
    // before a's attack, and guard draws nothing).
    final guarded = resolveTurn(spec, s, t, g, Mulberry32(11));
    final open = resolveTurn(spec, s, t, t, Mulberry32(11));
    final gd = guarded.events.whereType<DamageEvent>().first.amount;
    final od = open.events.whereType<DamageEvent>().first.amount;
    expect(gd, (od * 50) ~/ 100);
  });

  test('special requires a full gauge and resets it', () {
    final s0 = initBattle(
      spec,
      fs(ElementType.fire, spd: 100),
      fs(ElementType.water, spd: 80),
    );
    final notReady = resolveTurn(spec, s0, sp, t, Mulberry32(1));
    expect(notReady.events, contains(const SpecialNotReadyEvent(Side.a)));
    expect(notReady.events.whereType<MoveEvent>().first.move, t);

    final s1 = s0.withFighter(Side.a, s0.a.copyWith(gauge: 100));
    final r = resolveTurn(spec, s1, sp, t, Mulberry32(1));
    expect(r.events.whereType<MoveEvent>().first.move, sp);
    expect(r.events, contains(const GaugeEvent(Side.a, delta: -100, value: 0)));
    expect(r.state.a.usage.special, 1);
  });

  test('timeout resolves as tackle', () {
    final s = initBattle(spec, fs(ElementType.fire), fs(ElementType.water));
    final r = resolveTurn(spec, s, BattleAction.timeout, g, Mulberry32(1));
    expect(r.events[1], const TimeoutEvent(Side.a));
    expect(r.events.whereType<MoveEvent>().single.move, t);
    expect(r.state.a.lastAction, t);
  });

  test('turn cap ends the battle by HP ratio', () {
    var s = initBattle(spec, fs(ElementType.fire), fs(ElementType.water));
    final rng = Mulberry32(5);
    while (!s.isOver) {
      s = resolveTurn(spec, s, g, g, rng).state;
    }
    expect(s.turn, spec.turnCap);
    expect(s.endReason, EndReason.turnCap);
  });

  test('no infinite battles: random play always ends by the turn cap', () {
    final meta = Mulberry32(2024);
    for (var i = 0; i < 300; i++) {
      final els = ElementType.values;
      var s = initBattle(
        spec,
        FighterSetup(
          element: els[meta.nextInt(6)],
          level: 1 + meta.nextInt(30),
          stats: Stats(
            hp: 1 + meta.nextInt(200),
            atk: 1 + meta.nextInt(200),
            def: 1 + meta.nextInt(200),
            spd: 1 + meta.nextInt(200),
          ),
        ),
        FighterSetup(
          element: els[meta.nextInt(6)],
          level: 1 + meta.nextInt(30),
          stats: Stats(
            hp: 1 + meta.nextInt(200),
            atk: 1 + meta.nextInt(200),
            def: 1 + meta.nextInt(200),
            spd: 1 + meta.nextInt(200),
          ),
        ),
      );
      final rng = Mulberry32(meta.nextUint32());
      while (!s.isOver) {
        final r = resolveTurn(
          spec,
          s,
          BattleAction.values[meta.nextInt(5)],
          BattleAction.values[meta.nextInt(5)],
          rng,
        );
        for (final f in [r.state.a, r.state.b]) {
          expect(f.hp, inInclusiveRange(0, f.maxHp));
          expect(f.gauge, inInclusiveRange(0, spec.gauge.max));
        }
        s = r.state;
      }
      expect(s.turn, lessThanOrEqualTo(spec.turnCap));
      expect(s.winner, isNotNull);
    }
  });

  test('state and events round-trip through JSON', () {
    var s = initBattle(spec, fs(ElementType.shadow), fs(ElementType.rainbow));
    final r = resolveTurn(spec, s, el, el, Mulberry32(8));
    s = r.state;
    expect(BattleState.fromJson(s.toJson()), s);
    for (final e in r.events) {
      expect(BattleEvent.fromJson(e.toJson()), e);
    }
    expect(
      r.events.whereType<EffectivenessEvent>().every((e) => e.isSuper),
      isTrue,
    );
  });

  test('computeDamage: type, crit, guard and min damage', () {
    int dmg({
      int typePct = 100,
      bool crit = false,
      int guard = 100,
      int atk = 90,
    }) => computeDamage(
      spec,
      power: 60,
      atk: atk,
      def: 90,
      typePct: typePct,
      crit: crit,
      variancePct: 100,
      guardTakenPct: guard,
    );
    expect(dmg(typePct: 150), greaterThan(dmg()));
    expect(dmg(typePct: 75), lessThan(dmg()));
    expect(dmg(crit: true), (dmg() * spec.damage.critMultiplierPct) ~/ 100);
    expect(dmg(guard: 50), dmg() ~/ 2);
    expect(dmg(atk: 0, guard: 0), spec.damage.minDamage);
  });
}
