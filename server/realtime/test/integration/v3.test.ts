/**
 * End-to-end with Engine v3 over real WebSockets: v2 (schema 2) snapshots as written by
 * registerCharacter, one of them with the hidden verdict `engine.trust = "ai_generated"`.
 * Checks that a full match works, replays from seed + inputs, matches the protocol schema and
 * that NO message a child receives reveals the trust verdict or the hidden late-bloomer form.
 */
import { afterEach, describe, expect, it } from "vitest";
import { InsecureDevVerifier } from "../../src/auth";
import { COST_MODES, StaticCostMode, type CostMode, type CostModeSource } from "../../src/costMode";
import { loadEngine } from "../../src/engines";
import { Hub } from "../../src/hub";
import { silentLogger } from "../../src/log";
import type { ServerMsg } from "../../src/protocol";
import { RealtimeServer } from "../../src/server";
import { TestClient } from "../helpers/client";
import { MemoryStore } from "../helpers/memoryStore";
import { serverMessageValidator } from "../helpers/schema";
import { v2EngineData } from "../helpers/v3Fixtures";

const TICK_MS = 1;
const HIDDEN = /trust|bloom|reborn|rebirth|origin|ai_generated|digital|printed|screen|imageHash|features|energy10|skill10|proposals|preForm|moveStream|engineData/i;

interface Env {
  server: RealtimeServer;
  store: MemoryStore;
  url: string;
  clients: TestClient[];
}
let env: Env | null = null;

async function start(costMode: CostModeSource = new StaticCostMode("normal"), configure?: (s: MemoryStore) => void): Promise<Env> {
  const store = new MemoryStore();
  store.addUser("alice");
  store.addUser("bob");
  // Alice's character is a hidden late bloomer (AI picture), Lv60 = already reborn.
  store.addV2Snapshot("snapA", "alice", v2EngineData(1, "ai_generated"), { level: 60 });
  store.addV2Snapshot("snapB", "bob", v2EngineData(2, null), { level: 30 });
  store.addSnapshot("snapV1", "alice"); // a v1 snapshot: not battleable under Engine v3
  configure?.(store);
  const hub = new Hub({ engine: loadEngine("v3"), store, costMode, log: silentLogger, matchmakingEveryTicks: 1 });
  const server = new RealtimeServer({
    config: { port: 0, tickMs: TICK_MS, maxConnections: 50, helloTimeoutMs: 1000, idleTimeoutMs: 60_000, maxConnectionMs: 60_000, shutdownGraceMs: 2000, engine: "v3" },
    hub,
    verifier: new InsecureDevVerifier(),
    log: silentLogger,
  });
  const port = await server.listen(0, "127.0.0.1");
  env = { server, store, url: `ws://127.0.0.1:${port}/v2`, clients: [] };
  return env;
}

async function client(e: Env, uid: string): Promise<TestClient> {
  const c = await TestClient.open(e.url);
  e.clients.push(c);
  c.hello(uid);
  await c.waitFor("welcome");
  return c;
}

afterEach(async () => {
  if (!env) return;
  for (const c of env.clients) c.close();
  await env.server.close();
  env = null;
});

const FIGHTER_KEYS = ["attr", "badge", "characterName", "displayName", "imagePath", "isGhost", "level", "maxHp", "moves", "rig", "snapshotId"];

function expectNothingHidden(messages: readonly ServerMsg[]): void {
  const leaks = messages.filter((m) => HIDDEN.test(JSON.stringify(m)));
  expect(leaks).toEqual([]);
  // FighterInfo carries only the public fields; `snapshotId` is the plain document id.
  for (const m of messages) {
    if (m.t !== "match") continue;
    for (const f of [m.a, m.b]) {
      expect(Object.keys(f).filter((k) => !FIGHTER_KEYS.includes(k))).toEqual([]);
      expect(f.snapshotId).toMatch(/^[A-Za-z0-9_-]+$/);
    }
  }
}

