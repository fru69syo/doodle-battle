/**
 * Move templates, budget points and shrink-to-fit. Bit-exact port of
 * app/lib/domain/battle_v3/moves.dart (docs/GAME_DESIGN_V2.md §5).
 */
import { type Attr, idiv, Stat, type StatIndex, STATS, statIndex, type V3Spec } from './spec';

export type MoveKind = 'physical' | 'special' | 'heal' | 'buff' | 'debuff' | 'status' | 'shield';
export type SecondaryType = 'none' | 'poison' | 'paralyze' | 'debuff' | 'drain';
export type StatusKind = 'poison' | 'paralyze';

export interface AtkFormula {
  code: string;
  a: StatIndex;
  pa: number;
  b: StatIndex;
  pb: number;
  physical: boolean;
}

export const ATK_FORMULAS: readonly AtkFormula[] = [
  { code: 'STR80_AGI20', a: Stat.str, pa: 80, b: Stat.agi, pb: 20, physical: true },
  { code: 'STR70_VIT30', a: Stat.str, pa: 70, b: Stat.vit, pb: 30, physical: true },
  { code: 'STR60_DEX40', a: Stat.str, pa: 60, b: Stat.dex, pb: 40, physical: true },
  { code: 'INT80_DEX20', a: Stat.intl, pa: 80, b: Stat.dex, pb: 20, physical: false },
  { code: 'INT70_RES30', a: Stat.intl, pa: 70, b: Stat.res, pb: 30, physical: false },
  { code: 'INT60_LUK40', a: Stat.intl, pa: 60, b: Stat.luk, pb: 40, physical: false },
];

export function atkFormula(code: unknown): AtkFormula | undefined {
  return ATK_FORMULAS.find((f) => f.code === code);
}

export const VFX = [
  'slash', 'punch', 'beam', 'orb', 'burst', 'wave', 'rain', 'spiral',
  'stars', 'hearts', 'bubbles', 'leaves', 'sparks', 'shield', 'glow',
] as const;
export const COLOURS = [
  'red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'pink',
  'black', 'white', 'rainbow',
] as const;

/** Stats a buff / debuff may target. */
export const STAGE_STATS: readonly StatIndex[] = [Stat.str, Stat.def, Stat.intl, Stat.res, Stat.agi, Stat.dex, Stat.luk];

export type Range = readonly [number, number];
export const clampRange = (r: Range, v: number) => (v < r[0] ? r[0] : v > r[1] ? r[1] : v);

export interface MoveTemplate {
  id: string;
  kind: MoveKind;
  ranges: Readonly<Record<string, Range>>;
}

const COMMON: Record<string, Range> = { spCost: [0, 50], castTicks: [0, 20], cooldownTicks: [0, 150] };
const DAMAGE1: Record<string, Range> = { power: [40, 200], hits: [1, 1], accuracy: [60, 100], critBonus: [0, 20], ...COMMON };
const DAMAGEN: Record<string, Range> = { power: [40, 200], hits: [2, 3], accuracy: [60, 100], critBonus: [0, 20], ...COMMON };

export const TEMPLATES: Readonly<Record<string, MoveTemplate>> = {
  strike: { id: 'strike', kind: 'physical', ranges: DAMAGE1 },
  combo: { id: 'combo', kind: 'physical', ranges: DAMAGEN },
  blast: { id: 'blast', kind: 'special', ranges: DAMAGE1 },
  barrage: { id: 'barrage', kind: 'special', ranges: DAMAGEN },
  heal: { id: 'heal', kind: 'heal', ranges: { healPct: [10, 40], spCost: [0, 50], castTicks: [0, 20], cooldownTicks: [60, 150] } },
  power_up: { id: 'power_up', kind: 'buff', ranges: { stages: [1, 2], durationTicks: [40, 120], ...COMMON } },
  weaken: { id: 'weaken', kind: 'debuff', ranges: { stages: [1, 2], durationTicks: [40, 120], accuracy: [60, 100], ...COMMON } },
  poison: { id: 'poison', kind: 'status', ranges: { chance: [30, 100], accuracy: [60, 100], ...COMMON } },
  paralyze: { id: 'paralyze', kind: 'status', ranges: { chance: [30, 100], accuracy: [60, 100], ...COMMON } },
  barrier: { id: 'barrier', kind: 'shield', ranges: { shieldPct: [20, 60], durationTicks: [20, 60], spCost: [0, 50], castTicks: [0, 5], cooldownTicks: [40, 150] } },
};

export const SECONDARY_RANGES: Readonly<Record<'chance' | 'drainPct', Range>> = { chance: [10, 50], drainPct: [10, 50] };

