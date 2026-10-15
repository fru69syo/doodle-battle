/**
 * Battle AI with stackable gauge bars: the kid's 「おまかせ」 switch (random
 * move, then wait for its bars) and the tiered CPU / ghost AI that reasons
 * about bars. Bit-exact port of app/lib/domain/battle_v3/ai.dart.
 */
import type { Battle, Controller, Fighter } from './engine';
import {
  DEBUFF_SECONDARY_VALUE,
  isDamage,
  kindOf,
  type Move,
  moveValue,
  PARALYZE_VALUE,
  POISON_VALUE,
  statusOf,
} from './moves';
import type { Mulberry32 } from './rng';
import { idiv, Stat, tdiv } from './spec';

export type AiTier = 'weak' | 'normal' | 'strong';
export const AI_TIERS: Readonly<Record<AiTier, { randomPct: number; thinkTicks: number; saveBars: number; label: string }>> = {
  weak: { randomPct: 40, thinkTicks: 10, saveBars: 0, label: 'よわい' },
  normal: { randomPct: 20, thinkTicks: 10, saveBars: 1, label: 'ふつう' },
  strong: { randomPct: 0, thinkTicks: 4, saveBars: 5, label: 'つよい' },
};

const MIN_SCORE = -(2 ** 52);

/** Slots `side` may plan for: off cooldown, cost ≤ max bars. */
export function eligibleSlots(b: Battle, side: number): number[] {
  const f = b.fighters[side]!;
  const out: number[] = [];
  for (let i = 0; i < f.moves.length; i++) if (f.eligible(i)) out.push(i);
  return out;
}

/** おまかせ: a uniformly random eligible move (`nextInt(count)`). */
export function omakasePick(b: Battle, side: number, rng: Mulberry32): number {
  const e = eligibleSlots(b, side);
  if (e.length === 0) return 0;
  return e[rng.nextInt(e.length)]!;
}

/** The kid's おまかせ switch: random plan, wait for its bars, use, re-pick. */
export function omakaseController(): Controller {
  return (b, side) => {
    const f = b.fighters[side]!;
    if (f.aiPlan === null) f.aiPlan = omakasePick(b, side, b.aiRng[side]!);
    const p = f.aiPlan;
    return f.usable(p) ? p : null;
  };
}

/** Plans a move (see ai.dart `chooseMove`): random with randomPct, else `bestMove`. */
export function chooseMove(b: Battle, side: number, rng: Mulberry32, tier: AiTier = 'normal'): number {
  const e = eligibleSlots(b, side);
  if (e.length === 0) return 0;
  const roll = rng.nextInt(100);
  if (roll < AI_TIERS[tier].randomPct) return e[rng.nextInt(e.length)]!;
  return bestMove(b, side, tier);
}

/** Best-scoring eligible move within the tier's saving horizon. */
export function bestMove(b: Battle, side: number, tier: AiTier = 'normal'): number {
  const f = b.fighters[side]!;
  const reach = f.bars + AI_TIERS[tier].saveBars;
  const e = eligibleSlots(b, side).filter((i) => i === 0 || f.moves[i]!.bars <= reach);
  if (e.length === 0) return 0;
  let best = e[0]!;
  let bestScore = MIN_SCORE;
  for (const i of e) {
    const s = tier === 'strong' ? scoreMoveStrong(b, side, i) : scoreMove(b, side, i);
    if (s > bestScore) {
      bestScore = s;
      best = i;
    }
  }
  return best;
}

/** One decision of the tiered AI (see ai.dart `aiDecide`). */
export function aiDecide(b: Battle, side: number, tier: AiTier, think: number): number | null {
  const f = b.fighters[side]!;
  if (f.bars < 1 || f.waitTicks < think) return null;
  if (tier === 'strong') {
    f.aiPlan = bestMove(b, side, tier);
  } else {
    if (f.aiPlan === null) f.aiPlan = chooseMove(b, side, b.aiRng[side]!, tier);
    if (tier === 'normal' && !f.usable(f.aiPlan)) {
      const ko = finisherNow(b, side);
      if (ko !== null) f.aiPlan = ko;
    }
  }
  const p = f.aiPlan;
  return f.usable(p) ? p : null;
}

