/**
 * Quantised features and character generation (kid-likeness, hidden late
 * bloomer, ten stats, growth, attribute). Bit-exact port of
 * app/lib/domain/battle_v3/features.dart + genome.dart.
 *
 * INTERNAL: `isBloomer` / `rebornAt` are the hidden late-bloomer mechanic;
 * never put them in an API response (docs/GAME_DESIGN_V2.md §4.4).
 */
import { deriveSeed, fnv1a32, Mulberry32 } from './rng';
import {
  AFFINITY_TABLE,
  ATTRIBUTE_RULE,
  type Attr,
  idiv,
  maxBarsFor,
  RAMP_TABLE,
  Stat,
  STATS,
  type V3Spec,
} from './spec';

export const FEATURE_KEYS = [
  'roundness',
  'silhouetteCoverage',
  'inkCoverage',
  'solidity',
  'spikiness',
  'redShare',
  'lineThickness',
  'darkness',
  'colorUnits',
  'balancedHueCount',
  'detailDensity',
  'convexityDefects',
  'elongation',
  'symmetry',
] as const;
export type FeatureKey = (typeof FEATURE_KEYS)[number];

export const FEATURE_RANGES: Readonly<Record<FeatureKey, readonly [number, number]>> = {
  roundness: [0, 1000],
  silhouetteCoverage: [0, 1000],
  inkCoverage: [0, 1000],
  solidity: [0, 1000],
  spikiness: [0, 1000],
  redShare: [0, 1000],
  lineThickness: [0, 600],
  darkness: [0, 1000],
  colorUnits: [0, 30],
  balancedHueCount: [0, 12],
  detailDensity: [0, 1000],
  convexityDefects: [0, 50],
  elongation: [100, 1000],
  symmetry: [0, 1000],
};

export const FEATURE_DEFAULTS: Readonly<Record<FeatureKey, number>> = {
  roundness: 500,
  silhouetteCoverage: 150,
  inkCoverage: 120,
  solidity: 750,
  spikiness: 100,
  redShare: 200,
  lineThickness: 50,
  darkness: 500,
  colorUnits: 5,
  balancedHueCount: 2,
  detailDensity: 150,
  convexityDefects: 3,
  elongation: 160,
  symmetry: 600,
};

export type FeatureVector = Partial<Record<FeatureKey, number>>;

export function feature(f: FeatureVector, k: string): number {
  const v = (f as Record<string, number | undefined>)[k];
  return v ?? (FEATURE_DEFAULTS as Record<string, number>)[k] ?? 0;
}

/**
 * Parses a transmitted vector: unknown keys ignored, non-integers rejected
 * (null), values clamped to range (same as `FeatureVector.tryParse`).
 */
export function parseFeatures(json: unknown): FeatureVector | null {
  if (typeof json !== 'object' || json === null || Array.isArray(json)) return null;
  const out: FeatureVector = {};
  for (const k of FEATURE_KEYS) {
    const v = (json as Record<string, unknown>)[k];
    if (v === undefined || v === null) continue;
    if (typeof v !== 'number' || !Number.isInteger(v)) return null;
    const [lo, hi] = FEATURE_RANGES[k];
    out[k] = v < lo ? lo : v > hi ? hi : v;
  }
  return out;
}

/** Ramp term by name (`round`, `inv:thick`, …) → 0..1000. */
export function term(f: FeatureVector, name: string): number {
  if (name.startsWith('inv:')) return 1000 - term(f, name.substring(4));
  const r = RAMP_TABLE[name];
  if (!r) throw new Error(`unknown ramp ${name}`);
  const v = feature(f, r[0]);
  const [, lo, hi] = r;
  if (v <= lo) return 0;
  if (v >= hi) return 1000;
  return idiv((v - lo) * 1000, hi - lo);
}

const HEX8 = /^[0-9a-fA-F]{8}/;

/** uint32 seed from an image hash (first 8 hex digits; else FNV-1a). */
export function imageSeed(imageHash: string): number {
  if (HEX8.test(imageHash)) return parseInt(imageHash.substring(0, 8), 16) >>> 0;
  return fnv1a32(imageHash);
}

const clamp = (v: number, lo: number, hi: number) => (v < lo ? lo : v > hi ? hi : v);

