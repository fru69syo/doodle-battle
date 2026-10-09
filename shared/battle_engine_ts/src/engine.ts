/**
 * Pure turn resolver; line-by-line port of
 * app/lib/domain/battle/battle_engine.dart. See docs/BATTLE.md §3–§5.
 */
import type { Mulberry32 } from './rng';
import type { BattleSpec, AttackMoveSpec } from './spec';
import type {
  AttackMove, BattleAction, BattleEvent, BattleMove, BattleState, ElementType,
  EndReason, FighterSetup, FighterState, MoveUsage, Side, TurnResult,
} from './types';
import { isAttack, other } from './types';

/** floor(a / b) for non-negative integers (exact below 2^53). */
export const idiv = (a: number, b: number): number => Math.floor(a / b);
const atLeast1 = (v: number): number => (v < 1 ? 1 : v);

/** ひっさつ power at `level` including evolution bonuses. */
export function specialPowerAt(spec: BattleSpec, level: number): number {
  let power = spec.moves.special.power;
  for (const e of spec.growth.evolutions) if (level >= e.level) power += e.specialPowerBonus;
  return power;
}

export function fighterFromSetup(spec: BattleSpec, s: FighterSetup): FighterState {
  const maxHp = atLeast1(s.stats.hp) * spec.hpMultiplier;
  return {
    element: s.element,
    level: s.level,
    maxHp,
    hp: maxHp,
    atk: atLeast1(s.stats.atk),
    def: atLeast1(s.stats.def),
    spd: atLeast1(s.stats.spd),
    specialPower: specialPowerAt(spec, s.level),
    gauge: 0,
    guardStreak: 0,
    usage: { tackle: 0, element: 0, guard: 0, special: 0 },
    lastAction: null,
  };
}

/** Initial state for a new battle. */
export function initBattle(spec: BattleSpec, a: FighterSetup, b: FighterSetup): BattleState {
  return { turn: 0, a: fighterFromSetup(spec, a), b: fighterFromSetup(spec, b), winner: null, endReason: null };
}

export function attackSpec(spec: BattleSpec, move: AttackMove): AttackMoveSpec {
  return spec.moves[move];
}

export interface DamageInput {
  power: number;
  atk: number;
  def: number;
  typePct: number;
  crit: boolean;
  variancePct: number;
  guardTakenPct: number;
}

/**
 * eff = floor(atk * (atk + k*def) / ((k+1) * def)),  k = defenseWeight
 * pow = floor(power * typePct / 100) + basePower
 * d   = floor(pow * eff * scalePct / 10000)
 * d   = floor(d * critMultiplierPct / 100)   (crit only)
 * d   = floor(d * variancePct / 100)
 * d   = floor(d * guardTakenPct / 100)
 * d   = max(minDamage, d)
 */
export function computeDamage(spec: BattleSpec, i: DamageInput): number {
  const a = atLeast1(i.atk);
  const d0 = atLeast1(i.def);
  const k = spec.damage.defenseWeight;
  const eff = idiv(a * (a + k * d0), (k + 1) * d0);
  const pow = idiv(i.power * i.typePct, 100) + spec.damage.basePower;
  let d = idiv(pow * eff * spec.damage.scalePct, 10000);
  if (i.crit) d = idiv(d * spec.damage.critMultiplierPct, 100);
  d = idiv(d * i.variancePct, 100);
  d = idiv(d * i.guardTakenPct, 100);
  return d < spec.damage.minDamage ? spec.damage.minDamage : d;
}

/** Type multiplier (percent) of `move` by `attacker` against `defender`. */
export function typeMultiplierPct(spec: BattleSpec, move: AttackMove, attacker: ElementType, defender: ElementType): number {
  if (!attackSpec(spec, move).typed) return spec.typeChart.neutralPct;
  return spec.typeChart.matrix[attacker][defender];
}

export function guardDamageTakenPct(spec: BattleSpec, streak: number): number {
  const t = spec.moves.guard.damageTakenPctByStreak;
  const i = streak - 1;
  return t[i < t.length ? i : t.length - 1]!;
}

function incrementUsage(u: MoveUsage, m: BattleMove): MoveUsage {
  return { ...u, [m]: u[m] + 1 };
}

/**
 * Resolves one turn. Consumes `rng` in the normative order documented in
 * docs/BATTLE.md (speed tie, then per attacker: accuracy (<100 only), crit,
 * variance; finally the turn-cap HP% tie).
 */