export function aiController(opts: { thinkTicks?: number; tier?: AiTier } = {}): Controller {
  const tier = opts.tier ?? 'normal';
  const think = opts.thinkTicks ?? AI_TIERS[tier].thinkTicks;
  return (b, side) => aiDecide(b, side, tier, think);
}

const pts = (points: number, maxHp: number) => idiv(points * maxHp, 1000);

/** Ticks for one bar at the current rates. */
export function barTicks(b: Battle, side: number): number {
  const r = b.fillRate(side);
  return r <= 0 ? b.spec.gaugeMax : idiv(b.spec.gaugeMax + r - 1, r);
}

/** Ticks until `side` has `bars` full bars (0 = now). */
export function ticksToBars(b: Battle, side: number, bars: number): number {
  const f = b.fighters[side]!;
  const need = bars * b.spec.gaugeMax - f.gauge;
  if (need <= 0) return 0;
  const r = b.fillRate(side);
  return r <= 0 ? 1 << 20 : idiv(need + r - 1, r);
}

function finisherNow(b: Battle, side: number): number | null {
  const f = b.fighters[side]!;
  const foe = b.fighters[1 - side]!;
  let best: number | null = null;
  for (let i = 0; i < f.moves.length; i++) {
    const m = f.moves[i]!;
    if (!isDamage(m) || !f.usable(i)) continue;
    const per = b.baseHitDamage(side, 1 - side, m);
    let e = idiv(per * m.hits * m.accuracy * 95, 10000);
    e = idiv(e * (100 - foe.shieldPct), 100);
    if (e >= foe.hp && (best === null || m.bars < f.moves[best]!.bars)) best = i;
  }
  return best;
}

function secondaryValue(m: Move, me: Fighter, foe: Fighter): number {
  switch (m.secondary) {
    case 'poison':
      return foe.poisonTicks === 0 ? idiv(m.secondaryChance * POISON_VALUE, 100) : 0;
    case 'paralyze':
      return foe.paralyzeTicks === 0 ? idiv(m.secondaryChance * PARALYZE_VALUE, 100) : 0;
    case 'debuff':
      return idiv(m.secondaryChance * DEBUFF_SECONDARY_VALUE, 100);
    case 'drain':
      return me.hp * 2 < me.maxHp ? idiv(m.drainPct * m.power, 100) : 0;
    default:
      return 0;
  }
}

/** ふつう / よわい: HP value per bar (×100), ×0.97 when it must be saved for. */
export function scoreMove(b: Battle, side: number, slot: number): number {
  const s = b.spec;
  const me = b.fighters[side]!;
  const foe = b.fighters[1 - side]!;
  const m = me.moves[slot]!;
  const t = 1 - side;
  const now = me.gauge >= m.bars * s.gaugeMax;
  let v = 0;
  switch (kindOf(m)) {
    case 'physical':
    case 'special': {
      const per = b.baseHitDamage(side, t, m);
      let e = idiv(per * m.hits * m.accuracy * 95, 10000);
      e = idiv(e * (100 - foe.shieldPct), 100);
      if (e >= foe.hp) {
        if (now) return 1000000000 - m.bars * 1000 - m.castTicks;
        e = foe.hp;
      }
      v = e + pts(secondaryValue(m, me, foe), foe.maxHp);
      break;
    }
    case 'heal': {
      const missing = me.maxHp - me.hp;
      const est = idiv(me.maxHp * m.healPct, 100);
      const amt = est < missing ? est : missing;
      const hpPct = idiv(me.hp * 100, me.maxHp);
      v = hpPct < 50 ? idiv(amt * 12, 10) : hpPct < 75 ? idiv(amt * 3, 10) : 0;
      break;
    }
    case 'buff':
      v = me.stages[m.stat]! > 0 || me.hp * 100 < me.maxHp * 40 ? 0 : idiv(pts(moveValue(m), foe.maxHp) * 8, 10);
      break;
    case 'debuff':
      v = foe.stages[m.stat]! < 0 ? 0 : idiv(pts(moveValue(m), foe.maxHp) * 8, 10);
      break;
    case 'status': {
      const has = statusOf(m) === 'poison' ? foe.poisonTicks > 0 : foe.paralyzeTicks > 0;
      v = has ? 0 : pts(moveValue(m), foe.maxHp);
      break;
    }
    case 'shield': {
      const threat = (foe.phase === 'casting' && foe.castLeft >= 2) || foe.bars >= 2;
      v = me.shieldPct > 0 ? 0 : idiv(pts(moveValue(m), foe.maxHp) * (threat ? 20 : 3), 10);
      break;
    }
  }
  let score = tdiv((v - pts(m.castTicks, foe.maxHp)) * 100, m.bars);
  if (!now) score = tdiv(score * 97, 100);
  return score;
}

