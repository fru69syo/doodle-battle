/**
 * 「おまかせ」 AI (timeout auto-pick, おまかせ toggle, CPU, server ghosts).
 * Bit-exact port of app/lib/domain/battle_v3/ai.dart.
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
import { idiv, Stat } from './spec';

export type AiTier = 'weak' | 'normal' | 'strong';
export const AI_TIERS: Readonly<Record<AiTier, { randomPct: number; thinkTicks: number; label: string }>> = {
  weak: { randomPct: 40, thinkTicks: 10, label: 'よわい' },
  normal: { randomPct: 10, thinkTicks: 10, label: 'ふつう' },
  strong: { randomPct: 0, thinkTicks: 4, label: 'つよい' },
};

const MIN_SCORE = -(2 ** 40);

/** Picks a usable slot for `side` (see ai.dart `chooseMove`). */
export function chooseMove(b: Battle, side: number, rng: Mulberry32, tier: AiTier = 'normal'): number {
  const f = b.fighters[side]!;
  const usable: number[] = [];
  for (let i = 0; i < f.moves.length; i++) if (f.usable(i)) usable.push(i);
  if (usable.length === 0) return 0;
  const roll = rng.nextInt(100);
  if (roll < AI_TIERS[tier].randomPct) return usable[rng.nextInt(usable.length)]!;
  let best = usable[0]!;
  let bestScore = MIN_SCORE;
  for (const i of usable) {
    const s = tier === 'strong' ? scoreMoveStrong(b, side, i) : scoreMove(b, side, f.moves[i]!);
    if (s > bestScore) {
      bestScore = s;
      best = i;
    }
  }
  return best;
}

const pts = (points: number, maxHp: number) => idiv(points * maxHp, 1000);

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

/** ふつう / よわい score (HP-equivalent). */
export function scoreMove(b: Battle, side: number, m: Move): number {
  const s = b.spec;
  const me = b.fighters[side]!;
  const foe = b.fighters[1 - side]!;
  const t = 1 - side;
  const costPenalty = pts(idiv(idiv(m.spCost * 5, 4) * 6, 10), foe.maxHp) + pts(m.castTicks, foe.maxHp);
  let score = 0;
  switch (kindOf(m)) {
    case 'physical':
    case 'special': {
      const per = b.baseHitDamage(side, t, m);
      let e = idiv(per * m.hits * m.accuracy * 95, 10000);
      e = idiv(e * (100 - foe.shieldPct), 100);
      if (e >= foe.hp) return 1000000000 - m.spCost * 1000 - m.castTicks;
      score = e + pts(secondaryValue(m, me, foe), foe.maxHp);
      break;
    }
    case 'heal': {
      const missing = me.maxHp - me.hp;
      const est = idiv(me.maxHp * m.healPct, 100);
      const amt = est < missing ? est : missing;
      const hpPct = idiv(me.hp * 100, me.maxHp);
      score = hpPct < 50 ? idiv(amt * 12, 10) : hpPct < 75 ? idiv(amt * 3, 10) : 0;
      break;
    }
    case 'buff':
      score = me.stages[m.stat]! > 0 || me.hp * 100 < me.maxHp * 40 ? 0 : idiv(pts(moveValue(m), foe.maxHp) * 8, 10);
      break;
    case 'debuff':
      score = foe.stages[m.stat]! < 0 ? 0 : idiv(pts(moveValue(m), foe.maxHp) * 8, 10);
      break;
    case 'status': {
      const has = statusOf(m) === 'poison' ? foe.poisonTicks > 0 : foe.paralyzeTicks > 0;
      score = has ? 0 : pts(moveValue(m), foe.maxHp);
      break;
    }
    case 'shield': {
      const threat = (foe.phase === 'casting' && foe.castLeft >= 2) || foe.gauge * 100 >= s.gaugeMax * 85;
      score = me.shieldPct > 0 ? 0 : idiv(pts(moveValue(m), foe.maxHp) * (threat ? 20 : 3), 10);
      break;
    }
  }
  return score - costPenalty;
}

/** Expected damage of one use of `m` by `side` now. */
export function expectedDamage(b: Battle, side: number, m: Move): number {
  const s = b.spec;
  const t = 1 - side;
  const foe = b.fighters[t]!;
  const per = b.baseHitDamage(side, t, m);
  const hit = b.hitChance(side, t, m.accuracy);
  const crit = b.critMille(side, t, m.critBonus);
  const meanVar = s.varianceMinPct + idiv(s.varianceSpan - 1, 2);
  let e = idiv(per * m.hits * hit * (1000 + idiv(crit * (s.critMultiplierPct - 100), 100)), 100000);
  e = idiv(e * meanVar, 100);
  e = idiv(e * (100 - foe.shieldPct), 100);
  return idiv(e * b.heatPct(), 100);
}

