import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  DEFAULT_SPEC as s,
  Genome,
  moveContextOf,
  parseFeatures,
  publicMoves,
  ratedFighterFromSnapshot,
  RealtimeBattle,
  validateCharacterClaimV2,
  xpToNext,
} from '../src';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const golden = JSON.parse(readFileSync(join(__dirname, '..', '..', 'battle_spec_v3', 'golden_vectors.json'), 'utf8')) as any;
const g0 = golden.genomes[0].input;
const hash = 'ab'.repeat(32);
const claim = (o: Record<string, unknown> = {}) => ({
  features: g0.features,
  energy10: g0.energy10,
  skill10: g0.skill10,
  imageHash: hash,
  level: 12,
  xp: 10,
  ...o,
});

describe('validateCharacterClaimV2', () => {
  it('accepts a valid claim and recomputes everything server-side', () => {
    const g = new Genome(s, { features: parseFeatures(g0.features)!, energy10: g0.energy10, skill10: g0.skill10, imageHash: hash });
    const r = validateCharacterClaimV2(claim({ stats: g.statsAt(12) }));
    expect(r.ok).toBe(true);
    expect(r.snapshot!.stats).toEqual(g.statsAt(12));
    expect(r.snapshot!.attribute).toBe(g.attr);
    expect((r.snapshot!.setup.moves as unknown[]).length).toBe(3);
    expect(r.snapshot!.rated.stats).toEqual(g.statsAt(50));
    expect(JSON.stringify(r.snapshot)).not.toMatch(/bloomer|rebirth|kid/i);
  });

  it('rejects tampered stats, bad features, levels, XP and hashes', () => {
    expect(validateCharacterClaimV2(claim({ stats: [999, 1, 1, 1, 1, 1, 1, 1, 1, 1] })).problems).toEqual(['STATS_MISMATCH']);
    expect(validateCharacterClaimV2(claim({ features: { roundness: 1.5 } })).problems).toEqual(['FEATURES_INVALID']);
    expect(validateCharacterClaimV2(claim({ level: 101 })).problems).toContain('LEVEL_INVALID');
    expect(validateCharacterClaimV2(claim({ xp: xpToNext(s, 12) })).problems).toEqual(['XP_INVALID']);
    expect(validateCharacterClaimV2(claim({ imageHash: 'zz' })).problems).toEqual(['IMAGE_HASH_INVALID']);
    expect(validateCharacterClaimV2(claim({ energy10: 2000 })).problems).toEqual(['SCORES_INVALID']);
    expect(validateCharacterClaimV2(claim({ verdict: 'photo' })).problems).toEqual(['VERDICT_INVALID']);
    expect(validateCharacterClaimV2(claim({ moves: [1, 2] })).problems).toEqual(['MOVES_INVALID']);
  });

  it('re-validates move proposals and drops bad rigs without rejecting', () => {
    const ctx = moveContextOf(claim())!;
    const r = validateCharacterClaimV2(
      claim({
        moves: [
          { template: 'strike', attribute: ctx.attribute, name: 'ばかパンチ', power: 200 },
          { template: 'heal', name: 'げんき', healPct: 40 },
          null,
        ],
        rig: { v: 1, width: 10, height: 10, root: [5, 5], chest: [5, 99], limbs: [] },
      }),
      { ngCheck: (x) => x.includes('ばか') },
    );
    expect(r.ok).toBe(true);
    expect(r.moveLog[0]).toBe('0:rejected:name');
    expect(r.moveLog[1]).toMatch(/^1:ok/);
    expect(r.snapshot!.proposals[0]).toBeNull();
    expect(r.snapshot!.proposals[1]).toMatchObject({ template: 'heal', name: 'げんき' });
    expect(r.rigDropped).toBe('body');
    expect(r.snapshot!.rig).toBeNull();
  });

  it('a cloud ai_generated verdict makes the hidden form (weaker stats)', () => {
    const normal = validateCharacterClaimV2(claim({ level: 30 }));
    const hidden = validateCharacterClaimV2(claim({ level: 30 }), { serverOrigin: 'ai_generated' });
    const sum = (x: number[]) => x.reduce((a, b) => a + b, 0);
    expect(sum(hidden.snapshot!.stats)).toBeLessThan(sum(normal.snapshot!.stats));
  });
});

describe('realtime wrapper', () => {
  it('rated fighter from snapshot data and a server-mode battle', () => {
    const data = { features: g0.features, energy10: g0.energy10, skill10: g0.skill10, imageHash: hash, proposals: [] };
    const a = ratedFighterFromSnapshot(data, 7)!;
    const b = ratedFighterFromSnapshot({ ...data, imageHash: 'cd'.repeat(32) }, 60)!;
    expect(a.setup.moves).toHaveLength(2);
    expect(b.setup.moves).toHaveLength(4);
    expect(publicMoves(a.setup)[0]).toHaveProperty('templateId');
    const rt = new RealtimeBattle(a.setup, b.setup, 42);
    let guard = 0;
    while (!rt.finished && guard++ < 5000) {
      // never auto-picks: a side only acts when the server passes an input
      const inp: [number | null, number | null] = [
        rt.isReady(0) ? rt.chooseMove(0, 'normal') : null,
        rt.isReady(1) ? rt.chooseMove(1, 'strong') : null,
      ];
      const r = rt.step(inp);
      if (inp[0] !== null) expect(r.acted[0]).toBe(true);
    }
    expect(rt.finished).toBe(true);
    expect(['ko', 'timeout']).toContain(rt.endReason);
    expect(rt.stateHash()).toMatch(/^[0-9a-f]{8}$/);
    const idle = new RealtimeBattle(a.setup, b.setup, 1);
    for (let t = 0; t < 200; t++) idle.step([null, null]);
    expect(idle.isReady(0)).toBe(true);
    expect(idle.battle.fighters[0].actions).toBe(0);
    expect(ratedFighterFromSnapshot({}, 5)).toBeNull();
  });
});