function heatAt(b: Battle, tick: number): number {
  const s = b.spec;
  return tick <= s.heatUpStartTick ? 100 : 100 + s.heatUpPctPerSecond * idiv(tick - s.heatUpStartTick, s.tickHz);
}

/** Expected damage of one use, now or `inTicks` from now (see ai.dart). */
export function expectedDamage(b: Battle, side: number, m: Move, inTicks = 0): number {
  const s = b.spec;
  const t = 1 - side;
  const foe = b.fighters[t]!;
  const per = b.baseHitDamage(side, t, m);
  const hit = b.hitChance(side, t, m.accuracy);
  const crit = b.critMille(side, t, m.critBonus);
  const meanVar = s.varianceMinPct + idiv(s.varianceSpan - 1, 2);
  let e = idiv(per * m.hits * hit * (1000 + idiv(crit * (s.critMultiplierPct - 100), 100)), 100000);
  e = idiv(e * meanVar, 100);
  if (foe.shieldTicks > inTicks) e = idiv(e * (100 - foe.shieldPct), 100);
  return idiv(e * heatAt(b, b.tick + inTicks), 100);
}

/** Most damage the opponent of `side` can deal with one move within `ticks`. */
export function foeThreatWithin(b: Battle, side: number, ticks: number): number {
  const t = 1 - side;
  const foe = b.fighters[t]!;
  if (foe.phase === 'casting') {
    const m = foe.moves[foe.castSlot]!;
    return isDamage(m) ? expectedDamage(b, t, m) : 0;
  }
  let best = 0;
  for (let i = 0; i < foe.moves.length; i++) {
    const m = foe.moves[i]!;
    if (!isDamage(m) || !foe.canQueue(i)) continue;
    if (foe.cooldowns[i]! > ticks) continue;
    if (ticksToBars(b, t, m.bars) + m.castTicks > ticks) continue;
    const e = expectedDamage(b, t, m);
    if (e > best) best = e;
  }
  return best;
}

