import { describe, expect, it } from "vitest";
import { Match, type MatchSide } from "../../src/match";
import type { FighterInfo, ServerMsg } from "../../src/protocol";
import { FakeSim, fakeSetup } from "../helpers/fakeSim";

const info = (isGhost = false): FighterInfo => ({
  snapshotId: isGhost ? "g" : "s",
  displayName: "x",
  characterName: "c",
  imagePath: null,
  attr: "gu",
  moves: fakeSetup().moves,
  maxHp: 100,
  maxBars: 3,
  level: 50,
  badge: "egg",
  isGhost,
});
const player = (uid: string): MatchSide => ({ kind: "player", uid, snapshotId: `s-${uid}`, level: 10, rating: 1000, info: info() });
const ghost = (): MatchSide => ({ kind: "ghost", uid: null, snapshotId: "g", level: 30, rating: 1000, info: info(true), aiTier: "normal" });

function setup(sim: FakeSim, b: MatchSide = player("bob")) {
  const m = new Match("m1", b.kind === "ghost" ? "ghost" : "pvp", sim, { engineId: "fake", tickHz: 10 }, [player("alice"), b], 42, 0);
  const inbox: [ServerMsg[], ServerMsg[]] = [[], []];
  m.attach(0, (x) => inbox[0].push(x));
  if (b.kind === "player") m.attach(1, (x) => inbox[1].push(x));
  return { m, inbox };
}

function runUntil(m: Match, pred: () => boolean, max = 5000): void {
  for (let i = 0; i < max && !pred(); i++) m.advance();
}

