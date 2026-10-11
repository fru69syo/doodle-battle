import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  aiController,
  type AiTier,
  applyXp,
  ATTRS,
  Battle,
  type Controller,
  DEFAULT_SPEC,
  deriveSeed,
  eloDelta,
  eloExpectedMille,
  eventLine,
  eventsHash,
  fnv1a32,
  generateOfflineMoves,
  Genome,
  maxHpOf,
  moveCost,
  moveDiscount,
  moveFromJson,
  moveToJson,
  moveValue,
  parseFeatures,
  RealtimeBattle,
  ratedSetup,
  rigProblem,
  setupFromJson,
  setupToJson,
  stageTable,
  validateAiMove,
  validateAiMoveSet,
  validationToJson,
  xpOnline,
  xpSinglePlayer,
  xpToNext,
  type Attr,
} from '../src';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Any = any;
const golden = JSON.parse(
  readFileSync(join(__dirname, '..', '..', 'battle_spec_v3', 'golden_vectors.json'), 'utf8'),
) as Record<string, Any>;
const s = DEFAULT_SPEC;
const ngWords: string[] = ['ばか', 'しね'];
const ngCheck = (x: string) => ngWords.some((w) => x.includes(w));
const norm = (o: unknown) => JSON.parse(JSON.stringify(o));

function genomeOf(v: Any): Genome {
  const i = v.input;
  return new Genome(s, {
    features: parseFeatures(i.features)!,
    energy10: i.energy10,
    skill10: i.skill10,
    imageHash: i.imageHash,
    origin: i.origin,
  });
}
const genomes: Genome[] = (golden.genomes as Any[]).map(genomeOf);

function runGolden(input: Any): Battle {
  const b = new Battle(s, setupFromJson(input.a), setupFromJson(input.b), input.seed);
  const ctl = (j: Any): Controller | null =>
    j === null ? null : aiController({ thinkTicks: j.think, tier: j.tier as AiTier });
  const ca = ctl(input.controllers[0]);
  const cb = ctl(input.controllers[1]);
  const inputs = (input.inputs ?? []) as number[][];
  while (!b.finished) {
    for (const x of inputs) if (x[0] === b.tick + 1) b.queueInput(x[1]!, x[2]!);
    b.step(ca, cb);
  }
  return b;
}

