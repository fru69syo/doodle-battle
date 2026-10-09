import { describe, expect, it } from "vitest";
import { joinQueueHandler } from "../../src/callables/matchmaking";
import { submitActionHandler } from "../../src/callables/battle";
import { LIMITS } from "../../src/config";
import { COL, db } from "../../src/lib/firebase";
import { sweep } from "../../src/scheduled/sweep";
import { req, useEmulatorEnv } from "../helpers/emulator";
import { getMatch, pvpMatch, registeredPlayer } from "../helpers/fixtures";

const env = useEmulatorEnv();

describe("sweep (every minute)", () => {
  it("drops stale queue entries and starts ghost matches for long waits", async () => {
    await registeredPlayer("ghostowner");
    const sa = await registeredPlayer("alice");
    const sb = await registeredPlayer("bob", { level: 20, xp: 0 });
    await joinQueueHandler(req("alice", { characterId: sa }));
    await joinQueueHandler(req("bob", { characterId: sb }));
    env.advance(LIMITS.queueStaleMs - 1000);
    await joinQueueHandler(req("alice", { characterId: sa })); // alice keeps heart-beating
    env.advance(LIMITS.ghostAfterMs - LIMITS.queueStaleMs + 1000);
    const stats = await sweep();
    expect(stats).toMatchObject({ staleQueueRemoved: 1, ghostMatches: 1 });
    expect((await db().collection(COL.queue).doc("bob").get()).exists).toBe(false);
    expect((await db().collection(COL.queue).doc("alice").get()).data()?.status).toBe("matched");
  });

  it("resolves expired turns when both players are gone, then aborts the match", async () => {
    const { matchId } = await pvpMatch();
    for (let i = 0; i < LIMITS.forfeitAfterTimeouts; i++) {
      env.advance(LIMITS.turnMs + LIMITS.turnGraceMs + 1);
      expect((await sweep()).turnsEnforced).toBe(1);
    }
    const m = await getMatch(matchId);
    expect(m).toMatchObject({ status: "aborted", endReason: "aborted", winner: null });
    expect(m.result).toEqual({
      a: { xp: 0, ratingDelta: 0, outcome: "none" },
      b: { xp: 0, ratingDelta: 0, outcome: "none" },
    });
    expect((await db().collection(COL.users).doc("alice").get()).data()?.activeMatchId).toBeNull();
  });

  it("does nothing for turns still within the deadline", async () => {
    const { matchId } = await pvpMatch();
    await submitActionHandler(req("alice", { matchId, turn: 1, action: "tackle" }));
    expect((await sweep()).turnsEnforced).toBe(0);
  });
});
