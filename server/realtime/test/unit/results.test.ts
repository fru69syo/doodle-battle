import { describe, expect, it } from "vitest";
import { initialRated } from "../../src/rating";
import { settle, type MatchSummary } from "../../src/results";

function summary(over: Partial<MatchSummary> = {}): MatchSummary {
  return {
    matchId: "m",
    mode: "pvp",
    engineId: "fake",
    seed: 1,
    startedAtMs: 0,
    endedAtMs: 1000,
    ticks: 300,
    sides: [
      { uid: "a", snapshotId: "sa", level: 10, isGhost: false, ratingAtStart: 1000 },
      { uid: "b", snapshotId: "sb", level: 60, isGhost: false, ratingAtStart: 1000 },
    ],
    winner: 0,
    reason: "ko",
    forfeitSide: null,
    inputs: [],
    finalHash: "h",
    tailEvents: [],
    ...over,
  };
}

const both = () =>
  new Map([
    ["a", initialRated()],
    ["b", initialRated()],
  ]);

describe("settle", () => {
  it("PvP: winner +24, loser -24 (provisional K 48), XP by real level", () => {
    const r = settle(summary(), both());
    expect(r.players).toMatchObject([
      { uid: "a", outcome: "win", ratingDelta: 24, xp: Math.floor((150 * 136) / 100) },
      { uid: "b", outcome: "lose", ratingDelta: -24, xp: Math.floor((60 * 336) / 100) },
    ]);
  });

  it("ghost: half K, the ghost owner is not touched", () => {
    const s = summary({
      mode: "ghost",
      sides: [
        { uid: "a", snapshotId: "sa", level: 10, isGhost: false, ratingAtStart: 1000 },
        { uid: null, snapshotId: "g", level: 30, isGhost: true, ratingAtStart: 1000 },
      ],
      winner: 1,
    });
    const r = settle(s, new Map([["a", initialRated()]]));
    expect(r.players).toHaveLength(1);
    expect(r.players[0]).toMatchObject({ uid: "a", outcome: "lose", ratingDelta: -12 });
  });

  it("forfeit: the absent child loses rating and gets no XP", () => {
    const r = settle(summary({ reason: "forfeit", forfeitSide: 1, winner: 0 }), both());
    expect(r.players[1]).toMatchObject({ outcome: "lose", xp: 0, ratingDelta: -24 });
    expect(r.players[0]?.xp).toBeGreaterThan(0);
  });

  it("aborted: nothing changes", () => {
    const r = settle(summary({ reason: "aborted", winner: null }), both());
    expect(r.players.every((p) => p.outcome === "none" && p.next === null && p.xp === 0)).toBe(true);
  });
});