/** Kid-likeness 0..100 from energy / skill in tenths. */
export function kidLikeness(s: V3Spec, energy10: number, skill10: number): number {
  const e = clamp(energy10, 0, 1000);
  const k = 1000 - clamp(skill10, 0, 1000);
  return idiv(s.kidEnergyWeight * e + s.kidSkillWeight * k + 50, 100);
}

/** Largest-remainder split of `total` by `shares` (ties → lower index). */
export function largestRemainder(total: number, shares: readonly number[]): number[] {
  const sum = shares.reduce((a, b) => a + b, 0);
  if (sum <= 0) {
    const each = idiv(total, shares.length);
    const out = shares.map(() => each);
    for (let i = 0; i < total - each * shares.length; i++) out[i]! += 1;
    return out;
  }
  const out = shares.map((x) => idiv(total * x, sum));
  const rem = shares.map((x) => (total * x) % sum);
  let left = total - out.reduce((a, b) => a + b, 0);
  const order = shares.map((_, i) => i).sort((a, b) => rem[b]! - rem[a]! || a - b);
  for (let k = 0; left > 0; k++, left--) out[order[k % order.length]!]! += 1;
  return out;
}

/** Origin verdicts that make a hidden late bloomer. */
export const BLOOMER_ORIGINS: ReadonlySet<string> = new Set(['ai_generated', 'digital', 'printed', 'screen']);

export interface GenomeInput {
  features: FeatureVector;
  energy10: number;
  skill10: number;
  imageHash: string;
  origin?: string | null;
}

function affinities(s: V3Spec, f: FeatureVector, luck: number, rj: Mulberry32): number[] {
  const out: number[] = [];
  for (const code of STATS) {
    let sum = 0;
    for (const [t, w] of AFFINITY_TABLE[code]) sum += w * (t === 'luck' ? luck : term(f, t));
    let a = idiv(sum, 100);
    a = idiv(a * (s.affinityJitterMinPct + (rj.nextUint32() % s.affinityJitterSpan)), 100);
    out.push(a < s.affinityFloor ? s.affinityFloor : a);
  }
  return out;
}

function distribute(s: V3Spec, budget: number, aff: readonly number[]): number[] {
  const sumA = aff.reduce((a, b) => a + b, 0);
  const free = 1000 - 10 * s.minShareMille;
  return largestRemainder(
    budget,
    aff.map((a) => s.minShareMille * sumA + free * a),
  );
}

/**
 * Raises SP to `minLv1Sp`, taking the difference from the other nine stats
 * in proportion to their values (largest remainder). Total unchanged.
 */
function spFloor(s: V3Spec, st: number[]): number[] {
  const d = s.minLv1Sp - st[Stat.sp]!;
  if (d <= 0) return st;
  const others = st.map((_, i) => i).filter((i) => i !== Stat.sp);
  const take = largestRemainder(
    d,
    others.map((i) => st[i]!),
  );
  const out = [...st];
  out[Stat.sp] = s.minLv1Sp;
  others.forEach((i, k) => (out[i] = out[i]! - take[k]!));
  return out;
}

/** Shape → グー / チョキ / パー (ties gu > choki > pa). */
export function attributeOf(f: FeatureVector): Attr {
  const score = (k: keyof typeof ATTRIBUTE_RULE) =>
    ATTRIBUTE_RULE[k].reduce((acc, t) => acc + term(f, t), 0);
  const gu = score('gu');
  const choki = score('choki');
  const pa = score('pa');
  if (gu >= choki && gu >= pa) return 'gu';
  if (choki >= pa) return 'choki';
  return 'pa';
}

/** maxHp from stats. */
export function maxHpOf(s: V3Spec, st: readonly number[]): number {
  return (
    s.hpPerHp * st[Stat.hp]! +
    s.hpPerVit * st[Stat.vit]! +
    idiv(s.hpPerAvg * st.reduce((a, b) => a + b, 0), 10)
  );
}

export class Genome {
  readonly kid: number;
  /** INTERNAL — never surface. */
  readonly isBloomer: boolean;
  readonly attr: Attr;
  readonly jitterPct: number;
  readonly budget: number;
  readonly affinities: number[];
  /** Lv1 stats (pre-rebirth form for bloomers). */
  readonly base: number[];
  /** Per-stat growth per level, ‰ of the Lv1 stat (Σ = 400). */
  readonly growthMille: number[];
  /** Bloomers only: the regenerated "virtual Lv1" stats used from Lv50. */
  readonly rebirthBase: number[] | null;
  readonly seed: number;

