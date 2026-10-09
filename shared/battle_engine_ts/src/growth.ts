/** Levelling, XP, パワーのたね and evolution; port of growth.dart. */
import { idiv } from './engine';
import type { BattleSpec } from './spec';
import type { EvolutionStage, StatKind, Stats } from './types';

export type SeedAllocations = Partial<Record<StatKind, number>>;
const STAT_KINDS: readonly StatKind[] = ['hp', 'atk', 'def', 'spd'];

/** しょぼキャラ: skill > growth.shoboSkillAbove (75). */
export function isShoboSkill(spec: BattleSpec, skill: number): boolean {
  return skill > spec.growth.shoboSkillAbove;
}

/** Growth per level in percent of Lv1 stats (higher for しょぼキャラ). */
export function levelUpPct(spec: BattleSpec, isShobo: boolean): number {
  return isShobo ? spec.growth.shoboLevelUpStatPct : spec.growth.levelUpStatPct;
}

/**
 * floor(base * (100 + g*(level-1) + seedStatPct*seeds) / 100), min 1,
 * g = levelUpPct(spec, isShobo).
 */
export function statsAtLevel(spec: BattleSpec, base: Stats, level: number, seeds: SeedAllocations, isShobo: boolean): Stats {
  const g = levelUpPct(spec, isShobo);
  const one = (k: StatKind): number => {
    const pct = 100 + g * (level - 1) + spec.growth.seedStatPct * (seeds[k] ?? 0);
    const v = idiv(base[k] * pct, 100);
    return v < 1 ? 1 : v;
  };
  return { hp: one('hp'), atk: one('atk'), def: one('def'), spd: one('spd') };
}

/** Upper bound of each stat at `level` (every seed in that stat): anti-tamper check. */
export function maxStatsAtLevel(spec: BattleSpec, base: Stats, level: number, isShobo: boolean): Stats {
  const n = (level - 1) * spec.growth.seedsPerLevel;
  return statsAtLevel(spec, base, level, { hp: n, atk: n, def: n, spd: n }, isShobo);
}

/** XP from `level` to level+1: 50 + 25 * level. */
export function xpToNext(spec: BattleSpec, level: number): number {
  return spec.growth.xpToNextBase + spec.growth.xpToNextPerLevel * level;
}

export function stageAtLevel(spec: BattleSpec, level: number): EvolutionStage {
  let stage: EvolutionStage = 'normal';
  for (const e of spec.growth.evolutions) if (level >= e.level) stage = e.stage;
  return stage;
}

export interface XpOptions {
  won: boolean;
  isShobo: boolean;
  stageXpMultiplierPct?: number;
  adBoost?: boolean;
}

/** floor(base * stagePct * (100 + shoboBonusPct if shobo) * (adBoost ? m : 1) / 10000). */
export function xpForBattle(spec: BattleSpec, o: XpOptions): number {
  const base = o.won ? spec.xp.win : spec.xp.lose;
  const shoboPct = 100 + (o.isShobo ? spec.xp.shoboBonusPct : 0);
  const ad = o.adBoost ? spec.xp.adBoostMultiplier : 1;
  return idiv(base * (o.stageXpMultiplierPct ?? 100) * shoboPct * ad, 10000);
}

export interface XpProgress {
  level: number;
  /** XP towards the next level (0 at max level). */
  xp: number;
  levelsGained: number;
  seedsGained: number;
  evolutions: EvolutionStage[];
}

/** Adds `gained` XP; applies multiple level-ups; discards leftovers at max level. */
export function addXp(spec: BattleSpec, level: number, xp: number, gained: number): XpProgress {
  const max = spec.growth.maxLevel;
  let lv = level;
  let cur = lv >= max ? 0 : xp + gained;
  const evolutions: EvolutionStage[] = [];
  while (lv < max && cur >= xpToNext(spec, lv)) {
    cur -= xpToNext(spec, lv);
    lv++;
    for (const e of spec.growth.evolutions) if (e.level === lv) evolutions.push(e.stage);
  }
  if (lv >= max) cur = 0;
  return {
    level: lv,
    xp: cur,
    levelsGained: lv - level,
    seedsGained: (lv - level) * spec.growth.seedsPerLevel,
    evolutions,
  };
}

/** Unspent パワーのたね: (level - 1) * seedsPerLevel - allocated. */
export function seedsAvailable(spec: BattleSpec, level: number, seeds: SeedAllocations): number {
  let allocated = 0;
  for (const k of STAT_KINDS) allocated += seeds[k] ?? 0;
  return (level - 1) * spec.growth.seedsPerLevel - allocated;
}

/** Spends one seed on `stat`; throws if none is available. */
export function allocateSeed(spec: BattleSpec, level: number, seeds: SeedAllocations, stat: StatKind): SeedAllocations {
  if (seedsAvailable(spec, level, seeds) <= 0) throw new Error('no パワーのたね available');
  return { ...seeds, [stat]: (seeds[stat] ?? 0) + 1 };
}
