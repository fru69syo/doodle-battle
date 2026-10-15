import { describe, expect, it } from "vitest";
import type { BattleSim, FighterSource, Side } from "../../src/engine";
import { DevEngine, unlockedMoveCount } from "../../src/engines/devEngine";
import { deriveSeed, Mulberry32 } from "../../src/engines/rng";
import { MemoryStore } from "../helpers/memoryStore";

async function source(id: string, level = 20): Promise<FighterSource> {
  const st = new MemoryStore();
  st.addSnapshot(id, "u", { level, power: 90 });
  const s = await st.loadSnapshot(id);
  if (!s) throw new Error("no snapshot");
  return s;
}

/** Plays a battle where the AI plays both sides, returns the accepted inputs. */
function autoplay(sim: BattleSim): { tick: number; side: Side; slot: number }[] {
  const log: { tick: number; side: Side; slot: number }[] = [];
  while (!sim.finished) {
    const inputs: [number | null, number | null] = [null, null];
    for (const s of [0, 1] as const) inputs[s] = s === 0 ? sim.aiInput(s, "normal", 10) : sim.omakaseInput(s);
    const r = sim.step(inputs);
    for (const s of [0, 1] as const) if (r.acted[s]) log.push({ tick: sim.tick, side: s, slot: inputs[s] ?? -1 });
  }
  return log;
}

describe("rng (bit-exact with shared/battle_engine_ts)", () => {
  it("mulberry32 / deriveSeed known values", () => {
    const r = new Mulberry32(0);
    expect([r.nextUint32(), r.nextUint32()]).toEqual([1144304738, 1416247]);
    expect(deriveSeed(42, 0)).toBe(deriveSeed(42, 0));
    expect(deriveSeed(42, 0)).not.toBe(deriveSeed(42, 1));
  });
});

describe("DevEngine (stand-in)", () => {
  it("unlocks moves like the spec: 2 / 3 at Lv10 / 4 at Lv50", () => {
    expect([1, 9, 10, 49, 50, 100].map(unlockedMoveCount)).toEqual([2, 2, 3, 3, 4, 4]);
  });

  it("is deterministic and a replay of seed + accepted inputs reproduces the final state", async () => {
    const e = new DevEngine();
    const a = e.ratedFighter(await source("a"), 50);
    const b = e.ratedFighter(await source("b"), 50);
    const sim1 = e.createBattle(a, b, { seed: 1234 });
    const log = autoplay(sim1);
    expect(sim1.finished).toBe(true);
    expect(sim1.endReason).toBe("ko");

    // Replay: same seed, only the logged inputs at their ticks, no AI calls.
    const sim2 = e.createBattle(a, b, { seed: 1234 });
    let i = 0;
    while (!sim2.finished) {
      const inputs: [number | null, number | null] = [null, null];
      while (log[i] && log[i]?.tick === sim2.tick + 1) {
        const x = log[i];
        if (x) inputs[x.side] = x.slot;
        i++;
      }
      sim2.step(inputs);
    }
    expect(sim2.stateHash()).toBe(sim1.stateHash());
    expect(sim2.winner).toBe(sim1.winner);
  });

  it("never picks by itself: an idle side caps at its max bars", async () => {
    const e = new DevEngine();
    const a = e.ratedFighter(await source("a"), 50);
    const sim = e.createBattle(a, a, { seed: 1 });
    for (let t = 0; t < 400; t++) sim.step([null, null]);
    expect(sim.view(0).bars).toBe(a.maxBars);
    expect(sim.view(0).gauge).toBe(a.maxBars * 10_000);
    expect(sim.view(0).hp).toBe(sim.view(0).maxHp);
  });

  it("ends at the 3 minute cap by HP ratio", async () => {
    const e = new DevEngine();
    const a = e.ratedFighter(await source("a"), 50);
    const sim = e.createBattle(a, a, { seed: 7 });
    for (let t = 0; t < 1800 && !sim.finished; t++) sim.step([null, null]);
    expect(sim.finished).toBe(true);
    expect(sim.endReason).toBe("timeout");
    expect(sim.tick).toBe(1800);
  });
});