export const POISON_VALUE = 120;
export const PARALYZE_VALUE = 80;
export const DEBUFF_SECONDARY_VALUE = 40;
export const HEAL_VALUE_PER_PCT = 6;
export const HITS_ADJ_PCT = [100, 100, 103, 106] as const;
/** Duration of the 1-stage debuff of a damage move's secondary. */
export const DEBUFF_SECONDARY_TICKS = 60;

export const isDamageKind = (k: MoveKind) => k === 'physical' || k === 'special';

/** A concrete move (one slot). Defaults match the Dart `Move` constructor. */
export interface Move {
  template: string;
  attr: Attr;
  name: string;
  flavor: string;
  vfx: string;
  colour: string;
  atkFormula: AtkFormula;
  power: number;
  hits: number;
  accuracy: number;
  critBonus: number;
  spCost: number;
  castTicks: number;
  cooldownTicks: number;
  secondary: SecondaryType;
  secondaryChance: number;
  secondaryStat: StatIndex;
  drainPct: number;
  healPct: number;
  stat: StatIndex;
  stages: number;
  durationTicks: number;
  chance: number;
  shieldPct: number;
}

export function makeMove(p: Partial<Move> & { template: string; attr: Attr }): Move {
  return {
    name: '',
    flavor: '',
    vfx: 'punch',
    colour: 'red',
    atkFormula: ATK_FORMULAS[0]!,
    power: 0,
    hits: 1,
    accuracy: 100,
    critBonus: 0,
    spCost: 0,
    castTicks: 0,
    cooldownTicks: 0,
    secondary: 'none',
    secondaryChance: 0,
    secondaryStat: Stat.def,
    drainPct: 0,
    healPct: 0,
    stat: Stat.str,
    stages: 0,
    durationTicks: 0,
    chance: 0,
    shieldPct: 0,
    ...p,
  };
}

export const templateOf = (m: Move): MoveTemplate => TEMPLATES[m.template]!;
export const kindOf = (m: Move): MoveKind => templateOf(m).kind;
export const isDamage = (m: Move): boolean => isDamageKind(kindOf(m));
export const statusOf = (m: Move): StatusKind | null =>
  m.template === 'poison' ? 'poison' : m.template === 'paralyze' ? 'paralyze' : null;

/** JSON form (same keys and order as Dart `Move.toJson`). */
export function moveToJson(m: Move): Record<string, unknown> {
  const k = kindOf(m);
  const o: Record<string, unknown> = {
    template: m.template,
    attribute: m.attr,
    name: m.name,
    flavor: m.flavor,
    vfx: m.vfx,
    colour: m.colour,
  };
  if (isDamageKind(k)) {
    o.atkFormula = m.atkFormula.code;
    o.power = m.power;
    o.hits = m.hits;
    o.accuracy = m.accuracy;
    o.critBonus = m.critBonus;
    const sec: Record<string, unknown> = { type: m.secondary };
    if (m.secondary === 'poison' || m.secondary === 'paralyze' || m.secondary === 'debuff') sec.chance = m.secondaryChance;
    if (m.secondary === 'debuff') sec.stat = STATS[m.secondaryStat];
    if (m.secondary === 'drain') sec.drainPct = m.drainPct;
    o.secondary = sec;
  }
  if (k === 'heal') o.healPct = m.healPct;
  if (k === 'buff' || k === 'debuff') {
    o.stat = STATS[m.stat];
    o.stages = m.stages;
    o.durationTicks = m.durationTicks;
  }
  if (k === 'debuff' || k === 'status') o.accuracy = m.accuracy;
  if (k === 'status') o.chance = m.chance;
  if (k === 'shield') {
    o.shieldPct = m.shieldPct;
    o.durationTicks = m.durationTicks;
  }
  o.spCost = m.spCost;
  o.castTicks = m.castTicks;
  o.cooldownTicks = m.cooldownTicks;
  return o;
}

/** Inverse of `moveToJson` for already-validated moves (not a validator). */
export function moveFromJson(j: Record<string, unknown>): Move {
  const i = (k: string, d = 0) => (typeof j[k] === 'number' ? (j[k] as number) : d);
  const sec = (j.secondary ?? null) as Record<string, unknown> | null;
  const stat = typeof j.stat === 'string' ? statIndex(j.stat) : undefined;
  return makeMove({
    template: j.template as string,
    attr: j.attribute as Attr,
    name: (j.name as string | undefined) ?? '',
    flavor: (j.flavor as string | undefined) ?? '',
    vfx: (j.vfx as string | undefined) ?? 'punch',
    colour: (j.colour as string | undefined) ?? 'white',
    atkFormula: atkFormula(j.atkFormula) ?? ATK_FORMULAS[0]!,
    power: i('power'),
    hits: i('hits', 1),
    accuracy: i('accuracy', 100),
    critBonus: i('critBonus'),
    spCost: i('spCost'),
    castTicks: i('castTicks'),
    cooldownTicks: i('cooldownTicks'),
    secondary: sec === null ? 'none' : (sec.type as SecondaryType),
    secondaryChance: typeof sec?.chance === 'number' ? sec.chance : 0,
    secondaryStat: typeof sec?.stat === 'string' ? (statIndex(sec.stat) ?? Stat.def) : Stat.def,
    drainPct: typeof sec?.drainPct === 'number' ? sec.drainPct : 0,
    healPct: i('healPct'),
    stat: stat ?? Stat.str,
    stages: i('stages'),
    durationTicks: i('durationTicks'),
    chance: i('chance'),
    shieldPct: i('shieldPct'),
  });
}