describe("Match timing (server-side, stackable bars)", () => {
  it("sends match + snap on attach, never reveals the other side's selection", () => {
    const sim = new FakeSim([10, 10]);
    const { m, inbox } = setup(sim);
    expect(inbox[0][0]).toMatchObject({ t: "match", you: "a", resumed: false, tickHz: 10 });
    expect(inbox[0][0]).not.toHaveProperty("decisionTicks");
    expect(inbox[1][0]).toMatchObject({ t: "match", you: "b" });
    const ack = m.select(0, 1, 2);
    expect(ack).toEqual({ t: "sel", seq: 1, slot: 2, accepted: true, queued: true });
    expect(inbox[1].some((x) => x.t === "sel")).toBe(false);
  });

  it("さきどり: a queued move fires in the tick its bars are there", () => {
    const sim = new FakeSim([10, 10_000]);
    const { m } = setup(sim);
    m.select(0, 1, 2); // costs 3 bars: bar 1 at tick 10, 2 at 20, 3 at 30
    runUntil(m, () => sim.inputsSeen.length > 0);
    expect(sim.inputsSeen[0]).toEqual({ tick: 30, side: 0, slot: 2 });
    expect(m.summary(0).inputs[0]).toEqual({ tick: 30, side: 0, slot: 2, src: "player" });
  });

  it("a newer select replaces the queued one", () => {
    const sim = new FakeSim([10, 10_000]);
    const { m } = setup(sim);
    m.select(0, 1, 2);
    m.select(0, 2, 0);
    runUntil(m, () => sim.inputsSeen.length > 0);
    expect(sim.inputsSeen[0]).toEqual({ tick: 10, side: 0, slot: 0 });
  });

  it("no decision timer: an idle child caps at max bars and nobody picks for it", () => {
    const sim = new FakeSim([10, 10_000]);
    const { m, inbox } = setup(sim);
    runUntil(m, () => sim.tick >= 300);
    expect(sim.inputsSeen).toEqual([]);
    expect(sim.bars[0]).toBe(sim.maxBars);
    expect(sim.aiCalls + sim.omakaseCalls).toBe(0);
    const types = new Set(inbox[0].flatMap((x) => (x.t === "ev" ? x.events.map((e) => e.type) : [])));
    expect(types.has("deadline")).toBe(false);
    expect(types.has("autoPick")).toBe(false);
    expect(types.has("bar")).toBe(true);
    const snap = inbox[0].filter((x) => x.t === "snap").at(-1);
    expect(snap).toMatchObject({ a: { bars: 3, maxBars: 3, gauge: 30_000 } });
  });

  it("a move costing more than max bars is refused at once", () => {
    const sim = new FakeSim([10, 10_000], 10, 100, 1800, 2);
    const { m } = setup(sim);
    expect(m.select(0, 1, 2)).toEqual({ t: "sel", seq: 1, slot: 2, accepted: false, queued: false, reason: "unusable" });
    expect(m.select(0, 2, 1)).toMatchObject({ accepted: true, queued: true });
  });

  it("a queued move waits while it cannot be used (e.g. cooldown), then fires", () => {
    const sim = new FakeSim([10, 10_000]);
    sim.unusable.add("0:2");
    const { m } = setup(sim);
    m.select(0, 1, 2);
    runUntil(m, () => sim.tick >= 50);
    expect(sim.inputsSeen).toEqual([]);
    sim.unusable.clear();
    m.advance();
    expect(sim.inputsSeen[0]).toEqual({ tick: 51, side: 0, slot: 2 });
  });

  it("おまかせ switch: random move, wait for its bars, use it; off = manual control again", () => {
    const sim = new FakeSim([10, 10_000]);
    sim.omakaseChoice = 1; // costs 2 bars
    const { m, inbox } = setup(sim);
    m.select(0, 1, 2); // さきどり, dropped when おまかせ goes on
    expect(m.setOmakase(0, true)).toEqual({ t: "omakase", on: true });
    runUntil(m, () => sim.inputsSeen.length > 0);
    // Bar 2 fills in tick 20; the server passes the plan from the next tick.
    expect(sim.inputsSeen[0]).toEqual({ tick: 21, side: 0, slot: 1 });
    expect(m.summary(0).inputs[0]?.src).toBe("omakase");
    expect(inbox[1].some((x) => x.t === "omakase")).toBe(false);

    expect(m.setOmakase(0, false)).toEqual({ t: "omakase", on: false });
    const calls = sim.omakaseCalls;
    runUntil(m, () => sim.tick >= 45);
    expect(sim.inputsSeen).toHaveLength(1); // bars fill, nobody picks for the child
    m.select(0, 2, 0);
    runUntil(m, () => sim.inputsSeen.length > 1);
    expect(sim.inputsSeen[1]).toEqual({ tick: 46, side: 0, slot: 0 });
    expect(sim.omakaseCalls).toBe(calls);
  });

  it("the AI plan is dropped whenever control of a side changes", () => {
    const sim = new FakeSim([10, 10_000]);
    const { m } = setup(sim);
    m.advance(); // player control from the first tick
    const c0 = sim.cleared;
    m.setOmakase(0, true);
    m.advance();
    m.setOmakase(0, false);
    m.advance();
    expect(sim.cleared - c0).toBe(2);
  });

  it("rejects stale or out-of-range selections", () => {
    const sim = new FakeSim();
    const { m } = setup(sim);
    expect(m.select(0, 5, 0).t).toBe("sel");
    expect(m.select(0, 5, 1)).toMatchObject({ accepted: false, reason: "stale" });
    expect(m.select(0, 6, 3)).toMatchObject({ accepted: false, reason: "unusable" });
  });

  it("ghosts are played by the tiered AI (1 s thinking time)", () => {
    const sim = new FakeSim([10_000, 10]);
    sim.aiChoice = 0;
    const { m } = setup(sim, ghost());
    runUntil(m, () => sim.inputsSeen.length > 0);
    // First bar in tick 10, then 10 ticks of thinking.
    expect(sim.inputsSeen[0]).toEqual({ tick: 20, side: 1, slot: 0 });
    expect(m.summary(0).inputs[0]?.src).toBe("ai");
  });

  it("disconnect: the AI plays after 10 s, control back on reconnect, loss after 30 s away", () => {
    const sim = new FakeSim([10, 10_000], 1);
    sim.aiChoice = 0;
    const { m } = setup(sim);
    m.detach(0);
    runUntil(m, () => sim.inputsSeen.length > 0, 2000);
    // Nothing is picked for 10 s (no timer); from tick 101 the AI plays (bars are capped).
    expect(m.summary(0).inputs.map((x) => [x.tick, x.src])).toEqual([[101, "ai"]]);

    const inbox: ServerMsg[] = [];
    m.attach(0, (x) => inbox.push(x), 0);
    expect(inbox[0]).toMatchObject({ t: "match", resumed: true });
    expect(inbox.filter((x) => x.t === "ev").length).toBeGreaterThan(0);
    const before = sim.inputsSeen.length;
    m.select(0, 1, 2);
    runUntil(m, () => sim.inputsSeen.length > before);
    expect(sim.inputsSeen.at(-1)).toMatchObject({ side: 0, slot: 2 });
    expect(m.summary(0).inputs.at(-1)?.src).toBe("player");

    m.detach(0);
    const t0 = sim.tick;
    runUntil(m, () => m.done);
    expect(sim.tick - t0).toBe(300);
    const s = m.summary(1);
    expect(s).toMatchObject({ reason: "forfeit", forfeitSide: 0, winner: 1 });
  });

  it("both players away for 30 s: aborted, no winner", () => {
    const sim = new FakeSim([10_000, 10_000]);
    const { m } = setup(sim);
    m.detach(0);
    m.detach(1);
    runUntil(m, () => m.done);
    expect(m.summary(0)).toMatchObject({ reason: "aborted", winner: null });
  });

  it("KO ends the match; summary carries the input log for replay", () => {
    const sim = new FakeSim([5, 7], 50);
    const { m, inbox } = setup(sim);
    for (let i = 0; i < 5000 && !m.done; i++) {
      m.select(0, i + 1, 0); // the child keeps tapping slot 0
      m.advance();
    }
    const s = m.summary(123);
    expect(s.reason).toBe("ko");
    expect(s.winner).toBe(sim.winner);
    expect(s.inputs.length).toBe(sim.inputsSeen.length);
    expect(s.finalHash).toBe(sim.stateHash());
    expect(inbox[0].at(-1)).toMatchObject({ t: "snap" });
    const seqs = inbox[0].flatMap((x) => (x.t === "ev" ? [x.seq] : []));
    expect(seqs).toEqual(seqs.map((_, i) => i + 1));
  });

  it("snapshots go out every 5 ticks (2 Hz)", () => {
    const sim = new FakeSim([10_000, 10_000]);
    const { m, inbox } = setup(sim);
    inbox[0].length = 0;
    for (let i = 0; i < 20; i++) m.advance();
    expect(inbox[0].flatMap((x) => (x.t === "snap" ? [x.tick] : []))).toEqual([5, 10, 15, 20]);
  });

  it("abort() ends without a winner", () => {
    const sim = new FakeSim();
    const { m } = setup(sim);
    m.advance();
    m.abort();
    expect(m.done).toBe(true);
    expect(m.summary(0)).toMatchObject({ reason: "aborted", winner: null });
  });
});
