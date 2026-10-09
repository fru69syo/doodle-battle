/// Pure turn resolver. Mirrors `shared/battle_engine_ts/src/engine.ts`
/// line by line; see docs/BATTLE.md §3–§5 for the normative rules.
library;

import '../element_type.dart';
import '../stats.dart';
import 'battle_event.dart';
import 'battle_spec.dart';
import 'battle_state.dart';
import 'battle_types.dart';
import 'rng.dart';

/// What a fighter brings into battle: its *current* stats (after growth, see
/// `currentStats`), level and element.
class FighterSetup {
  const FighterSetup({
    required this.element,
    required this.level,
    required this.stats,
  });

  final ElementType element;
  final int level;
  final Stats stats;

  Map<String, Object?> toJson() => {
    'element': element.name,
    'level': level,
    'stats': stats.toJson(),
  };

  factory FighterSetup.fromJson(Map<String, Object?> j) => FighterSetup(
    element: ElementType.fromName(j['element']! as String),
    level: j['level']! as int,
    stats: Stats.fromJson((j['stats']! as Map).cast<String, Object?>()),
  );
}

/// ひっさつ power at [level] including evolution bonuses.
int specialPowerAt(BattleSpec spec, int level) {
  var power = spec.moves.special.power;
  for (final e in spec.growth.evolutions) {
    if (level >= e.level) power += e.specialPowerBonus;
  }
  return power;
}

int _atLeast1(int v) => v < 1 ? 1 : v;

FighterState fighterFromSetup(BattleSpec spec, FighterSetup s) {
  final maxHp = _atLeast1(s.stats.hp) * spec.hpMultiplier;
  return FighterState(
    element: s.element,
    level: s.level,
    maxHp: maxHp,
    hp: maxHp,
    atk: _atLeast1(s.stats.atk),
    def: _atLeast1(s.stats.def),
    spd: _atLeast1(s.stats.spd),
    specialPower: specialPowerAt(spec, s.level),
  );
}

/// Initial state for a new battle.
BattleState initBattle(BattleSpec spec, FighterSetup a, FighterSetup b) =>
    BattleState(a: fighterFromSetup(spec, a), b: fighterFromSetup(spec, b));

/// Deterministic damage for one hit (integer math, floor at every step):
///
/// ```
/// eff  = floor(atk * (atk + k * def) / ((k + 1) * def))   k = defenseWeight
/// pow  = floor(power * typePct / 100) + basePower
/// d    = floor(pow * eff * scalePct / 10000)
/// d    = floor(d * critMultiplierPct / 100)      // only on a crit
/// d    = floor(d * variancePct / 100)
/// d    = floor(d * guardTakenPct / 100)
/// d    = max(minDamage, d)
/// ```
int computeDamage(
  BattleSpec spec, {
  required int power,
  required int atk,
  required int def,
  required int typePct,
  required bool crit,
  required int variancePct,
  required int guardTakenPct,
}) {
  final a = _atLeast1(atk);
  final d0 = _atLeast1(def);
  final k = spec.damage.defenseWeight;
  final eff = (a * (a + k * d0)) ~/ ((k + 1) * d0);
  final pow = (power * typePct) ~/ 100 + spec.damage.basePower;
  var d = (pow * eff * spec.damage.scalePct) ~/ 10000;
  if (crit) d = (d * spec.damage.critMultiplierPct) ~/ 100;
  d = (d * variancePct) ~/ 100;
  d = (d * guardTakenPct) ~/ 100;
  return d < spec.damage.minDamage ? spec.damage.minDamage : d;
}

/// Type multiplier (percent) of [move] used by [attacker] against [defender].
int typeMultiplierPct(
  BattleSpec spec,
  BattleAction move,
  ElementType attacker,
  ElementType defender,
) {
  if (!spec.moves.attack(move).typed) return spec.typeChart.neutralPct;
  return spec.typeChart.multiplierPct(attacker, defender);
}

/// Result of one turn.
typedef TurnResult = ({BattleState state, List<BattleEvent> events});

