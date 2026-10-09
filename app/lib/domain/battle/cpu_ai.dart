/// CPU / ghost opponent AI (SPEC §4.3). Deterministic given the state and the
/// rng; mirrors `shared/battle_engine_ts/src/ai.ts`. Use a dedicated rng
/// stream (see `deriveSeed`) so AI draws never perturb battle draws.
library;

import 'battle_engine.dart';
import 'battle_spec.dart';
import 'battle_state.dart';
import 'battle_types.dart';
import 'rng.dart';

/// Chooses the action of [self] for the next turn.
BattleAction chooseCpuAction(
  BattleSpec spec,
  BattleState state,
  Side self,
  AiTier tier,
  Mulberry32 rng,
) {
  final me = state.fighter(self);
  final opp = state.fighter(self.other);
  final ready = me.gauge >= spec.gauge.max;
  switch (tier) {
    case AiTier.weak:
      return _weak(spec, ready, rng);
    case AiTier.normal:
      return _normal(spec, me, opp, ready, rng);
    case AiTier.strong:
      return _strong(spec, me, opp, ready, rng);
  }
}

/// よわい: weighted random pick (tackle, element, guard, special-if-ready).
BattleAction _weak(BattleSpec spec, bool ready, Mulberry32 rng) {
  final w = spec.ai.weak;
  final weights = [
    (BattleAction.tackle, w.tackleWeight),
    (BattleAction.element, w.elementWeight),
    (BattleAction.guard, w.guardWeight),
    (BattleAction.special, ready ? w.specialWeight : 0),
  ];
  final total = weights.fold<int>(0, (a, e) => a + e.$2);
  var r = rng.nextInt(total);
  for (final (action, weight) in weights) {
    if (r < weight) return action;
    r -= weight;
  }
  return BattleAction.tackle; // unreachable
}

/// ふつう: special when ready; otherwise a small chance to guard (not twice
/// in a row); element move unless it is not very effective.
BattleAction _normal(
  BattleSpec spec,
  FighterState me,
  FighterState opp,
  bool ready,
  Mulberry32 rng,
) {
  if (ready) return BattleAction.special;
  if (me.guardStreak == 0 && rng.nextInt(100) < spec.ai.normal.guardChancePct) {
    return BattleAction.guard;
  }
  final typePct = spec.typeChart.multiplierPct(me.element, opp.element);
  return typePct < spec.typeChart.neutralPct
      ? BattleAction.tackle
      : BattleAction.element;
}

/// Damage of [move] by [att] on [def] without crit at the given variance and
/// guard percentages.
int _damage(
  BattleSpec spec,
  FighterState att,
  FighterState def,
  BattleAction move,
  int variancePct,
  int guardTakenPct,
) {
  final power = move == BattleAction.special
      ? att.specialPower
      : spec.moves.attack(move).power;
  return computeDamage(
    spec,
    power: power,
    atk: att.atk,
    def: def.def,
    typePct: typeMultiplierPct(spec, move, att.element, def.element),
    crit: false,
    variancePct: variancePct,
    guardTakenPct: guardTakenPct,
  );
}

/// Better of tackle / element by expected damage factor
/// `(floor(power * typePct / 100) + basePower) * accuracyPct`
/// (element only if strictly greater).
BattleAction _bestBasic(BattleSpec spec, FighterState me, FighterState opp) {
  int score(BattleAction move) {
    final m = spec.moves.attack(move);
    final typePct = typeMultiplierPct(spec, move, me.element, opp.element);
    return ((m.power * typePct) ~/ 100 + spec.damage.basePower) * m.accuracyPct;
  }

  return score(BattleAction.element) > score(BattleAction.tackle)
      ? BattleAction.element
      : BattleAction.tackle;
}

/// つよい: reads HP, gauges and the opponent's habits.
BattleAction _strong(
  BattleSpec spec,
  FighterState me,
  FighterState opp,
  bool ready,
  Mulberry32 rng,
) {
  final s = spec.ai.strong;
  final vMin = spec.damage.varianceMinPct;
  final vMax = spec.damage.varianceMaxPct;
  // 1. Finish the opponent with a sure KO (no rng).
  for (final move in [
    BattleAction.tackle,
    if (ready) BattleAction.special,
    BattleAction.element,
  ]) {
    if (_damage(spec, me, opp, move, vMin, 100) >= opp.hp) return move;
  }
  // 2. The opponent's ひっさつ is ready and could KO us, but まもる would let
  //    us survive: brace.
  if (opp.gauge >= spec.gauge.max && me.guardStreak == 0) {
    final guardPct = spec.moves.guard.damageTakenPct(1);
    final threat =
        _damage(spec, opp, me, BattleAction.special, vMax, 100) >= me.hp;
    final survivable =
        _damage(spec, opp, me, BattleAction.special, vMax, guardPct) < me.hp;
    if (threat && survivable && rng.nextInt(100) < s.guardVsSpecialPct) {
      return BattleAction.guard;
    }
  }
  // 3. Use ひっさつ unless the opponent is a habitual guarder who is likely
  //    to guard now (did not guard last turn).
  if (ready) {
    final total = opp.usage.total;
    final guarder =
        total >= s.opponentGuardMinSamples &&
        opp.usage.guard * 100 >= total * s.opponentGuardRatePct &&
        opp.guardStreak == 0;
    if (!guarder) return BattleAction.special;
  }
  // 4. Best basic attack.
  return _bestBasic(spec, me, opp);
}