  constructor(
    readonly spec: V3Spec,
    input: GenomeInput,
  ) {
    const s = spec;
    const seed = imageSeed(input.imageHash);
    const kid = kidLikeness(s, input.energy10, input.skill10);
    const bloomer = input.skill10 > s.bloomerSkillAbove10 || BLOOMER_ORIGINS.has(input.origin ?? '');
    const rj = new Mulberry32(deriveSeed(seed, 10));
    const jitterPct = s.budgetJitterMinPct + (rj.nextUint32() % s.budgetJitterSpan);
    const luck = rj.nextUint32() % 1001;
    const aff = affinities(s, input.features, luck, rj);
    const fullBudget = idiv((s.budgetBase + s.budgetPerKid * kid) * jitterPct, s.budgetDiv);
    const budget = bloomer ? idiv(fullBudget * s.bloomerPreBudgetPct, 100) : fullBudget;
    const base = spFloor(s, distribute(s, budget, aff));

    const rg = new Mulberry32(deriveSeed(seed, 11));
    const raw = aff.map(
      (a) => s.growthRawBase + idiv(a, s.growthRawAffinityDiv) + (rg.nextUint32() % s.growthRawJitterSpan),
    );
    const growth = largestRemainder(s.growthTotalMillePerLevel, raw);

    let rebirth: number[] | null = null;
    if (bloomer) {
      const rr = new Mulberry32(deriveSeed(seed, 13));
      const luck2 = rr.nextUint32() % 1001;
      const aff2 = affinities(s, input.features, luck2, rr);
      const b2 = idiv(
        idiv((s.budgetBase + s.budgetPerKid * s.rebirthKid) * jitterPct, s.budgetDiv) * s.rebirthBudgetPct,
        100,
      );
      rebirth = spFloor(s, distribute(s, b2, aff2));
    }
    this.kid = kid;
    this.isBloomer = bloomer;
    this.attr = attributeOf(input.features);
    this.jitterPct = jitterPct;
    this.budget = budget;
    this.affinities = aff;
    this.base = base;
    this.growthMille = growth;
    this.rebirthBase = rebirth;
    this.seed = seed;
  }

  rebornAt(level: number): boolean {
    return this.isBloomer && level >= this.spec.rebirthLevel;
  }

  /**
   * Gauge bars (2..5) from the Lv1 base SP of the active form (the rebirth
   * form once a hidden bloomer is reborn; `preForm` keeps the first form).
   */
  maxBarsAt(level: number, preForm = false): number {
    const st = this.rebornAt(level) && !preForm ? this.rebirthBase! : this.base;
    return maxBarsFor(this.spec, st[Stat.sp]!);
  }

  /** Max bars of the Lv1 form. */
  get maxBars(): number {
    return this.maxBarsAt(1);
  }

  /** Stats at `level`; `preForm` forces a bloomer's pre-rebirth formula. */
  statsAt(level: number, preForm = false): number[] {
    const s = this.spec;
    const l = clamp(level, 1, s.maxLevel);
    const g = this.growthMille;
    if (!this.isBloomer) {
      return this.base.map((b, i) => b + idiv(b * g[i]! * (l - 1), 1000));
    }
    if (l < s.rebirthLevel || preForm) {
      return this.base.map((b, i) => b + idiv(b * g[i]! * s.bloomerPreGrowthPct * (l - 1), 100000));
    }
    const pre = s.rebirthLevel - 1;
    const post = l - s.rebirthLevel;
    return this.rebirthBase!.map(
      (b, i) => b + idiv(b * g[i]! * (100 * pre + (100 + s.bloomerPostGrowthBoostPct) * post), 100000),
    );
  }

  /** Move budget factor (%) at `level`. */
  moveFactorPct(level: number): number {
    const s = this.spec;
    const legend = level >= s.rebirthLevel ? s.legendMoveBonusPct : 0;
    if (this.isBloomer) {
      if (level < s.rebirthLevel) return s.bloomerPreMoveFactorPct;
      return s.moveFactorBasePct + idiv(s.rebirthKid, s.moveFactorKidDiv) + legend + s.bloomerRebirthMoveBonusPct;
    }
    return s.moveFactorBasePct + idiv(this.kid, s.moveFactorKidDiv) + legend;
  }
}