/// Resolves one turn. Pure apart from consuming values from [rng] (whose
/// state the caller persists between turns).
///
/// RNG draw order (normative):
/// 1. speed tie: `nextInt(2)` iff `a.spd == b.spd` (0 → a acts first);
/// 2. per attacking actor, in action order: accuracy `nextInt(100)` iff
///    accuracy < 100 (hit iff roll < accuracy); then, on hit, crit
///    `nextInt(100)` (crit iff roll < critChancePct); then variance
///    `varianceMinPct + nextInt(varianceMaxPct - varianceMinPct + 1)`;
/// 3. turn-cap HP% tie: `nextInt(2)` (0 → a wins).
TurnResult resolveTurn(
  BattleSpec spec,
  BattleState state,
  BattleAction actionA,
  BattleAction actionB,
  Mulberry32 rng,
) {
  if (state.isOver) {
    throw StateError('battle is already over');
  }
  final turn = state.turn + 1;
  final events = <BattleEvent>[TurnStartEvent(turn)];
  final fighters = <Side, FighterState>{Side.a: state.a, Side.b: state.b};
  final chosen = <Side, BattleAction>{Side.a: actionA, Side.b: actionB};
  final acts = <Side, BattleAction>{};

  // 1. Normalise actions (timeouts, special without full gauge).
  for (final side in Side.values) {
    var act = chosen[side]!;
    if (act == BattleAction.timeout) {
      events.add(TimeoutEvent(side));
      act = spec.timeoutAction;
    }
    if (act == BattleAction.special && fighters[side]!.gauge < spec.gauge.max) {
      events.add(SpecialNotReadyEvent(side));
      act = BattleAction.tackle;
    }
    acts[side] = act;
    final f = fighters[side]!;
    fighters[side] = f.copyWith(
      usage: f.usage.increment(act),
      lastAction: act,
      guardStreak: act == BattleAction.guard ? f.guardStreak + 1 : 0,
    );
  }

  // 2. Action order by speed.
  final spdA = fighters[Side.a]!.spd;
  final spdB = fighters[Side.b]!.spd;
  final Side first;
  if (spdA > spdB) {
    first = Side.a;
  } else if (spdB > spdA) {
    first = Side.b;
  } else {
    first = rng.nextInt(2) == 0 ? Side.a : Side.b;
  }
  final order = [first, first.other];

  void addGauge(Side side, int delta) {
    final f = fighters[side]!;
    var v = f.gauge + delta;
    if (v > spec.gauge.max) v = spec.gauge.max;
    if (v < 0) v = 0;
    final actual = v - f.gauge;
    if (actual == 0) return;
    fighters[side] = f.copyWith(gauge: v);
    events.add(GaugeEvent(side, delta: actual, value: v));
  }

  // 3. Guards take effect before any attack.
  final guardTaken = <Side, int>{Side.a: 100, Side.b: 100};
  for (final side in order) {
    if (acts[side] != BattleAction.guard) continue;
    final streak = fighters[side]!.guardStreak;
    final pct = spec.moves.guard.damageTakenPct(streak);
    guardTaken[side] = pct;
    events.add(GuardEvent(side, damageTakenPct: pct, weakened: streak > 1));
    addGauge(side, spec.gauge.onGuard);
  }

  // 4. Attacks in speed order; a fainted fighter does not act.
  for (final side in order) {
    final move = acts[side]!;
    if (!move.isAttack) continue;
    if (fighters[side]!.fainted) continue;
    final target = side.other;
    final attacker = fighters[side]!;
    final moveSpec = spec.moves.attack(move);
    events.add(
      MoveEvent(side, move, element: moveSpec.typed ? attacker.element : null),
    );
    final power = move == BattleAction.special
        ? attacker.specialPower
        : moveSpec.power;
    if (move == BattleAction.special) {
      addGauge(side, -attacker.gauge);
    }

    if (moveSpec.accuracyPct < 100 &&
        rng.nextInt(100) >= moveSpec.accuracyPct) {
      events.add(MissEvent(side));
      if (move != BattleAction.special) addGauge(side, spec.gauge.onMiss);
      continue;
    }
    final crit = rng.nextInt(100) < spec.damage.critChancePct;
    final variance =
        spec.damage.varianceMinPct +
        rng.nextInt(
          spec.damage.varianceMaxPct - spec.damage.varianceMinPct + 1,
        );
    final defender = fighters[target]!;
    final typePct = typeMultiplierPct(
      spec,
      move,
      attacker.element,
      defender.element,
    );
    final dmg = computeDamage(
      spec,
      power: power,
      atk: attacker.atk,
      def: defender.def,
      typePct: typePct,
      crit: crit,
      variancePct: variance,
      guardTakenPct: guardTaken[target]!,
    );
    if (crit) events.add(CritEvent(side));
    if (typePct != spec.typeChart.neutralPct) {
      events.add(
        EffectivenessEvent(
          side,
          multiplierPct: typePct,
          text: typePct > spec.typeChart.neutralPct
              ? spec.texts['super']!
              : spec.texts['weak']!,
        ),
      );
    }
    final lost = dmg > defender.hp ? defender.hp : dmg;
    final hpAfter = defender.hp - lost;
    fighters[target] = defender.copyWith(hp: hpAfter);
    events.add(
      DamageEvent(
        target,
        amount: lost,
        hp: hpAfter,
        guarded: acts[target] == BattleAction.guard,
      ),
    );
    if (move != BattleAction.special) addGauge(side, spec.gauge.onHit);
    if (hpAfter > 0) {
      addGauge(
        target,
        spec.gauge.onDamagedFlat +
            (lost * spec.gauge.onDamagedPctOfMaxHp) ~/ defender.maxHp,
      );
    } else {
      events.add(FaintEvent(target));
    }
  }

  // 5. End conditions.
  final fa = fighters[Side.a]!;
  final fb = fighters[Side.b]!;
  Side? winner;
  EndReason? reason;
  if (fa.fainted || fb.fainted) {
    winner = fa.fainted ? Side.b : Side.a;
    reason = EndReason.ko;
  } else if (turn >= spec.turnCap) {
    // Compare HP ratios exactly: hpA/maxA vs hpB/maxB.
    final cross = fa.hp * fb.maxHp - fb.hp * fa.maxHp;
    if (cross > 0) {
      winner = Side.a;
    } else if (cross < 0) {
      winner = Side.b;
    } else {
      winner = rng.nextInt(2) == 0 ? Side.a : Side.b;
    }
    reason = EndReason.turnCap;
  }
  if (winner != null) events.add(BattleEndEvent(winner, reason!));

  return (
    state: BattleState(
      a: fa,
      b: fb,
      turn: turn,
      winner: winner,
      endReason: reason,
    ),
    events: List.unmodifiable(events),
  );
}