describe('golden vectors (shared with the Dart engine)', () => {
  it('has >= 60 vectors and the spec version', () => {
    let n = 0;
    for (const [k, v] of Object.entries(golden)) {
      if (k === 'conventions') continue;
      if (Array.isArray(v)) n += v.length;
      else if (typeof v === 'object' && v !== null) n += Object.keys(v).length;
    }
    expect(n).toBeGreaterThanOrEqual(60);
    expect(golden.specVersion).toBe(s.specVersion);
  });

  it('deriveSeed', () => {
    for (const v of golden.deriveSeed) expect(deriveSeed(v.seed, v.stream)).toBe(v.expected);
  });

  (golden.genomes as Any[]).forEach((v, idx) => {
    it(`genome ${idx}`, () => {
      const g = genomes[idx]!;
      const e = v.expected;
      expect(g.kid).toBe(e.kid);
      expect(g.isBloomer).toBe(e.isBloomer);
      expect(g.attr).toBe(e.attribute);
      expect(g.jitterPct).toBe(e.jitterPct);
      expect(g.budget).toBe(e.budget);
      expect(g.affinities).toEqual(e.affinities);
      expect(g.base).toEqual(e.base);
      expect(g.growthMille).toEqual(e.growthMille);
      expect(g.rebirthBase).toEqual(e.rebirthBase);
      for (const l of [1, 10, 49, 50, 75, 100]) expect(g.statsAt(l)).toEqual(e.statsAt[`${l}`]);
      for (const l of [1, 50, 100]) expect(maxHpOf(s, g.statsAt(l))).toBe(e.maxHpAt[`${l}`]);
      for (const l of [1, 49, 50]) expect(g.moveFactorPct(l)).toBe(e.moveFactorPct[`${l}`]);
    });
  });

  (golden.offlineMoves as Any[]).forEach((v, idx) => {
    it(`offline moves ${idx}`, () => {
      const ms = generateOfflineMoves(s, genomes[v.genomeIndex]!, {
        moveFactorPct: v.moveFactorPct,
        stream: v.stream,
        attr: v.attribute as Attr | null,
      });
      expect(ms.map((m) => ({ ...moveToJson(m), cost: moveCost(s, m) }))).toEqual(v.expected);
    });
  });

  (golden.validator as Any[]).forEach((v, idx) => {
    it(`validator ${idx}`, () => {
      const r = validateAiMove(s, v.input, { slot: v.slot, own: v.own as Attr, moveFactorPct: v.moveFactorPct, ngCheck });
      expect(validationToJson(s, r)).toEqual(v.expected);
    });
  });

  (golden.validatorSets as Any[]).forEach((v, idx) => {
    it(`validator set ${idx}`, () => {
      const r = validateAiMoveSet(s, v.input, { own: v.own as Attr, moveFactorPct: v.moveFactorPct, ngCheck });
      expect(r.map((x) => validationToJson(s, x.result))).toEqual(v.expected);
    });
  });

  (golden.battles as Any[]).forEach((v, idx) => {
    it(`battle ${idx}: ${v.input.note}`, () => {
      const b = runGolden(v.input);
      const e = v.expected;
      expect(b.winner).toBe(e.winner);
      expect(b.endReason).toBe(e.endReason);
      expect(b.tick).toBe(e.ticks);
      expect(b.fighters.map((f) => f.hp)).toEqual(e.hp);
      expect(b.fighters.map((f) => f.maxHp)).toEqual(e.maxHp);
      expect(b.fighters.map((f) => f.actions)).toEqual(e.actions);
      if (e.events) expect(b.events.map(eventLine)).toEqual(e.events);
      expect(b.events.length).toBe(e.eventCount);
      expect(eventsHash(b.events)).toBe(e.eventsFnv1a);
      expect(b.stateHash()).toBe(e.stateHash);
    });

    it(`battle ${idx} replays from its input log in server mode`, () => {
      const rt = new RealtimeBattle(setupFromJson(v.input.a), setupFromJson(v.input.b), v.input.seed);
      const log = v.expected.inputLog as number[][];
      while (!rt.finished) {
        const t = rt.tick + 1;
        const inp: [number | null, number | null] = [null, null];
        for (const x of log) if (x[0] === t) inp[x[1] as 0 | 1] = x[2]!;
        rt.step(inp);
      }
      expect(rt.winner).toBe(v.expected.winner);
      expect(rt.tick).toBe(v.expected.ticks);
      expect(rt.battle.fighters.map((f) => f.hp)).toEqual(v.expected.hp);
      expect(rt.battle.stateHash()).toBe(v.expected.stateHash);
    });
  });

  it('move cost', () => {
    for (const v of golden.moveCost) {
      const m = moveFromJson(v.move);
      expect([moveValue(m), moveDiscount(s, m), moveCost(s, m)]).toEqual([v.value, v.discount, v.cost]);
    }
  });

  it('rated setups', () => {
    for (const v of golden.ratedSetups) {
      expect(norm(setupToJson(ratedSetup(s, genomes[v.genomeIndex]!, v.actualLevel)))).toEqual(v.expected);
    }
  });

  it('xp, applyXp, xpToNext, elo, stage table, rig', () => {
    for (const v of golden.xp) expect(xpSinglePlayer(v)).toBe(v.expected);
    for (const v of golden.xpOnline) expect(xpOnline(v)).toBe(v.expected);
    for (const v of golden.applyXp) {
      const p = applyXp(s, v);
      expect({ level: p.level, xp: p.xp, newSlots: p.newSlots, evolutions: p.evolutions, rebirth: p.rebirth }).toEqual(v.expected);
    }
    for (const [k, v] of Object.entries(golden.xpToNext)) expect(xpToNext(s, Number(k))).toBe(v);
    for (const v of golden.elo) {
      expect(eloExpectedMille(v.ratingA, v.ratingB)).toBe(v.expectedMille);
      expect(eloDelta(v.ratingA, v.ratingB, v.aWon, v.k)).toBe(v.delta);
    }
    expect(fnv1a32(JSON.stringify(stageTable()))).toBe(golden.stagesFnv1a);
    for (const v of golden.rig) expect(rigProblem(v.input)).toBe(v.problem);
    expect(ATTRS).toContain('gu');
  });
});