function cycleTicks(b: Battle, side: number): number {
  const r = b.fillRate(side);
  return r <= 0 ? b.spec.gaugeMax : idiv(b.spec.gaugeMax + r - 1, r);
}

function foeThreat(b: Battle, side: number): number {
  const t = 1 - side;
  const foe = b.fighters[t]!;
  if (foe.phase === 'casting') {
    const m = foe.moves[foe.castSlot]!;
    return isDamage(m) ? expectedDamage(b, t, m) : 0;
  }
  let best = 0;
  for (let i = 0; i < foe.moves.length; i++) {
    const m = foe.moves[i]!;
    if (!isDamage(m) || !foe.usable(i)) continue;
    const e = expectedDamage(b, t, m);
    if (e > best) best = e;
  }
  return best;
}

/** つよい score (see ai.dart `scoreMoveStrong`). */
export function scoreMoveStrong(b: Battle, side: number, slot: number): number {
  const s = b.spec;
  const me = b.fighters[side]!;
  const foe = b.fighters[1 - side]!;
  const m = me.moves[slot]!;
  const cycle = cycleTicks(b, side);
  const time = cycle + m.castTicks;
  const spPenalty = pts(idiv(idiv(m.spCost * 5, 4) * 6, 10), foe.maxHp);
  const perTime = (v: number) => idiv(v * 36, time);
  switch (kindOf(m)) {
    case 'physical':
    case 'special': {
      const e = expectedDamage(b, side, m);
      const t = 1 - side;
      const hit = b.hitChance(side, t, m.accuracy);
      const minHit = idiv(
        idiv(idiv(b.baseHitDamage(side, t, m) * s.varianceMinPct, 100) * (100 - foe.shieldPct), 100) * b.heatPct(),
        100,
      );
      if (hit >= 100 && minHit * m.hits >= foe.hp) return 2000000000 - m.castTicks * 1000 - m.spCost;
      if (e >= foe.hp) return 1000000000 + hit * 1000 - m.castTicks * 10 - m.spCost;
      const sec = pts(secondaryValue(m, me, foe), foe.maxHp);
      return perTime(e + sec) - spPenalty;
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
      return perTime(v) - spPenalty;
    }
    case 'shield': {
      if (me.shieldPct > 0) return -spPenalty;
      const threat = foeThreat(b, side);
      const charged =
        (foe.phase === 'casting' && foe.castLeft >= 2) || foe.phase === 'ready' || foe.gauge * 100 >= s.gaugeMax * 80;
      const foeCycle = cycleTicks(b, 1 - side);
      const blocks = charged ? 1 + idiv(m.durationTicks, foeCycle + 10) : 0;
      const v = idiv(threat * m.shieldPct, 100) * blocks;
      return perTime(v) - spPenalty;
    }
    case 'buff':
    case 'debuff': {
      const buff = kindOf(m) === 'buff';
      const target = buff ? me : foe;
      const active = buff ? target.stages[m.stat]! > 0 : target.stages[m.stat]! < 0;
      if (active || me.hp * 100 < me.maxHp * 35) return -spPenalty;
      const actions = 1 + idiv(m.durationTicks, cycle + 5);
      let best = 0;
      for (const x of me.moves) {
        if (!isDamage(x)) continue;
        const e = expectedDamage(b, side, x);
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
      return perTime(v < 0 ? 0 : v) - spPenalty;
    }
    case 'status': {
      const st = statusOf(m);
      const has = st === 'poison' ? foe.poisonTicks > 0 : foe.paralyzeTicks > 0;
      if (has) return -spPenalty;
      const hit = b.hitChance(side, 1 - side, m.accuracy);
      const p = b.rel(m.chance, b.eff(side, Stat.luk), b.eff(1 - side, Stat.vit), s.statusLukSkewPct);
      const full =
        st === 'poison'
          ? idiv(foe.maxHp * s.poisonMillePerSecond, 1000) * idiv(s.poisonTicks, 10)
          : pts(PARALYZE_VALUE, foe.maxHp);
      const v = idiv(full * hit * (p > 100 ? 100 : p), 10000);
      return perTime(v) - spPenalty;
    }
  }
}

/** Controller that thinks `thinkTicks` (default: the tier's) after ready. */
export function aiController(opts: { thinkTicks?: number; tier?: AiTier } = {}): Controller {
  const tier = opts.tier ?? 'normal';
  const think = opts.thinkTicks ?? AI_TIERS[tier].thinkTicks;
  return (b, side) => {
    const f = b.fighters[side]!;
    if (f.readyTicks < think) return null;
    return chooseMove(b, side, b.aiRng[side]!, tier);
  };
}

/** Timeout auto-pick: the ふつう AI. */
export function autoPickNormal(b: Battle, side: number, rng: Mulberry32): number {
  return chooseMove(b, side, rng);
}
