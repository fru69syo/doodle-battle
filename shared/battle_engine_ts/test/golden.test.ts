import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  addXp, chooseCpuAction, computeDamage, defaultSpec, deriveSeed, fnv1a32, initBattle,
  maxStatsAtLevel, Mulberry32, resolveTurn, specialPowerAt, stageAtLevel, statsAtLevel, xpForBattle,
} from '../src';
import type { AiTier, BattleAction, BattleState, DamageInput, FighterSetup, Side, Stats } from '../src';

const golden = JSON.parse(
  readFileSync(join(__dirname, '..', '..', 'battle_spec', 'golden_vectors.json'), 'utf8'),
) as { specVersion: number; vectors: Vector[] };

type Vector = { kind: string; name: string; [k: string]: any };

const spec = defaultSpec;

describe('golden vectors', () => {
  it('matches spec version and has >= 40 battle vectors', () => {
    expect(golden.specVersion).toBe(spec.specVersion);
    expect(golden.vectors.filter((v) => v.kind === 'battle').length).toBeGreaterThanOrEqual(40);
  });

  for (const v of golden.vectors) {
    it(`[${v.kind}] ${v.name}`, () => {
      switch (v.kind) {
        case 'rng': {
          const seed = v.input.seed as number;
          const r = new Mulberry32(seed);
          expect(Array.from({ length: 8 }, () => r.nextUint32())).toEqual(v.expected.uint32);
          const r2 = new Mulberry32(seed);
          expect((v.input.intBounds as number[]).map((n) => r2.nextInt(n))).toEqual(v.expected.ints);
          expect(r2.state).toBe(v.expected.stateAfterInts);
          expect([0, 1, 2].map((s) => deriveSeed(seed, s))).toEqual(v.expected.deriveSeed);
          break;
        }
        case 'fnv':
          expect(fnv1a32(v.input as string)).toBe(v.expected);
          break;
        case 'damage':
          expect(computeDamage(spec, v.input as DamageInput)).toBe(v.expected);
          break;
        case 'battle': {
          if (v.initialFromSetup) {
            const s = v.setup as { a: FighterSetup; b: FighterSetup };
            expect(initBattle(spec, s.a, s.b)).toEqual(v.initial);
          }
          const rng = new Mulberry32(v.seed as number);
          let state = structuredClone(v.initial) as BattleState;
          (v.turns as [BattleAction, BattleAction][]).forEach(([x, y], i) => {
            const r = resolveTurn(spec, state, x, y, rng);
            expect(r.events, `events of turn ${i + 1}`).toEqual(v.expected.events[i]);
            state = r.state;
          });
          expect(state).toEqual(v.expected.final);
          expect(rng.state).toBe(v.expected.rngState);
          break;
        }
        case 'ai': {
          const rng = new Mulberry32(v.seed as number);
          const action = chooseCpuAction(spec, v.state as BattleState, v.side as Side, v.tier as AiTier, rng);
          expect(action).toBe(v.expected.action);
          expect(rng.state).toBe(v.expected.rngState);
          break;
        }
        case 'xp': {
          const i = v.input;
          const gained = xpForBattle(spec, {
            won: i.won, isShobo: i.isShobo, stageXpMultiplierPct: i.stageXpMultiplierPct, adBoost: i.adBoost,
          });
          expect({ xpGained: gained, ...addXp(spec, i.level, i.xp, gained) }).toEqual(v.expected);
          break;
        }
        case 'stats': {
          const base = v.input.base as Stats;
          const level = v.input.level as number;
          expect(statsAtLevel(spec, base, level, v.input.seeds)).toEqual(v.expected.stats);
          expect(maxStatsAtLevel(spec, base, level)).toEqual(v.expected.maxStats);
          expect(specialPowerAt(spec, level)).toBe(v.expected.specialPower);
          expect(stageAtLevel(spec, level)).toBe(v.expected.stage);
          break;
        }
        default:
          throw new Error(`unknown vector kind ${v.kind}`);
      }
    });
  }
});
