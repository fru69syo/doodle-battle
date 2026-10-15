/**
 * Battle spec v3 constants (docs/GAME_DESIGN_V2.md, docs/BATTLE_V3.md).
 * Mirrors `V3Spec` in app/lib/domain/battle_v3/spec.dart; test/spec.test.ts
 * checks every value against shared/battle_spec_v3/battle_spec_v3.json.
 * All maths is integer maths: `idiv` = floor division of non-negative ints.
 */

export const STATS = ['HP', 'SP', 'STR', 'VIT', 'DEF', 'INT', 'RES', 'DEX', 'AGI', 'LUK'] as const;
export type StatCode = (typeof STATS)[number];

/** Stat indices (canonical order). */
export const Stat = {
  hp: 0,
  sp: 1,
  str: 2,
  vit: 3,
  def: 4,
  intl: 5,
  res: 6,
  dex: 7,
  agi: 8,
  luk: 9,
} as const;
export type StatIndex = (typeof Stat)[keyof typeof Stat];

export function statIndex(code: string): StatIndex | undefined {
  const i = (STATS as readonly string[]).indexOf(code);
  return i < 0 ? undefined : (i as StatIndex);
}

/** グー / チョキ / パー (+ むぞくせい). */
export type Attr = 'gu' | 'choki' | 'pa' | 'none';
export const ATTRS: readonly Attr[] = ['gu', 'choki', 'pa', 'none'];

/** The attribute `a` beats (gu > choki > pa > gu). */
export function beats(a: Attr): Attr | null {
  return a === 'gu' ? 'choki' : a === 'choki' ? 'pa' : a === 'pa' ? 'gu' : null;
}

/** The attribute that beats `a`. */
export function beatenBy(a: Attr): Attr | null {
  return a === 'gu' ? 'pa' : a === 'choki' ? 'gu' : a === 'pa' ? 'choki' : null;
}

export function isAttr(x: unknown): x is Attr {
  return x === 'gu' || x === 'choki' || x === 'pa' || x === 'none';
}

export interface V3Spec {
  specVersion: number;
  kidEnergyWeight: number;
  kidSkillWeight: number;
  budgetBase: number;
  budgetPerKid: number;
  budgetDiv: number;
  budgetJitterMinPct: number;
  budgetJitterSpan: number;
  bloomerSkillAbove10: number;
  bloomerPreBudgetPct: number;
  bloomerPreGrowthPct: number;
  rebirthLevel: number;
  rebirthKid: number;
  rebirthBudgetPct: number;
  bloomerPostGrowthBoostPct: number;
  minShareMille: number;
  affinityJitterMinPct: number;
  affinityJitterSpan: number;
  affinityFloor: number;
  growthTotalMillePerLevel: number;
  growthRawBase: number;
  growthRawAffinityDiv: number;
  growthRawJitterSpan: number;
  hpPerHp: number;
  hpPerVit: number;
  hpPerAvg: number;
  minLv1Sp: number;
  maxLevel: number;
  xpBase: number;
  xpPerLevel: number;
  xpQuadNum: number;
  xpQuadDen: number;
  barBudgets: readonly number[];
  slotMaxBars: readonly number[];
  slotUnlockLevels: readonly number[];
  moveFactorBasePct: number;
  moveFactorKidDiv: number;
  bloomerPreMoveFactorPct: number;
  legendMoveBonusPct: number;
  bloomerRebirthMoveBonusPct: number;
  castDiscountPerTick: number;
  cooldownDiscountDiv: number;
  maxDiscountPct: number;
  tickHz: number;
  gaugeMax: number;
  gaugeFillPerTick: number;
  agiWeightPct: number;
  spPerBar: number;
  minBars: number;
  maxBars: number;
  damageScalePct: number;
  typeAdvantagePct: number;
  typeDisadvantagePct: number;
  typeStrengthPct: number;
  varianceMinPct: number;
  varianceSpan: number;
  critBaseMille: number;
  critLukMille: number;
  critMultiplierPct: number;
  hitSkewPct: number;
  hitMinPct: number;
  stageDen: number;
  maxStage: number;
  poisonMillePerSecond: number;
  poisonTicks: number;
  paralyzeFillPct: number;
  paralyzeTicks: number;
  statusLukSkewPct: number;
  healDecaySteps: readonly number[];
  heatUpStartTick: number;
  heatUpPctPerSecond: number;
  hardCapTick: number;
}

