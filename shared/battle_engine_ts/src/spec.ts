/** Typed view of shared/battle_spec/battle_spec.json. */
import { SPEC_DATA } from './generated/specData';
import type { AiTier, BattleAction, ElementType, EvolutionStage } from './types';
import { ELEMENTS } from './types';

export interface AttackMoveSpec {
  label: string;
  power: number;
  accuracyPct: number;
  typed: boolean;
}

export interface CpuStage {
  stage: number;
  cpuId: string;
  level: number;
  recommendedLevel: number;
  aiTier: AiTier;
  xpMultiplierPct: number;
}

export interface BattleSpec {
  specVersion: number;
  hpMultiplier: number;
  turnCap: number;
  timeoutAction: BattleAction;
  damage: {
    scalePct: number;
    basePower: number;
    defenseWeight: number;
    minDamage: number;
    critChancePct: number;
    critMultiplierPct: number;
    varianceMinPct: number;
    varianceMaxPct: number;
  };
  typeChart: {
    advantagePct: number;
    disadvantagePct: number;
    neutralPct: number;
    matrix: Record<ElementType, Record<ElementType, number>>;
  };
  moves: {
    tackle: AttackMoveSpec;
    element: AttackMoveSpec;
    guard: { label: string; damageTakenPctByStreak: number[] };
    special: AttackMoveSpec;
  };
  gauge: {
    max: number;
    onHit: number;
    onMiss: number;
    onGuard: number;
    onDamagedFlat: number;
    onDamagedPctOfMaxHp: number;
  };
  growth: {
    maxLevel: number;
    levelUpStatPct: number;
    shoboLevelUpStatPct: number;
    shoboSkillAbove: number;
    seedStatPct: number;
    seedsPerLevel: number;
    xpToNextBase: number;
    xpToNextPerLevel: number;
    evolutions: { level: number; stage: EvolutionStage; specialPowerBonus: number }[];
  };
  xp: { win: number; lose: number; shoboBonusPct: number; adBoostMultiplier: number };
  ai: {
    weak: { tackleWeight: number; elementWeight: number; guardWeight: number; specialWeight: number };
    normal: { guardChancePct: number };
    strong: { guardVsSpecialPct: number; opponentGuardRatePct: number; opponentGuardMinSamples: number };
  };
  texts: Record<string, string>;
  cpu: { characterIds: string[]; stages: CpuStage[] };
}

function fail(path: string): never {
  throw new Error(`battle_spec: invalid or missing ${path}`);
}

function checkInts(obj: unknown, path: string, keys: string[]): void {
  if (typeof obj !== 'object' || obj === null) fail(path);
  for (const k of keys) {
    const v = (obj as Record<string, unknown>)[k];
    if (typeof v !== 'number' || !Number.isInteger(v)) fail(`${path}.${k}`);
  }
}

/** Validates the JSON shape (integer constants, full type matrix) and returns it typed. */
export function parseSpec(json: unknown): BattleSpec {
  const s = json as BattleSpec;
  checkInts(s, 'spec', ['specVersion', 'hpMultiplier', 'turnCap']);
  checkInts(s.damage, 'damage', [
    'scalePct', 'basePower', 'defenseWeight', 'minDamage', 'critChancePct',
    'critMultiplierPct', 'varianceMinPct', 'varianceMaxPct',
  ]);
  checkInts(s.gauge, 'gauge', ['max', 'onHit', 'onMiss', 'onGuard', 'onDamagedFlat', 'onDamagedPctOfMaxHp']);
  for (const m of ['tackle', 'element', 'special'] as const) {
    checkInts(s.moves?.[m], `moves.${m}`, ['power', 'accuracyPct']);
  }
  if (!Array.isArray(s.moves.guard?.damageTakenPctByStreak) || s.moves.guard.damageTakenPctByStreak.length === 0) {
    fail('moves.guard.damageTakenPctByStreak');
  }
  for (const a of ELEMENTS) checkInts(s.typeChart?.matrix?.[a], `typeChart.matrix.${a}`, [...ELEMENTS]);
  checkInts(s.growth, 'growth', ['maxLevel', 'levelUpStatPct', 'shoboLevelUpStatPct', 'shoboSkillAbove', 'seedStatPct', 'seedsPerLevel', 'xpToNextBase', 'xpToNextPerLevel']);
  checkInts(s.xp, 'xp', ['win', 'lose', 'shoboBonusPct', 'adBoostMultiplier']);
  if (!Array.isArray(s.cpu?.stages)) fail('cpu.stages');
  return s;
}

/** The spec bundled with this package (generated from battle_spec.json). */
export const defaultSpec: BattleSpec = parseSpec(SPEC_DATA);
