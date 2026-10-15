import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  AFFINITY_TABLE,
  AI_TIERS,
  ATK_FORMULAS,
  COLOURS,
  DEFAULT_SPEC as s,
  RAMP_TABLE,
  RIG_MAX_BYTES,
  RIG_MAX_LIMBS,
  SECONDARY_RANGES,
  STAGE_POWER_PCT,
  TEMPLATES,
  VFX,
  WORLD_NAMES,
  WORLD_ROSTERS,
} from '../src';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const j = JSON.parse(readFileSync(join(__dirname, '..', '..', 'battle_spec_v3', 'battle_spec_v3.json'), 'utf8')) as any;

describe('constants match shared/battle_spec_v3/battle_spec_v3.json', () => {
  it('character', () => {
    const c = j.character;
    expect([c.kid.energyWeight, c.kid.skillWeight]).toEqual([s.kidEnergyWeight, s.kidSkillWeight]);
    expect(c.budget).toMatchObject({
      base: s.budgetBase,
      perKid: s.budgetPerKid,
      div: s.budgetDiv,
      jitterMinPct: s.budgetJitterMinPct,
      jitterSpan: s.budgetJitterSpan,
    });
    expect(c.bloomer).toMatchObject({
      skillAbove10: s.bloomerSkillAbove10,
      preBudgetPct: s.bloomerPreBudgetPct,
      preGrowthPct: s.bloomerPreGrowthPct,
      rebirthLevel: s.rebirthLevel,
      rebirthKid: s.rebirthKid,
      rebirthBudgetPct: s.rebirthBudgetPct,
      postGrowthBoostPct: s.bloomerPostGrowthBoostPct,
    });
    expect(c.distribution).toMatchObject({
      minShareMille: s.minShareMille,
      affinityJitterMinPct: s.affinityJitterMinPct,
      affinityJitterSpan: s.affinityJitterSpan,
      affinityFloor: s.affinityFloor,
    });
    for (const [k, v] of Object.entries(RAMP_TABLE)) expect(c.distribution.ramps[k]).toEqual([...v]);
    for (const [k, v] of Object.entries(AFFINITY_TABLE)) expect(Object.entries(c.distribution.affinities[k])).toEqual(v.map((x) => [...x]));
    expect(c.growth).toEqual({
      totalMillePerLevel: s.growthTotalMillePerLevel,
      rawBase: s.growthRawBase,
      rawAffinityDiv: s.growthRawAffinityDiv,
      rawJitterSpan: s.growthRawJitterSpan,
    });
    expect(c.maxHp).toMatchObject({ perHp: s.hpPerHp, perVit: s.hpPerVit, perAvg: s.hpPerAvg });
  });

  it('levels, moves, atb, damage, status, termination', () => {
    expect(j.levels).toEqual({
      max: s.maxLevel,
      xpToNext: { base: s.xpBase, perLevel: s.xpPerLevel, quadNum: s.xpQuadNum, quadDen: s.xpQuadDen },
    });
    expect(j.moves).toEqual({
      barBudgets: s.barBudgets,
      slotMaxBars: s.slotMaxBars,
      slotUnlockLevels: s.slotUnlockLevels,
      moveFactorBasePct: s.moveFactorBasePct,
      moveFactorKidDiv: s.moveFactorKidDiv,
      bloomerPreMoveFactorPct: s.bloomerPreMoveFactorPct,
      legendMoveBonusPct: s.legendMoveBonusPct,
      bloomerRebirthMoveBonusPct: s.bloomerRebirthMoveBonusPct,
      castDiscountPerTick: s.castDiscountPerTick,
      cooldownDiscountDiv: s.cooldownDiscountDiv,
      maxDiscountPct: s.maxDiscountPct,
    });
    expect(j.atb).toMatchObject({
      tickHz: s.tickHz,
      gaugeMax: s.gaugeMax,
      gaugeFillPerTick: s.gaugeFillPerTick,
      agiWeightPct: s.agiWeightPct,
      gaugePerBar: s.gaugeMax,
      spPerBar: s.spPerBar,
      minBars: s.minBars,
      maxBars: s.maxBars,
    });
    expect(j.atb.decisionTicks).toBeUndefined();
    expect(j.character.minLv1Sp.value).toBe(s.minLv1Sp);
    expect(j.damage).toMatchObject({
      scalePct: s.damageScalePct,
      typeAdvantagePct: s.typeAdvantagePct,
      typeDisadvantagePct: s.typeDisadvantagePct,
      typeStrengthPct: s.typeStrengthPct,
      varianceMinPct: s.varianceMinPct,
      varianceSpan: s.varianceSpan,
      critBaseMille: s.critBaseMille,
      critLukMille: s.critLukMille,
      critMultiplierPct: s.critMultiplierPct,
      hitSkewPct: s.hitSkewPct,
      hitMinPct: s.hitMinPct,
      stageDen: s.stageDen,
      maxStage: s.maxStage,
    });
    expect(j.status).toEqual({
      poisonMillePerSecond: s.poisonMillePerSecond,
      poisonTicks: s.poisonTicks,
      paralyzeFillPct: s.paralyzeFillPct,
      paralyzeTicks: s.paralyzeTicks,
      lukSkewPct: s.statusLukSkewPct,
      healDecaySteps: s.healDecaySteps,
    });
    expect(j.termination).toEqual({
      heatUpStartTick: s.heatUpStartTick,
      heatUpPctPerSecond: s.heatUpPctPerSecond,
      hardCapTick: s.hardCapTick,
    });
  });

  it('templates, rules, AI, stages, rig', () => {
    for (const [id, t] of Object.entries(TEMPLATES)) {
      expect(j.moveTemplates[id].kind).toBe(t.kind);
      for (const [k, r] of Object.entries(t.ranges)) expect(j.moveTemplates[id].ranges[k]).toEqual([...r]);
      expect(Object.keys(j.moveTemplates[id].ranges).sort()).toEqual(Object.keys(t.ranges).sort());
    }
    expect(Object.keys(j.moveTemplates).sort()).toEqual(Object.keys(TEMPLATES).sort());
    expect(j.moveRules.vfx).toEqual([...VFX]);
    expect(j.moveRules.colours).toEqual([...COLOURS]);
    expect(Object.keys(j.moveRules.atkFormulas)).toEqual(ATK_FORMULAS.map((f) => f.code));
    expect(j.moveRules.secondaryRanges).toEqual({ chance: [...SECONDARY_RANGES.chance], drainPct: [...SECONDARY_RANGES.drainPct] });
    for (const [t, v] of Object.entries(AI_TIERS)) {
      expect(j.ai.randomPct[t]).toBe(v.randomPct);
      expect(j.ai.thinkTicks[t]).toBe(v.thinkTicks);
      expect(j.ai.saveBars[t]).toBe(v.saveBars);
    }
    expect(j.progression.stages.worlds).toEqual([...WORLD_NAMES]);
    expect(j.progression.stages.powerPctByPosition).toEqual([...STAGE_POWER_PCT]);
    expect(j.progression.stages.worldRosters).toEqual(WORLD_ROSTERS.map((r) => [...r]));
    expect([j.rig.maxBytes, j.rig.maxLimbs]).toEqual([RIG_MAX_BYTES, RIG_MAX_LIMBS]);
  });
});