/** Minimum cooldown that is "free" (not discounted). */
export function freeCooldown(m: Move): number {
  switch (kindOf(m)) {
    case 'heal':
      return 60;
    case 'buff':
    case 'debuff':
      return m.durationTicks > 20 ? m.durationTicks : 20;
    case 'shield':
      return 40;
    default:
      return 20;
  }
}

/** Gross value in budget points. */
export function moveValue(m: Move): number {
  switch (kindOf(m)) {
    case 'physical':
    case 'special': {
      let v = idiv(m.power * m.accuracy * (200 + m.critBonus) * HITS_ADJ_PCT[m.hits]!, 100 * 200 * 100);
      switch (m.secondary) {
        case 'poison':
          v += idiv(m.secondaryChance * POISON_VALUE, 100);
          break;
        case 'paralyze':
          v += idiv(m.secondaryChance * PARALYZE_VALUE, 100);
          break;
        case 'debuff':
          v += idiv(m.secondaryChance * DEBUFF_SECONDARY_VALUE, 100);
          break;
        case 'drain':
          v += idiv(m.drainPct * m.power, 100);
          break;
        default:
          break;
      }
      return v;
    }
    case 'heal':
      return m.healPct * HEAL_VALUE_PER_PCT;
    case 'buff':
      return idiv(m.stages * m.durationTicks * 5 * (m.stat === Stat.agi ? 120 : 100), 800);
    case 'debuff':
      return idiv(m.stages * m.durationTicks * 5 * (m.stat === Stat.agi ? 120 : 100) * m.accuracy, 80000);
    case 'status': {
      const sv = statusOf(m) === 'poison' ? POISON_VALUE : PARALYZE_VALUE;
      return idiv(sv * m.chance * m.accuracy, 10000);
    }
    case 'shield':
      return idiv(m.shieldPct * m.durationTicks, 30);
  }
}

/** Discount for SP, cast time and extra cooldown (capped). */
export function moveDiscount(s: V3Spec, m: Move): number {
  const free = freeCooldown(m);
  const d = idiv(m.spCost * 5, 4) + m.castTicks * 2 + (m.cooldownTicks > free ? idiv(m.cooldownTicks - free, 2) : 0);
  const cap = idiv(moveValue(m) * s.maxDiscountPct, 100);
  return d < cap ? d : cap;
}

export function moveCost(s: V3Spec, m: Move): number {
  return moveValue(m) - moveDiscount(s, m);
}

/** Budget of `slot` (0..3) at `moveFactorPct`. */
export function slotBudget(s: V3Spec, slot: number, moveFactorPct: number): number {
  return idiv(s.slotBudgets[slot]! * moveFactorPct, 100);
}

/** Shrinks the primary magnitude until the move fits; null when impossible. */
export function fitToBudget(s: V3Spec, m0: Move, budget: number): Move | null {
  let m = m0;
  for (let guard = 0; guard < 400; guard++) {
    if (moveCost(s, m) <= budget) return m;
    const r = templateOf(m).ranges;
    switch (kindOf(m)) {
      case 'physical':
      case 'special':
        if (m.power - 5 >= r.power![0]) m = { ...m, power: m.power - 5 };
        else if (m.secondary !== 'none') m = { ...m, secondary: 'none' };
        else return null;
        break;
      case 'heal':
        if (m.healPct - 1 < r.healPct![0]) return null;
        m = { ...m, healPct: m.healPct - 1 };
        break;
      case 'buff':
      case 'debuff':
        if (m.durationTicks - 10 >= r.durationTicks![0]) m = { ...m, durationTicks: m.durationTicks - 10 };
        else if (m.stages > 1) m = { ...m, stages: m.stages - 1 };
        else return null;
        break;
      case 'status':
        if (m.chance - 5 < r.chance![0]) return null;
        m = { ...m, chance: m.chance - 5 };
        break;
      case 'shield':
        if (m.shieldPct - 5 >= r.shieldPct![0]) m = { ...m, shieldPct: m.shieldPct - 5 };
        else if (m.durationTicks - 5 >= r.durationTicks![0]) m = { ...m, durationTicks: m.durationTicks - 5 };
        else return null;
        break;
    }
  }
  return null;
}