describe("realtime server with Engine v3 (integration)", () => {
  it("plays a full rated PvP match; nothing hidden reaches the children", async () => {
    const e = await start();
    const alice = await client(e, "alice");
    const bob = await client(e, "bob");
    alice.autoplay(0);
    bob.autoplay(1);
    alice.send({ t: "queue", snapshotId: "snapA" });
    bob.send({ t: "queue", snapshotId: "snapB" });
    const mA = await alice.waitFor("match");
    const me = mA.you === "a" ? mA.a : mA.b;
    const foe = mA.you === "a" ? mA.b : mA.a;
    expect(me.moves).toHaveLength(4); // Lv60: four moves
    expect(foe.moves).toHaveLength(3); // Lv30: three moves
    expect(me.level).toBe(50);
    // Each side carries its public snapshot id (reports, SPEC §9.4), the same for both apps.
    expect([me.snapshotId, foe.snapshotId]).toEqual(["snapA", "snapB"]);
    const mB = await bob.waitFor("match");
    expect([mB.a.snapshotId, mB.b.snapshotId].sort()).toEqual(["snapA", "snapB"]);

    const endA = await alice.waitFor("end", undefined, 30_000);
    const endB = await bob.waitFor("end", undefined, 30_000);
    expect(["ko", "timeout"]).toContain(endA.reason);
    expect([endA.you.outcome, endB.you.outcome].sort()).toEqual(["lose", "win"]);

    // Engine v3 events reached the clients (moveStart / hit / ...), in seq order.
    const evs = alice.messages.flatMap((m) => (m.t === "ev" ? m.events : []));
    expect(evs.some((x) => x.type === "moveStart")).toBe(true);
    expect(alice.messages.some((m) => m.t === "sel" && m.accepted)).toBe(true);

    const all = [...alice.messages, ...bob.messages];
    const valid = serverMessageValidator();
    expect(all.filter((m) => !valid(m))).toEqual([]);
    expectNothingHidden(all);

    // Replay = seed + logged inputs through the same adapter.
    const rep = e.store.replays.get(mA.matchId);
    if (!rep) throw new Error("no replay");
    expect(rep.engineId).toBe("v3.0");
    const engine = loadEngine("v3");
    const setup = async (id: string) => {
      const s = await e.store.loadSnapshot(id);
      if (!s) throw new Error(id);
      return engine.ratedFighter(s, 50);
    };
    const sim = engine.createBattle(await setup(rep.sides[0].snapshotId), await setup(rep.sides[1].snapshotId), { seed: rep.seed });
    let i = 0;
    while (!sim.finished) {
      const inputs: [number | null, number | null] = [null, null];
      for (; rep.inputs[i]?.tick === sim.tick + 1; i++) {
        const x = rep.inputs[i];
        if (x) inputs[x.side] = x.slot;
      }
      sim.step(inputs);
    }
    expect(sim.stateHash()).toBe(rep.finalHash);
  });

  it("a hidden-form ghost reveals nothing either", async () => {
    const quick: CostModeSource = { current: (): CostMode => ({ mode: "saving", flags: { ...COST_MODES.saving, ghostAfterSec: 0.05 } }) };
    const e = await start(quick, (s) => {
      s.snapshots.delete("snapB");
      s.addV2Snapshot("ghostH", "carol", v2EngineData(3, "digital"), { level: 45, ghostRating: 1000 });
    });
    const alice = await client(e, "alice");
    alice.autoplay(0);
    alice.send({ t: "queue", snapshotId: "snapA" });
    const m = await alice.waitFor("match");
    expect((m.you === "a" ? m.b : m.a).isGhost).toBe(true);
    expect((m.you === "a" ? m.b : m.a).snapshotId).toBe("ghostH");
    await alice.waitFor("end", undefined, 30_000);
    expectNothingHidden(alice.messages);
  });

  it("おまかせ switch: the server plays for the child (no timeout picks); deadline events are exact", async () => {
    const e = await start();
    const alice = await client(e, "alice");
    const bob = await client(e, "bob");
    bob.autoplay(0);
    alice.onMessage = (m, c) => {
      if (m.t === "match") c.send({ t: "omakase", on: true });
    };
    alice.send({ t: "queue", snapshotId: "snapA" });
    bob.send({ t: "queue", snapshotId: "snapB" });
    const mA = await alice.waitFor("match");
    expect(await alice.waitFor("omakase")).toEqual({ t: "omakase", on: true });
    await alice.waitFor("end", undefined, 30_000);
    const mySide = mA.you === "a" ? 0 : 1;
    const evs = alice.messages.flatMap((m) => (m.t === "ev" ? m.events : []));
    expect(evs.some((x) => x.type === "autoPick" && x.side === mySide)).toBe(false);
    expect(evs.some((x) => x.type === "select" && x.side === mySide)).toBe(true);
    const rep = e.store.replays.get(mA.matchId);
    if (!rep) throw new Error("no replay");
    const mine = rep.inputs.filter((x) => x.side === mySide);
    expect(mine.length).toBeGreaterThan(0);
    expect(mine.every((x) => x.src === "omakase")).toBe(true);
    // Every ready of a child is followed (same tick) by its deadline; bob's picks come before it.
    const deadlines = evs.filter((x) => x.type === "deadline");
    expect(deadlines.length).toBeGreaterThan(0);
    for (const d of deadlines) expect(d.at).toBe(d.tick + 52);
    expect(bob.messages.some((m) => m.t === "omakase")).toBe(false);
    const valid = serverMessageValidator();
    expect([...alice.messages, ...bob.messages].filter((m) => !valid(m))).toEqual([]);
    expectNothingHidden([...alice.messages, ...bob.messages]);
  });

  it("answers NOT_FOUND for a v1 snapshot (the app registers it again)", async () => {
    const e = await start();
    const alice = await client(e, "alice");
    alice.send({ t: "queue", snapshotId: "snapV1" });
    const err = await alice.waitFor("error");
    expect(err.code).toBe("NOT_FOUND");
    expectNothingHidden(alice.messages);
  });
});