export const DEFAULT_SPEC: Readonly<V3Spec> = Object.freeze({
  specVersion: 4,
  kidEnergyWeight: 6,
  kidSkillWeight: 4,
  budgetBase: 1400,
  budgetPerKid: 3,
  budgetDiv: 400,
  budgetJitterMinPct: 97,
  budgetJitterSpan: 7,
  bloomerSkillAbove10: 750,
  bloomerPreBudgetPct: 50,
  bloomerPreGrowthPct: 100,
  rebirthLevel: 50,
  rebirthKid: 75,
  rebirthBudgetPct: 100,
  bloomerPostGrowthBoostPct: 12,
  minShareMille: 50,
  affinityJitterMinPct: 85,
  affinityJitterSpan: 31,
  affinityFloor: 50,
  growthTotalMillePerLevel: 400,
  growthRawBase: 700,
  growthRawAffinityDiv: 3,
  growthRawJitterSpan: 301,
  hpPerHp: 3,
  hpPerVit: 2,
  hpPerAvg: 5,
  minLv1Sp: 20,
  maxLevel: 100,
  xpBase: 60,
  xpPerLevel: 20,
  xpQuadNum: 3,
  xpQuadDen: 4,
  barBudgets: [100, 230, 390, 580, 800],
  slotMaxBars: [1, 5, 5, 5],
  slotUnlockLevels: [1, 1, 10, 50],
  moveFactorBasePct: 95,
  moveFactorKidDiv: 10,
  bloomerPreMoveFactorPct: 70,
  legendMoveBonusPct: 5,
  bloomerRebirthMoveBonusPct: 0,
  castDiscountPerTick: 2,
  cooldownDiscountDiv: 4,
  maxDiscountPct: 25,
  tickHz: 10,
  gaugeMax: 10000,
  gaugeFillPerTick: 280,
  agiWeightPct: 30,
  spPerBar: 10,
  minBars: 2,
  maxBars: 5,
  damageScalePct: 57,
  typeAdvantagePct: 150,
  typeDisadvantagePct: 75,
  typeStrengthPct: 100,
  varianceMinPct: 90,
  varianceSpan: 11,
  critBaseMille: 50,
  critLukMille: 60,
  critMultiplierPct: 150,
  hitSkewPct: 15,
  hitMinPct: 30,
  stageDen: 4,
  maxStage: 2,
  poisonMillePerSecond: 15,
  poisonTicks: 80,
  paralyzeFillPct: 60,
  paralyzeTicks: 60,
  statusLukSkewPct: 50,
  healDecaySteps: [100, 75, 50, 25],
  heatUpStartTick: 600,
  heatUpPctPerSecond: 3,
  hardCapTick: 1800,
});

/** Floor division of non-negative integers (every engine division). */
export function idiv(a: number, b: number): number {
  return Math.floor(a / b);
}

/** Dart `~/` (truncation toward zero), for the few signed divisions. */
export function tdiv(a: number, b: number): number {
  return Math.trunc(a / b);
}

/** Max bars of a character whose Lv1 base SP is `lv1Sp` (SP / spPerBar, clamped). */
export function maxBarsFor(s: V3Spec, lv1Sp: number): number {
  const n = idiv(lv1Sp, s.spPerBar);
  return n < s.minBars ? s.minBars : n > s.maxBars ? s.maxBars : n;
}

/** Effective type multiplier (%) after `typeStrengthPct`. */
export function typePct(s: V3Spec, rawPct: number): number {
  return 100 + tdiv((rawPct - 100) * s.typeStrengthPct, 100);
}

/** Feature ramps: `[featureKey, lo, hi]`. */
export const RAMP_TABLE: Readonly<Record<string, readonly [string, number, number]>> = {
  round: ['roundness', 200, 800],
  size: ['silhouetteCoverage', 30, 350],
  ink: ['inkCoverage', 0, 300],
  solid: ['solidity', 500, 950],
  spiky: ['spikiness', 0, 300],
  red: ['redShare', 0, 1000],
  thick: ['lineThickness', 10, 120],
  dark: ['darkness', 200, 800],
  colour: ['colorUnits', 1, 10],
  hues: ['balancedHueCount', 1, 4],
  detail: ['detailDensity', 0, 600],
  parts: ['convexityDefects', 0, 8],
  elong: ['elongation', 100, 300],
  sym: ['symmetry', 400, 900],
};

/** Affinity weights per stat (weights sum to 100). Order matters (Dart map order). */
export const AFFINITY_TABLE: Readonly<Record<StatCode, readonly (readonly [string, number])[]>> = {
  HP: [['round', 40], ['size', 35], ['ink', 25]],
  SP: [['hues', 40], ['ink', 30], ['parts', 30]],
  STR: [['spiky', 40], ['red', 30], ['thick', 30]],
  VIT: [['dark', 40], ['solid', 30], ['size', 30]],
  DEF: [['thick', 45], ['solid', 35], ['inv:elong', 20]],
  INT: [['colour', 50], ['detail', 30], ['inv:sym', 20]],
  RES: [['dark', 40], ['thick', 35], ['colour', 25]],
  DEX: [['inv:thick', 40], ['parts', 30], ['detail', 30]],
  AGI: [['elong', 45], ['inv:thick', 35], ['inv:size', 20]],
  LUK: [['luck', 50], ['hues', 25], ['inv:sym', 25]],
};

/** Shape → attribute scores. */
export const ATTRIBUTE_RULE = {
  gu: ['solid', 'round', 'thick'],
  choki: ['spiky', 'elong', 'inv:thick'],
  pa: ['colour', 'hues', 'size'],
} as const;
