import { describe, expect, it } from "vitest";
import { DEFAULT_TIMING, Match, type MatchSide } from "../../src/match";
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

describe("Match timers (server-side)", () => {
  it("sends match + snap on attach, never reveals the other side's selection", () => {
    const sim = new FakeSim([10, 10]);
    const { m, inbox } = setup(sim);
    expect(inbox[0][0]).toMatchObject({ t: "match", you: "a", resumed: false, tickHz: 10, decisionTicks: 50 });
    expect(inbox[1][0]).toMatchObject({ t: "match", you: "b" });
    const ack = m.select(0, 1, 2);
    expect(ack).toEqual({ t: "sel", seq: 1, slot: 2, accepted: true, queued: true });
    expect(inbox[1].some((x) => x.t === "sel")).toBe(false);
  });

  it("さきどり: a move chosen while the gauge fills is used in the tick the gauge is full", () => {
    const sim = new FakeSim([10, 30]);
    const { m } = setup(sim);
    m.select(0, 1, 2);
    runUntil(m, () => sim.inputsSeen.length > 0);
    expect(sim.inputsSeen[0]).toEqual({ tick: 10, side: 0, slot: 2 });
    expect(m.summary(0).inputs[0]).toEqual({ tick: 10, side: 0, slot: 2, src: "player" });
  });

  it("5 s timer: おまかせ picks 50 ticks (+3 grace) after the gauge filled", () => {
    const sim = new FakeSim([10, 10_000]);
    sim.aiChoice = 1;
    const { m, inbox } = setup(sim);
    runUntil(m, () => sim.inputsSeen.length > 0);
    // ready at tick 10 (counted as the 1st waiting tick) -> auto at tick 10 + 50 + 3 - 1
    expect(sim.inputsSeen[0]).toEqual({ tick: 62, side: 0, slot: 1 });
    expect(m.summary(0).inputs[0]?.src).toBe("auto");
    const ev = inbox[0].find((x) => x.t === "ev" && x.events.some((e) => e.type === "autoPick"));
    expect(ev).toBeDefined();
    expect(DEFAULT_TIMING.decisionTicks + DEFAULT_TIMING.graceTicks).toBe(53);
  });

  it("deadline: the ready tick carries the exact tick of the timeout pick (children only)", () => {
    const sim = new FakeSim([10, 10_000]);
    sim.aiChoice = 1;
    const { m, inbox } = setup(sim);
    runUntil(m, () => sim.inputsSeen.length > 0);
    const deadlines = inbox[0].flatMap((x) => (x.t === "ev" ? x.events.filter((e) => e.type === "deadline") : []));
    expect(deadlines).toEqual([{ tick: 10, type: "deadline", side: 0, at: 62 }]);
    // The pick happens exactly at `at`; the opponent's app gets the same stream.
    expect(sim.inputsSeen[0]?.tick).toBe(62);
    expect(inbox[1].some((x) => x.t === "ev" && x.events.some((e) => e.type === "deadline"))).toBe(true);
    expect(m.deadlineOf(10)).toBe(62);
  });

  it("no deadline when さきどり fires in the very tick the gauge fills, none for ghosts", () => {
    const sim = new FakeSim([10, 10]);
    const { m, inbox } = setup(sim, ghost());
    m.select(0, 1, 0);
    runUntil(m, () => sim.tick >= 11);
    const deadlines = inbox[0].flatMap((x) => (x.t === "ev" ? x.events.filter((e) => e.type === "deadline") : []));
    expect(deadlines).toEqual([]);
  });

  it("おまかせ switch: the server's AI picks 1 s after ready; off = manual control again", () => {
    const sim = new FakeSim([10, 10_000]);
    sim.aiChoice = 1;
    const { m, inbox } = setup(sim);
    m.select(0, 1, 2); // さきどり, dropped when おまかせ goes on
    expect(m.setOmakase(0, true)).toEqual({ t: "omakase", on: true });
    runUntil(m, () => sim.inputsSeen.length > 0);
    expect(sim.inputsSeen[0]).toEqual({ tick: 20, side: 0, slot: 1 });
    expect(m.summary(0).inputs[0]?.src).toBe("omakase");
    // No autoPick event (that is only the 5 s timeout) and the ack is private.
    expect(inbox[0].some((x) => x.t === "ev" && x.events.some((e) => e.type === "autoPick"))).toBe(false);
    expect(inbox[1].some((x) => x.t === "omakase")).toBe(false);

    expect(m.setOmakase(0, false)).toEqual({ t: "omakase", on: false });
    const calls = sim.aiCalls;
    runUntil(m, () => sim.tick >= 45);
    expect(sim.inputsSeen).toHaveLength(1); // ready again at 30, waiting for the child
    m.select(0, 2, 0);
    runUntil(m, () => sim.inputsSeen.length > 1);
    expect(sim.inputsSeen[1]).toEqual({ tick: 46, side: 0, slot: 0 });
    expect(sim.aiCalls).toBe(calls);
  });

  it("おまかせ switched on while the gauge is already full: picks after the think time", () => {
    const sim = new FakeSim([10, 10_000]);
    const { m } = setup(sim);
    runUntil(m, () => sim.tick >= 30);
    m.setOmakase(0, true);
    m.advance();
    expect(sim.inputsSeen[0]).toMatchObject({ tick: 31, side: 0 });
  });

  it("an unusable queued move is rejected when the gauge fills, the child can pick again", () => {
    const sim = new FakeSim([10, 10_000]);
    sim.unusable.add("0:2");
    const { m, inbox } = setup(sim);
    m.select(0, 1, 2);
    runUntil(m, () => sim.tick >= 11);
    expect(inbox[0]).toContainEqual({ t: "sel", seq: 1, slot: 2, accepted: false, queued: false, reason: "unusable" });
    m.select(0, 2, 0);
    runUntil(m, () => sim.inputsSeen.length > 0);
    expect(sim.inputsSeen[0]).toMatchObject({ side: 0, slot: 0 });
  });

  it("rejects stale or out-of-range selections", () => {
    const sim = new FakeSim();
    const { m } = setup(sim);
    expect(m.select(0, 5, 0).t).toBe("sel");
    expect(m.select(0, 5, 1)).toMatchObject({ accepted: false, reason: "stale" });
    expect(m.select(0, 6, 3)).toMatchObject({ accepted: false, reason: "unusable" });
  });

  it("ghosts are played by the AI after thinking 10 ticks", () => {
    const sim = new FakeSim([10_000, 10]);
    const { m } = setup(sim, ghost());
    runUntil(m, () => sim.inputsSeen.length > 0);
    expect(sim.inputsSeen[0]).toEqual({ tick: 20, side: 1, slot: sim.aiChoice });
    expect(m.summary(0).inputs[0]?.src).toBe("ai");
  });

  it("disconnect: おまかせ after 10 s, control back on reconnect, loss after 30 s away", () => {
    const sim = new FakeSim([10, 10_000], 1);
    const { m } = setup(sim);
    m.detach(0);
    runUntil(m, () => sim.inputsSeen.length > 1, 2000);
    // The normal 5 s timer still runs while away (auto at tick 62); from tick 100 (10 s away)
    // the AI plays every turn without waiting for the timer (first AI tick: 101).
    expect(m.summary(0).inputs.map((x) => [x.tick, x.src])).toEqual([
      [62, "auto"],
      [101, "ai"],
    ]);

    const inbox: ServerMsg[] = [];
    m.attach(0, (x) => inbox.push(x), 0);
    expect(inbox[0]).toMatchObject({ t: "match", resumed: true });
    expect(inbox.filter((x) => x.t === "ev").length).toBeGreaterThan(0);
    const before = sim.aiCalls;
    m.select(0, 1, 2);
    runUntil(m, () => sim.inputsSeen.length > 2);
    expect(sim.inputsSeen[2]).toMatchObject({ side: 0, slot: 2 });
    expect(sim.aiCalls).toBe(before);

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
    for (let i = 0; i < 10; i++) m.select(0, i + 1, 0);
    runUntil(m, () => m.done);
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
