import { describe, expect, it } from "vitest";
import { LIMITS } from "../../src/config";
import { defaultSpec, maxStatsAtLevel, statsAtLevel } from "../../src/vendor/battle_engine";
import {
  effectiveStats,
  MAX_STAT_SHARE,
  statCapsAtLevel,
  evolutionStage,
  isShobo,
  skillMultiplier,
  statBudget,
  validateStatClaim,
  xpToNext,
  type StatClaim,
} from "../../src/stats/statLimits";

describe("SPEC §3.2 budget", () => {
  it("skill multiplier is piecewise linear", () => {
    expect(skillMultiplier(0)).toBe(1);
    expect(skillMultiplier(30)).toBe(1);
    expect(skillMultiplier(45)).toBeCloseTo(0.95);
    expect(skillMultiplier(60)).toBeCloseTo(0.9);
    expect(skillMultiplier(67.5)).toBeCloseTo(0.8);
    expect(skillMultiplier(75)).toBeCloseTo(0.7);
    expect(skillMultiplier(75.1)).toBe(0.35);
    expect(skillMultiplier(100)).toBe(0.35);
  });
  it("budget", () => {
    expect(statBudget(100, 0)).toBe(400);
    expect(statBudget(0, 0)).toBe(200);
    expect(statBudget(100, 90)).toBeCloseTo(140);
    expect(isShobo(75)).toBe(false);
    expect(isShobo(76)).toBe(true);
  });
});

describe("SPEC §4.2 growth", () => {
  it("xp to next level", () => {
    expect(xpToNext(1)).toBe(75);
    expect(xpToNext(5)).toBe(175);
  });
  it("effective stats grow 4%/level and 3%/seed", () => {
    expect(effectiveStats({ hp: 100, atk: 100, def: 100, spd: 100 }, 11, { atk: 2 }, false)).toEqual({
      hp: 140,
      atk: 146,
      def: 140,
      spd: 140,
    });
  });
  it("しょぼキャラ grow 12%/level (shared spec) and match the shared engine", () => {
    expect(effectiveStats({ hp: 30, atk: 30, def: 30, spd: 30 }, 11, {}, true)).toEqual({
      hp: 66,
      atk: 66,
      def: 66,
      spd: 66,
    });
    const base = { hp: 31, atk: 33, def: 30, spd: 32 };
    expect(effectiveStats(base, 30, { hp: 29 }, true)).toEqual(statsAtLevel(defaultSpec, base, 30, { hp: 29 }, true));
  });
  it("level caps use the shared maxStatsAtLevel", () => {
    const caps = statCapsAtLevel(80, 15, 10);
    const cap1 = Math.ceil(statBudget(80, 15) * MAX_STAT_SHARE) + 1;
    expect(caps).toEqual(maxStatsAtLevel(defaultSpec, { hp: cap1, atk: cap1, def: cap1, spd: cap1 }, 10, false));
    expect(statCapsAtLevel(80, 90, 30).hp).toBeGreaterThan(statCapsAtLevel(80, 90, 1).hp * 4);
  });
  it("evolution stages", () => {
    expect(evolutionStage(9)).toBe("normal");
    expect(evolutionStage(10)).toBe("kagayaki");
    expect(evolutionStage(20)).toBe("densetsu");
  });
});

describe("validateStatClaim", () => {
  const ok: StatClaim = {
    energy: 50,
    skill: 20,
    level: 6,
    xp: 10,
    baseStats: { hp: 90, atk: 80, def: 65, spd: 65 }, // total 300 = budget
    seedAllocations: { atk: 3, hp: 2 },
  };
  it("accepts a plausible claim", () => {
    expect(validateStatClaim(ok)).toEqual([]);
  });
  it("rejects totals above budget", () => {
    expect(validateStatClaim({ ...ok, baseStats: { hp: 100, atk: 100, def: 60, spd: 60 } })).toContain(
      "total exceeds budget",
    );
  });
  it("skill above 75 shrinks the budget (しょぼキャラ)", () => {
    expect(validateStatClaim({ ...ok, skill: 80 })).toContain("total exceeds budget");
  });
  it("rejects one stat hogging the budget", () => {
    expect(validateStatClaim({ ...ok, baseStats: { hp: 10, atk: 280, def: 5, spd: 5 } })).toContain(
      "atk exceeds share cap",
    );
  });
  it("rejects more seeds than level-ups and bad keys", () => {
    expect(validateStatClaim({ ...ok, seedAllocations: { atk: 6 } })).toContain("more seeds than level-ups");
    expect(validateStatClaim({ ...ok, seedAllocations: { luck: 1 } as never })).toContain("bad seed allocation luck");
  });
  it("rejects xp beyond the level threshold and out-of-range inputs", () => {
    expect(validateStatClaim({ ...ok, xp: 200 })).toContain("xp out of range");
    expect(validateStatClaim({ ...ok, level: 31 })).toContain("level out of range");
    expect(validateStatClaim({ ...ok, energy: 101 })).toContain("energy out of range");
    expect(validateStatClaim({ ...ok, baseStats: { ...ok.baseStats, hp: 1.5 } })).toContain(
      "hp not a non-negative integer",
    );
  });
  it("accepts a grown しょぼキャラ (budget 0.35x, 12%/level growth)", () => {
    const shobo: StatClaim = {
      energy: 80,
      skill: 90,
      level: 30,
      xp: 0,
      baseStats: { hp: 32, atk: 32, def: 31, spd: 31 }, // 126 = 360 * 0.35
      seedAllocations: { atk: 29 },
    };
    expect(validateStatClaim(shobo)).toEqual([]);
    expect(validateStatClaim({ ...shobo, seedAllocations: { atk: 30 } })).toContain("more seeds than level-ups");
  });
  it("server limits match the shared battle spec", () => {
    expect(LIMITS.maxLevel).toBe(defaultSpec.growth.maxLevel);
    expect(LIMITS.maxTurns).toBe(defaultSpec.turnCap);
  });
  it("allows any xp at max level", () => {
    expect(validateStatClaim({ ...ok, level: 30, xp: 99999 })).toEqual([]);
  });
});
