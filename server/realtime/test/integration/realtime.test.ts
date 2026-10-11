/**
 * End-to-end over real WebSockets: a local server with the dev engine, an in-memory store and
 * dev tokens. Two simulated children play a full rated match; the result is checked in the
 * store and replayed from seed + inputs.
 */
import { afterEach, describe, expect, it } from "vitest";
import { InsecureDevVerifier } from "../../src/auth";
import { COST_MODES, StaticCostMode, type CostMode, type CostModeSource } from "../../src/costMode";
import { DevEngine } from "../../src/engines/devEngine";
import { Hub } from "../../src/hub";
import { silentLogger } from "../../src/log";
import { RealtimeServer } from "../../src/server";
import { TestClient } from "../helpers/client";
import { MemoryStore } from "../helpers/memoryStore";

const TICK_MS = 2;

interface Env {
  server: RealtimeServer;
  hub: Hub;
  store: MemoryStore;
  url: string;
  clients: TestClient[];
}

let env: Env | null = null;

async function start(costMode: CostModeSource = new StaticCostMode("normal"), configure?: (s: MemoryStore) => void): Promise<Env> {
  const store = new MemoryStore();
  store.addUser("alice");
  store.addUser("bob");
  store.addUser("kid3", { consentOnline: false });
  store.addSnapshot("snapA", "alice");
  store.addSnapshot("snapB", "bob");
  store.addSnapshot("snapLow", "alice", { level: 3 });
  configure?.(store);
  const engine = new DevEngine();
  const hub = new Hub({ engine, store, costMode, log: silentLogger, matchmakingEveryTicks: 1 });
  const server = new RealtimeServer({
    config: { port: 0, tickMs: TICK_MS, maxConnections: 50, helloTimeoutMs: 1000, idleTimeoutMs: 60_000, maxConnectionMs: 60_000, shutdownGraceMs: 2000, engine: "dev" },
    hub,
    verifier: new InsecureDevVerifier(),
    log: silentLogger,
  });
  const port = await server.listen(0, "127.0.0.1");
  env = { server, hub, store, url: `ws://127.0.0.1:${port}/v2`, clients: [] };
  return env;
}

async function client(e: Env, uid?: string): Promise<TestClient> {
  const c = await TestClient.open(e.url);
  e.clients.push(c);
  if (uid) {
    c.hello(uid);
    await c.waitFor("welcome");
  }
  return c;
}

afterEach(async () => {
  if (!env) return;
  for (const c of env.clients) c.close();
  await env.server.close();
  env = null;
});

/** Re-runs the battle from the stored replay (seed + inputs) and compares the final state. */
async function replayHash(e: Env, matchId: string): Promise<{ replayed: string; stored: string }> {
  const rep = e.store.replays.get(matchId);
  if (!rep) throw new Error("no replay");
  const engine = new DevEngine();
  const src = async (id: string) => {
    const s = await e.store.loadSnapshot(id);
    if (!s) throw new Error(id);
    return engine.ratedFighter(s, 50);
  };
  const sim = engine.createBattle(await src(rep.sides[0].snapshotId), await src(rep.sides[1].snapshotId), { seed: rep.seed });
  let i = 0;
  while (sim.tick < rep.ticks && !sim.finished) {
    const inputs: [number | null, number | null] = [null, null];
    for (; rep.inputs[i]?.tick === sim.tick + 1; i++) {
      const x = rep.inputs[i];
      if (x) inputs[x.side] = x.slot;
    }
    sim.step(inputs);
  }
  return { replayed: sim.stateHash(), stored: rep.finalHash };
}