/** つよい: value per bar-time (see ai.dart `scoreMoveStrong`). */
export function scoreMoveStrong(b: Battle, side: number, slot: number): number {
  const s = b.spec;
  const me = b.fighters[side]!;
  const foe = b.fighters[1 - side]!;
  const m = me.moves[slot]!;
  const t = 1 - side;
  const cycle = barTicks(b, side);
  const wait = ticksToBars(b, side, m.bars);
  const time = m.bars * cycle + m.castTicks;
  const perTime = (v: number): number => {
    let x = tdiv(v * 36 * 100, time);
    if (wait > 0 && foeThreatWithin(b, side, wait + m.castTicks) >= me.hp) x = tdiv(x, 4);
    return x;
  };
  switch (kindOf(m)) {
    case 'physical':
    case 'special': {
      const e = expectedDamage(b, side, m, wait + m.castTicks);
      const hit = b.hitChance(side, t, m.accuracy);
      if (wait === 0) {
        const minHit = idiv(
          idiv(idiv(b.baseHitDamage(side, t, m) * s.varianceMinPct, 100) * (100 - foe.shieldPct), 100) * b.heatPct(),
          100,
        );
        if (hit >= 100 && minHit * m.hits >= foe.hp) return 2000000000 - m.castTicks * 1000 - m.bars;
        if (e >= foe.hp) return 1000000000 + hit * 1000 - m.castTicks * 10 - m.bars * 100;
      }
      const sec = pts(secondaryValue(m, me, foe), foe.maxHp);
      return perTime((e < foe.hp ? e : foe.hp) + sec);
    }
    case 'heal': {
      const steps = s.healDecaySteps;
      const decay = steps[me.healUses < steps.length ? me.healUses : steps.length - 1]!;
      const intl = b.eff(side, Stat.intl);
      const str = b.eff(side, Stat.str);
      const scale = 75 + idiv(50 * intl, intl + str);
      const heat = b.heatPct();
      const fade = heat >= 200 ? 0 : 200 - heat;
      const est = idiv(idiv(me.maxHp * m.healPct * scale * decay, 1000000) * fade, 100);
      const missing = me.maxHp - me.hp;
      const amt = est < missing ? est : missing;
      const hpPct = idiv(me.hp * 100, me.maxHp);
      const v = hpPct < 45 ? idiv(amt * 13, 10) : hpPct < 70 ? idiv(amt * 4, 10) : 0;
      return perTime(v);
    }
    case 'shield': {
      if (me.shieldPct > 0) return 0;
      const threat = foeThreatWithin(b, side, wait + m.durationTicks);
      const soon = foeThreatWithin(b, side, wait + 6);
      const v = idiv((soon > 0 ? threat : idiv(threat, 3)) * m.shieldPct, 100);
      return perTime(v);
    }
    case 'buff':
    case 'debuff': {
      const buff = kindOf(m) === 'buff';
      const target = buff ? me : foe;
      const active = buff ? target.stages[m.stat]! > 0 : target.stages[m.stat]! < 0;
      if (active || me.hp * 100 < me.maxHp * 35) return 0;
      const left = me.bars - m.bars < 0 ? 0 : me.bars - m.bars;
      const actions = 1 + left + idiv(m.durationTicks, cycle + 5);
      let best = 0;
      for (const x of me.moves) {
        if (!isDamage(x)) continue;
        const e = idiv(expectedDamage(b, side, x), x.bars);
        if (e > best) best = e;
      }
      const relevant =
        m.stat === Stat.str || m.stat === Stat.intl || m.stat === Stat.def || m.stat === Stat.res
          ? 22
          : m.stat === Stat.agi
            ? 18
            : m.stat === Stat.dex
              ? 8
              : 6;
      const acc = buff ? 100 : b.hitChance(side, 1 - side, m.accuracy);
      const v = idiv(best * relevant * m.stages * (actions - 1) * acc, 10000) - idiv(best, 4);
      return perTime(v < 0 ? 0 : v);
    }
    case 'status': {
      const has = statusOf(m) === 'poison' ? foe.poisonTicks > 0 : foe.paralyzeTicks > 0;
      if (has) return 0;
      const hit = b.hitChance(side, 1 - side, m.accuracy);
      const p = b.rel(m.chance, b.eff(side, Stat.luk), b.eff(1 - side, Stat.vit), s.statusLukSkewPct);
      const full =
        statusOf(m) === 'poison'
          ? idiv(foe.maxHp * s.poisonMillePerSecond, 1000) * idiv(s.poisonTicks, 10)
          : pts(PARALYZE_VALUE, foe.maxHp);
      const v = idiv(full * hit * (p > 100 ? 100 : p), 10000);
      return perTime(v);
    }
  }
}
