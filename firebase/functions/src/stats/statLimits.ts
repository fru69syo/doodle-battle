import { LIMITS } from "../config";
import {
  defaultSpec as SPEC,
  isShoboSkill,
  maxStatsAtLevel,
  stageAtLevel,
  statsAtLevel,
  xpToNext as sharedXpToNext,
} from "../vendor/battle_engine";

export const ELEMENTS = ["fire", "water", "leaf", "thunder", "shadow", "rainbow"] as const;
export type Element = (typeof ELEMENTS)[number];

export const STAT_KEYS = ["hp", "atk", "def", "spd"] as const;
export type StatKey = (typeof STAT_KEYS)[number];
export type Stats = Record<StatKey, number>;

/** SPEC §3.2 skill multiplier. */
export function skillMultiplier(skill: number): number {
  if (skill <= 30) return 1.0;
  if (skill <= 60) return 1.0 - (0.1 * (skill - 30)) / 30;
  if (skill <= 75) return 0.9 - (0.2 * (skill - 60)) / 15;
  return 0.35;
}

/** SPEC §3.2 level-1 stat budget. */
export function statBudget(energy: number, skill: number): number {
  return (200 + 2 * energy) * skillMultiplier(skill);
}

/** しょぼキャラ (SPEC §1): skill above the shared spec's threshold (75). */
export function isShobo(skill: number): boolean {
  return isShoboSkill(SPEC, skill);
}

/** SPEC §4.2: XP needed to go from level L to L+1 (shared battle spec). */
export function xpToNext(level: number): number {
  return sharedXpToNext(SPEC, level);
}

/**
 * Upper bound on a single stat's share of the budget. SPEC §3.2 says each
 * weight is at least 0.15; if weights are normalised after clamping, one stat
 * can take at most 1 / (1 + 3 * 0.15) ≈ 0.69 of the budget. Assumption to be
 * confirmed with the Vision team (docs/BACKEND.md).
 */
export const MAX_STAT_SHARE = 0.7;
/** Rounding slack for four integer stats. */
const ROUNDING_SLACK = 4;

/**
 * Effective stats at `level` (SPEC §4.2), computed by the shared battle engine
 * exactly as the app does: +4%/level of the Lv1 value (+12%/level for
 * しょぼキャラ), +3% per パワーのたね, floored.
 */
export function effectiveStats(base: Stats, level: number, seeds: Partial<Stats>, shobo: boolean): Stats {
  return statsAtLevel(SPEC, base, level, seeds, shobo);
}

/**
 * Highest value each stat can legally reach at `level` for this energy/skill:
 * the per-stat Lv1 share cap grown with every seed in that stat
 * (shared `maxStatsAtLevel`, including the しょぼ growth rate).
 */
export function statCapsAtLevel(energy: number, skill: number, level: number): Stats {
  const cap = Math.ceil(statBudget(energy, skill) * MAX_STAT_SHARE) + 1;
  return maxStatsAtLevel(SPEC, { hp: cap, atk: cap, def: cap, spd: cap }, level, isShobo(skill));
}

export function evolutionStage(level: number): "normal" | "kagayaki" | "densetsu" {
  return stageAtLevel(SPEC, level);
}

export interface StatClaim {
  energy: number;
  skill: number;
  level: number;
  xp: number;
  baseStats: Stats;
  seedAllocations: Partial<Stats>;
}

/** Returns a list of problems (empty when the claim is plausible). */
export function validateStatClaim(c: StatClaim): string[] {
  const problems: string[] = [];
  if (!(c.energy >= 0 && c.energy <= 100)) problems.push("energy out of range");
  if (!(c.skill >= 0 && c.skill <= 100)) problems.push("skill out of range");
  if (!Number.isInteger(c.level) || c.level < 1 || c.level > LIMITS.maxLevel) problems.push("level out of range");
  if (!Number.isInteger(c.xp) || c.xp < 0 || (c.level < LIMITS.maxLevel && c.xp >= xpToNext(c.level))) {
    problems.push("xp out of range");
  }
  if (problems.length > 0) return problems;

  const budget = statBudget(c.energy, c.skill);
  let total = 0;
  for (const k of STAT_KEYS) {
    const v = c.baseStats[k];
    if (!Number.isInteger(v) || v < 0) {
      problems.push(`${k} not a non-negative integer`);
      continue;
    }
    total += v;
    if (v > Math.ceil(budget * MAX_STAT_SHARE) + 1) problems.push(`${k} exceeds share cap`);
  }
  if (total > Math.ceil(budget) + ROUNDING_SLACK) problems.push("total exceeds budget");

  let seeds = 0;
  for (const [k, n] of Object.entries(c.seedAllocations) as [string, unknown][]) {
    if (!(STAT_KEYS as readonly string[]).includes(k) || typeof n !== "number" || !Number.isInteger(n) || n < 0) {
      problems.push(`bad seed allocation ${k}`);
    } else {
      seeds += n;
    }
  }
  if (seeds > (c.level - 1) * SPEC.growth.seedsPerLevel) problems.push("more seeds than level-ups");
  if (problems.length > 0) return problems;

  // Effective stats (what the battle uses) must stay within the level caps.
  const shobo = isShobo(c.skill);
  const eff = effectiveStats(c.baseStats, c.level, c.seedAllocations, shobo);
  const caps = statCapsAtLevel(c.energy, c.skill, c.level);
  const own = maxStatsAtLevel(SPEC, c.baseStats, c.level, shobo);
  for (const k of STAT_KEYS) {
    if (eff[k] > caps[k] || eff[k] > own[k]) problems.push(`${k} exceeds level cap`);
  }
  return problems;
}