describe("realtime server (integration)", () => {
  it("serves /healthz", async () => {
    const e = await start();
    const res = await fetch(e.url.replace("ws://", "http://").replace("/v2", "/healthz"));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, draining: false, engine: "dev" });
  });

  it("two children play a full rated PvP match", async () => {
    const e = await start();
    const alice = await client(e, "alice");
    const bob = await client(e, "bob");
    alice.autoplay(0);
    bob.autoplay(1);
    alice.send({ t: "queue", snapshotId: "snapA" });
    bob.send({ t: "queue", snapshotId: "snapB" });
    await alice.waitFor("queued");

    const mA = await alice.waitFor("match");
    const mB = await bob.waitFor("match");
    expect(mA.matchId).toBe(mB.matchId);
    expect([mA.you, mB.you].sort()).toEqual(["a", "b"]);
    expect(mA.a.level).toBe(50);
    expect(mA.a.isGhost).toBe(false);
    expect(JSON.stringify(mA)).not.toContain("rating");

    const endA = await alice.waitFor("end", undefined, 20_000);
    const endB = await bob.waitFor("end", undefined, 20_000);
    expect(endA.reason).toBe("ko");
    expect([endA.you.outcome, endB.you.outcome].sort()).toEqual(["lose", "win"]);
    expect(endA.you.xp).toBeGreaterThan(0);

    // Persisted: ratings moved ±24 (provisional K 48, equal ratings), match + replay stored.
    const ra = e.store.users.get("alice")?.rated?.rating ?? 0;
    const rb = e.store.users.get("bob")?.rated?.rating ?? 0;
    expect([ra, rb].sort((x, y) => x - y)).toEqual([976, 1024]);
    expect(e.store.rtMatches.get(mA.matchId)).toMatchObject({ mode: "pvp", reason: "ko" });
    expect(e.store.snapshots.get("snapA")?.ghostRating).toBe(ra);

    // Events arrive in order with consecutive seq numbers.
    const seqs = alice.messages.flatMap((m) => (m.t === "ev" ? [m.seq] : []));
    expect(seqs).toEqual(seqs.map((_, i) => i + 1));
    // Selections were acknowledged privately.
    expect(alice.messages.some((m) => m.t === "sel" && m.accepted)).toBe(true);

    const { replayed, stored } = await replayHash(e, mA.matchId);
    expect(replayed).toBe(stored);
  });

  it("falls back to a ghost when nobody else is queuing (cost mode decides how soon)", async () => {
    const quick: CostModeSource = { current: (): CostMode => ({ mode: "saving", flags: { ...COST_MODES.saving, ghostAfterSec: 0.05 } }) };
    const e = await start(quick, (s) => {
      s.snapshots.delete("snapB");
      s.addSnapshot("ghost1", "carol", { ghostRating: 1010 });
    });
    const alice = await client(e, "alice");
    alice.autoplay(0);
    alice.send({ t: "queue", snapshotId: "snapA" });
    const m = await alice.waitFor("match");
    const foe = m.you === "a" ? m.b : m.a;
    expect(foe).toMatchObject({ isGhost: true, displayName: "carol-name", characterName: "ghost1-chara" });
    const end = await alice.waitFor("end", undefined, 20_000);
    expect(["win", "lose"]).toContain(end.you.outcome);
    // Ghost matches use half K: ±12 at equal-ish ratings, and the ghost owner is untouched.
    expect(Math.abs((e.store.users.get("alice")?.rated?.rating ?? 0) - 1000)).toBeLessThanOrEqual(13);
    expect(e.store.users.has("carol")).toBe(false);
  });

  it("uses a mirror ghost when no other character exists", async () => {
    const quick: CostModeSource = { current: (): CostMode => ({ mode: "minimal", flags: { ...COST_MODES.minimal, ghostAfterSec: 0 } }) };
    const e = await start(quick, (s) => {
      s.snapshots.delete("snapB");
    });
    const alice = await client(e, "alice");
    alice.autoplay(0);
    alice.send({ t: "queue", snapshotId: "snapA" });
    const m = await alice.waitFor("match");
    const foe = m.you === "a" ? m.b : m.a;
    expect(foe).toMatchObject({ isGhost: true, displayName: "かがみ" });
    await alice.waitFor("end", undefined, 20_000);
  });

  it("a child who drops out can reconnect and continue the same match", async () => {
    const e = await start();
    const alice = await client(e, "alice");
    const bob = await client(e, "bob");
    bob.autoplay(0);
    alice.send({ t: "queue", snapshotId: "snapA" });
    bob.send({ t: "queue", snapshotId: "snapB" });
    const m = await alice.waitFor("match");
    await alice.waitFor("ev");
    const lastSeq = alice.messages.flatMap((x) => (x.t === "ev" ? [x.seq] : [])).at(-1) ?? 0;
    alice.close();
    await alice.waitClose();

    const again = await client(e);
    again.autoplay(0);
    again.hello("alice", { lastSeq });
    const w = await again.waitFor("welcome");
    expect(w.inMatch).toBe(true);
    const m2 = await again.waitFor("match");
    expect(m2).toMatchObject({ matchId: m.matchId, resumed: true });
    const firstEv = await again.waitFor("ev");
    expect(firstEv.seq).toBeGreaterThan(lastSeq);
    // autoplay only reacts to new `match`/`act` events; nudge it once
    again.send({ t: "select", seq: 1000, slot: 0 });
    const end = await again.waitFor("end", undefined, 20_000);
    expect(end.matchId).toBe(m.matchId);
  });

  it("a second connection for the same uid replaces the first", async () => {
    const e = await start();
    const first = await client(e, "alice");
    const second = await client(e, "alice");
    await first.waitFor("bye");
    expect((await first.waitClose()).code).toBe(4409);
    second.send({ t: "ping" });
    await second.waitFor("pong");
  });

  it("rejects bad tokens, missing consent, foreign or low-level characters", async () => {
    const e = await start();
    const bad = await client(e);
    bad.send({ t: "hello", proto: 1, idToken: "not-a-dev-token" });
    expect(await bad.waitFor("error")).toMatchObject({ code: "UNAUTHENTICATED" });
    expect((await bad.waitClose()).code).toBe(4401);

    const noConsent = await client(e);
    noConsent.hello("kid3");
    expect(await noConsent.waitFor("error")).toMatchObject({ code: "CONSENT_REQUIRED" });
    expect((await noConsent.waitClose()).code).toBe(4403);

    const alice = await client(e, "alice");
    alice.send({ t: "queue", snapshotId: "snapB" });
    expect(await alice.waitFor("error")).toMatchObject({ code: "NOT_OWNER" });
    alice.send({ t: "queue", snapshotId: "snapLow" });
    expect(await alice.waitFor("error", (m) => m.code === "LEVEL_TOO_LOW")).toBeDefined();
    alice.send({ t: "select", seq: 1, slot: 0 });
    expect(await alice.waitFor("error", (m) => m.code === "NOT_IN_MATCH")).toBeDefined();
  });

  it("rejects oversized and malformed messages", async () => {
    const e = await start();
    const old = await client(e);
    old.send({ t: "hello", proto: 99, idToken: "dev:alice" });
    expect(await old.waitFor("error")).toMatchObject({ code: "PROTOCOL_VERSION" });

    const alice = await client(e, "alice");
    alice.send({ t: "queue", snapshotId: "x".repeat(600) });
    expect(await alice.waitFor("error")).toMatchObject({ code: "BAD_MESSAGE" });
    expect((await alice.waitClose()).code).toBe(4400);
  });

  it("closes connections that never say hello", async () => {
    const e = await start();
    const silent = await client(e);
    expect((await silent.waitClose(3000)).code).toBe(4408);
  });

  it("SIGTERM drain: running matches end without a result, clients are told to reconnect", async () => {
    const e = await start();
    const alice = await client(e, "alice");
    const bob = await client(e, "bob");
    alice.send({ t: "queue", snapshotId: "snapA" });
    bob.send({ t: "queue", snapshotId: "snapB" });
    await alice.waitFor("match");
    await e.server.close();
    env = null;
    const end = await alice.waitFor("end");
    expect(end).toMatchObject({ reason: "aborted", winner: null, you: { outcome: "none", xp: 0 } });
    expect(await alice.waitFor("bye")).toMatchObject({ reason: "shutdown", reconnect: true });
    expect(e.store.users.get("alice")?.rated?.rating).toBe(1000);
  });

  it("still shows a result when Firestore is down (nothing saved)", async () => {
    const e = await start(undefined, (s) => {
      s.failSettle = true;
    });
    const alice = await client(e, "alice");
    const bob = await client(e, "bob");
    alice.autoplay(0);
    bob.autoplay(0);
    alice.send({ t: "queue", snapshotId: "snapA" });
    bob.send({ t: "queue", snapshotId: "snapB" });
    const end = await alice.waitFor("end", undefined, 20_000);
    expect(["win", "lose"]).toContain(end.you.outcome);
    expect(e.store.users.get("alice")?.rated?.rating).toBe(1000);
  });
});
