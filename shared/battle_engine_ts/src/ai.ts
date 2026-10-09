/** CPU / ghost AI; port of cpu_ai.dart. Use a dedicated rng stream (deriveSeed). */
import { computeDamage, guardDamageTakenPct, typeMultiplierPct, idiv } from './engine';
import type { Mulberry32 } from './rng';
import type { BattleSpec } from './spec';
import type { AiTier, AttackMove, BattleMove, BattleState, FighterState, Side } from './types';
import { other } from './types';

export function chooseCpuAction(
  spec: BattleSpec,
  state: BattleState,
  self: Side,
  tier: AiTier,
  rng: Mulberry32,
): BattleMove {
  const me = state[self];
  const opp = state[other(self)];
  const ready = me.gauge >= spec.gauge.max;
  switch (tier) {
    case 'weak':
      return weak(spec, ready, rng);
    case 'normal':
      return normal(spec, me, opp, ready, rng);
    case 'strong':
      return strong(spec, me, opp, ready, rng);
  }
}

function weak(spec: BattleSpec, ready: boolean, rng: Mulberry32): BattleMove {
  const w = spec.ai.weak;
  const weights: [BattleMove, number][] = [
    ['tackle', w.tackleWeight],
    ['element', w.elementWeight],
    ['guard', w.guardWeight],
    ['special', ready ? w.specialWeight : 0],
  ];
  const total = weights.reduce((a, e) => a + e[1], 0);
  let r = rng.nextInt(total);
  for (const [action, weight] of weights) {
    if (r < weight) return action;
    r -= weight;
  }
  return 'tackle';
}

function normal(spec: BattleSpec, me: FighterState, opp: FighterState, ready: boolean, rng: Mulberry32): BattleMove {
  if (ready) return 'special';
  if (me.guardStreak === 0 && rng.nextInt(100) < spec.ai.normal.guardChancePct) return 'guard';
  const typePct = spec.typeChart.matrix[me.element][opp.element];
  return typePct < spec.typeChart.neutralPct ? 'tackle' : 'element';
}

function damage(spec: BattleSpec, att: FighterState, def: FighterState, move: AttackMove, variancePct: number, guardTakenPct: number): number {
  return computeDamage(spec, {
    power: move === 'special' ? att.specialPower : spec.moves[move].power,
    atk: att.atk,
    def: def.def,
    typePct: typeMultiplierPct(spec, move, att.element, def.element),
    crit: false,
    variancePct,
    guardTakenPct,
  });
}

function bestBasic(spec: BattleSpec, me: FighterState, opp: FighterState): BattleMove {
  const score = (move: 'tackle' | 'element'): number => {
    const m = spec.moves[move];
    const typePct = typeMultiplierPct(spec, move, me.element, opp.element);
    return (idiv(m.power * typePct, 100) + spec.damage.basePower) * m.accuracyPct;
  };
  return score('element') > score('tackle') ? 'element' : 'tackle';
}

function strong(spec: BattleSpec, me: FighterState, opp: FighterState, ready: boolean, rng: Mulberry32): BattleMove {
  const s = spec.ai.strong;
  const vMin = spec.damage.varianceMinPct;
  const vMax = spec.damage.varianceMaxPct;
  const koMoves: AttackMove[] = ready ? ['tackle', 'special', 'element'] : ['tackle', 'element'];
  for (const move of koMoves) {
    if (damage(spec, me, opp, move, vMin, 100) >= opp.hp) return move;
  }
  if (opp.gauge >= spec.gauge.max && me.guardStreak === 0) {
    const guardPct = guardDamageTakenPct(spec, 1);
    const threat = damage(spec, opp, me, 'special', vMax, 100) >= me.hp;
    const survivable = damage(spec, opp, me, 'special', vMax, guardPct) < me.hp;
    if (threat && survivable && rng.nextInt(100) < s.guardVsSpecialPct) return 'guard';
  }
  if (ready) {
    const u = opp.usage;
    const total = u.tackle + u.element + u.guard + u.special;
    const guarder =
      total >= s.opponentGuardMinSamples && u.guard * 100 >= total * s.opponentGuardRatePct && opp.guardStreak === 0;
    if (!guarder) return 'special';
  }
  return bestBasic(spec, me, opp);
}
