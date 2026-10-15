/**
 * Engine v3 adapter (docs/REALTIME_PROTOCOL.md §9 step 3): the golden vectors of
 * shared/battle_spec_v3/golden_vectors.json replayed THROUGH the server adapter (inputs at their
 * ticks), plus the hidden-state guarantees.
 */
import {
  eventLine,
  eventsHash,
  setupFromJson,
  setupToJson,
  type BattleEvent as V3Event,
  type FighterSetup as V3Setup,
} from "@doodle-battle/battle-engine-v3";
import { describe, expect, it } from "vitest";
import { UnsupportedFighterError, type BattleEvent, type FighterSetup, type FighterSource } from "../../src/engine";
import { loadEngine } from "../../src/engines";
import { V3Engine } from "../../src/engines/v3Engine";
import { goldenV3, v2EngineData } from "../helpers/v3Fixtures";

const golden = goldenV3();
const engine = new V3Engine();

function v2Source(id: string, engineData: Record<string, unknown>, level: number): FighterSource {
  return {
    snapshotId: id,
    ownerUid: "u",
    level,
    display: { characterName: id, imagePath: null },
    data: { schema: 2, name: id, level, engine: engineData },
  };
}

function setupOf(json: Record<string, unknown>): FighterSetup {
  const s = setupFromJson(json);
  return { attr: s.attr, moves: [], maxHp: 1, maxBars: s.maxBars, engineData: s };
}

/** Server events back to the engine's `{tick, type, data}` form (for the golden event hash). */
function toV3(events: readonly BattleEvent[]): V3Event[] {
  return events.map((e) => {
    const { tick, type, ...data } = e;
    return { tick, type, data: data as V3Event["data"] };
  });
}

/** Words that would reveal the hidden late-bloomer mechanic or the trust verdict. */
const HIDDEN = /trust|bloom|reborn|rebirth|origin|ai_generated|digital|printed|screen|imageHash|features|energy10|skill10|preForm|moveStream/i;