export function resolveTurn(
  spec: BattleSpec,
  state: BattleState,
  actionA: BattleAction,
  actionB: BattleAction,
  rng: Mulberry32,
): TurnResult {
  if (state.winner !== null) throw new Error('battle is already over');
  const turn = state.turn + 1;
  const events: BattleEvent[] = [{ type: 'turnStart', turn }];
  const f: Record<Side, FighterState> = { a: state.a, b: state.b };
  const chosen: Record<Side, BattleAction> = { a: actionA, b: actionB };
  const acts = {} as Record<Side, BattleMove>;

  // 1. Normalise actions.
  for (const side of ['a', 'b'] as const) {
    let act = chosen[side];
    if (act === 'timeout') {
      events.push({ type: 'timeout', side });
      act = spec.timeoutAction;
    }
    if (act === 'special' && f[side].gauge < spec.gauge.max) {
      events.push({ type: 'specialNotReady', side });
      act = 'tackle';
    }
    const move = act as BattleMove;
    acts[side] = move;
    const cur = f[side];
    f[side] = {
      ...cur,
      usage: incrementUsage(cur.usage, move),
      lastAction: move,
      guardStreak: move === 'guard' ? cur.guardStreak + 1 : 0,
    };
  }

  // 2. Order by speed.
  let first: Side;
  if (f.a.spd > f.b.spd) first = 'a';
  else if (f.b.spd > f.a.spd) first = 'b';
  else first = rng.nextInt(2) === 0 ? 'a' : 'b';
  const order: Side[] = [first, other(first)];

  const addGauge = (side: Side, delta: number): void => {
    const cur = f[side];
    let v = cur.gauge + delta;
    if (v > spec.gauge.max) v = spec.gauge.max;
    if (v < 0) v = 0;
    const actual = v - cur.gauge;
    if (actual === 0) return;
    f[side] = { ...cur, gauge: v };
    events.push({ type: 'gauge', side, delta: actual, value: v });
  };

  // 3. Guards first.
  const guardTaken: Record<Side, number> = { a: 100, b: 100 };
  for (const side of order) {
    if (acts[side] !== 'guard') continue;
    const streak = f[side].guardStreak;
    const pct = guardDamageTakenPct(spec, streak);
    guardTaken[side] = pct;
    events.push({ type: 'guard', side, damageTakenPct: pct, weakened: streak > 1 });
    addGauge(side, spec.gauge.onGuard);
  }

  // 4. Attacks in speed order; fainted fighters do not act.
  for (const side of order) {
    const move = acts[side];
    if (!isAttack(move)) continue;
    if (f[side].hp <= 0) continue;
    const target = other(side);
    const attacker = f[side];
    const ms = attackSpec(spec, move);
    events.push({ type: 'move', side, move, element: ms.typed ? attacker.element : null });
    const power = move === 'special' ? attacker.specialPower : ms.power;
    if (move === 'special') addGauge(side, -attacker.gauge);

    if (ms.accuracyPct < 100 && rng.nextInt(100) >= ms.accuracyPct) {
      events.push({ type: 'miss', side });
      if (move !== 'special') addGauge(side, spec.gauge.onMiss);
      continue;
    }
    const crit = rng.nextInt(100) < spec.damage.critChancePct;
    const variance =
      spec.damage.varianceMinPct + rng.nextInt(spec.damage.varianceMaxPct - spec.damage.varianceMinPct + 1);
    const defender = f[target];
    const typePct = typeMultiplierPct(spec, move, attacker.element, defender.element);
    const dmg = computeDamage(spec, {
      power,
      atk: attacker.atk,
      def: defender.def,
      typePct,
      crit,
      variancePct: variance,
      guardTakenPct: guardTaken[target],
    });
    if (crit) events.push({ type: 'crit', side });
    if (typePct !== spec.typeChart.neutralPct) {
      events.push({
        type: 'effectiveness',
        side,
        multiplierPct: typePct,
        text: typePct > spec.typeChart.neutralPct ? spec.texts['super']! : spec.texts['weak']!,
      });
    }
    const lost = dmg > defender.hp ? defender.hp : dmg;
    const hpAfter = defender.hp - lost;
    f[target] = { ...defender, hp: hpAfter };
    events.push({ type: 'damage', target, amount: lost, hp: hpAfter, guarded: acts[target] === 'guard' });
    if (move !== 'special') addGauge(side, spec.gauge.onHit);
    if (hpAfter > 0) {
      addGauge(target, spec.gauge.onDamagedFlat + idiv(lost * spec.gauge.onDamagedPctOfMaxHp, defender.maxHp));
    } else {
      events.push({ type: 'faint', side: target });
    }
  }

  // 5. End conditions.
  let winner: Side | null = null;
  let reason: EndReason | null = null;
  if (f.a.hp <= 0 || f.b.hp <= 0) {
    winner = f.a.hp <= 0 ? 'b' : 'a';
    reason = 'ko';
  } else if (turn >= spec.turnCap) {
    const cross = f.a.hp * f.b.maxHp - f.b.hp * f.a.maxHp;
    if (cross > 0) winner = 'a';
    else if (cross < 0) winner = 'b';
    else winner = rng.nextInt(2) === 0 ? 'a' : 'b';
    reason = 'turnCap';
  }
  if (winner !== null && reason !== null) events.push({ type: 'battleEnd', winner, reason });

  return { state: { turn, a: f.a, b: f.b, winner, endReason: reason }, events };
}