describe("Engine v3 adapter", () => {
  it("is what loadEngine('v3') returns", () => {
    const e = loadEngine("v3");
    expect(e).toBeInstanceOf(V3Engine);
    expect(e.engineId).toBe("v3.1");
    expect(e.tickHz).toBe(10);
    expect(e.hardCapTick).toBe(1800);
  });

  const battles = golden.battles as Record<string, any>[];
  it("has golden battles to replay", () => {
    expect(battles.length).toBeGreaterThanOrEqual(6);
  });

  battles.forEach((v, idx) => {
    it(`golden battle ${idx} replays through the adapter (winner, tick, HP, events, state hash)`, () => {
      const sim = engine.createBattle(setupOf(v.input.a), setupOf(v.input.b), { seed: v.input.seed });
      const log = v.expected.inputLog as [number, 0 | 1, number][];
      const events: BattleEvent[] = [];
      const acted: [number, number, number][] = [];
      while (!sim.finished) {
        const t = sim.tick + 1;
        const inp: [number | null, number | null] = [null, null];
        for (const [tick, side, slot] of log) if (tick === t) inp[side] = slot;
        const r = sim.step(inp);
        events.push(...r.events);
        for (const side of [0, 1] as const) if (r.acted[side]) acted.push([sim.tick, side, inp[side] ?? -1]);
        expect(sim.tick).toBeLessThanOrEqual(engine.hardCapTick);
      }
      const e = v.expected;
      expect(sim.winner).toBe(e.winner);
      expect(sim.endReason).toBe(e.endReason === "ko" ? "ko" : "timeout");
      expect(sim.tick).toBe(e.ticks);
      expect([sim.view(0).hp, sim.view(1).hp]).toEqual(e.hp);
      expect([sim.view(0).maxHp, sim.view(1).maxHp]).toEqual(e.maxHp);
      if (e.events) {
        // A さきどり the engine dropped as impossible (`inputIgnored`) never reaches the engine
        // online: the server refuses it at `select` time. Everything else is identical.
        const expected = (e.events as string[]).filter((l) => !l.split(" ")[1]?.startsWith("inputIgnored"));
        expect(toV3(events).map(eventLine)).toEqual(expected);
      } else {
        expect(events.length).toBe(e.eventCount);
        expect(eventsHash(toV3(events))).toBe(e.eventsFnv1a);
      }
      expect(sim.stateHash()).toBe((e.stateHash as number).toString(16).padStart(8, "0"));
      // Every logged input was used exactly at its tick: the replay = seed + input log.
      expect(acted).toEqual(log);
    });
  });

  it("rated fighters from v2 snapshots match the golden rated setups", () => {
    const genomes = golden.genomes as Record<string, any>[];
    for (const v of golden.ratedSetups as Record<string, any>[]) {
      const g = genomes[v.genomeIndex]!.input;
      const data = { features: g.features, energy10: g.energy10, skill10: g.skill10, imageHash: g.imageHash, trust: g.origin ?? null, proposals: [] };
      const f = engine.ratedFighter(v2Source("s", data, v.actualLevel), 50);
      expect(JSON.parse(JSON.stringify(setupToJson(f.engineData as V3Setup)))).toEqual(v.expected);
      expect(f.moves.map((m) => m.slot)).toEqual(f.moves.map((_, i) => i));
      expect(f.moves.length).toBe(v.actualLevel >= 50 ? 4 : v.actualLevel >= 10 ? 3 : 2);
    }
  });

  it("refuses snapshots that are not v2 characters (the hub answers NOT_FOUND)", () => {
    const v1: FighterSource = { snapshotId: "old", ownerUid: "u", level: 20, display: { characterName: "x", imagePath: null }, data: { statsLv1: {}, moves: [] } };
    expect(() => engine.ratedFighter(v1, 50)).toThrow(UnsupportedFighterError);
    expect(() => engine.ratedFighter(v2Source("bad", { features: {} }, 20), 50)).toThrow(UnsupportedFighterError);
  });

  it("never picks by itself: an idle side caps at its max bars (no decision timer)", () => {
    const a = engine.ratedFighter(v2Source("a", v2EngineData(0), 30), 50);
    const sim = engine.createBattle(a, a, { seed: 3 });
    for (let t = 0; t < 400; t++) sim.step([null, null]);
    expect(sim.view(0)).toMatchObject({ bars: a.maxBars, maxBars: a.maxBars, gauge: a.maxBars * 10_000 });
    expect(sim.view(0).hp).toBe(sim.view(0).maxHp);
    expect(sim.canUse(0, 0)).toBe(true);
    expect(a.moves.every((m) => sim.canQueue(0, m.slot) && m.bars >= 1 && m.bars <= a.maxBars)).toBe(true);
  });

  it("おまかせ and the AI only act through inputs, each on its own AI stream", () => {
    const a = engine.ratedFighter(v2Source("a", v2EngineData(0), 60), 50);
    const b = engine.ratedFighter(v2Source("b", v2EngineData(2, null), 60), 50);
    const sim = engine.createBattle(a, b, { seed: 5 });
    let acts = 0;
    while (!sim.finished) {
      const inp: [number | null, number | null] = [sim.omakaseInput(0), sim.aiInput(1, "strong", 4)];
      const r = sim.step(inp);
      for (const side of [0, 1] as const) {
        if (inp[side] !== null) expect(r.acted[side]).toBe(true);
        if (r.acted[side]) acts++;
      }
    }
    expect(acts).toBeGreaterThan(2);
  });

  it("does not leak engine.trust or the hidden form in anything a client can receive", () => {
    for (const level of [5, 49, 50, 100]) {
      const hidden = engine.ratedFighter(v2Source("h", v2EngineData(1, "ai_generated"), level), 50);
      const plain = engine.ratedFighter(v2Source("p", v2EngineData(2, null), level), 50);
      for (const f of [hidden, plain]) {
        const pub = { attr: f.attr, moves: f.moves, maxHp: f.maxHp, maxBars: f.maxBars };
        expect(JSON.stringify(pub)).not.toMatch(HIDDEN);
        expect(Object.keys(f.moves[0] ?? {}).sort()).toEqual(["attr", "bars", "name", "slot", "templateId"]);
      }
      const sim = engine.createBattle(hidden, plain, { seed: 11 + level });
      const keys = new Set<string>();
      while (!sim.finished) {
        const r = sim.step([sim.aiInput(0, "normal", 10), sim.omakaseInput(1)]);
        for (const e of r.events) {
          for (const k of Object.keys(e)) keys.add(k);
          expect(JSON.stringify(e)).not.toMatch(HIDDEN);
        }
        expect(Object.keys(sim.view(0)).sort()).toEqual(["bars", "casting", "gauge", "hp", "maxBars", "maxHp"]);
      }
      for (const k of keys) expect(k).not.toMatch(HIDDEN);
    }
  });
});
