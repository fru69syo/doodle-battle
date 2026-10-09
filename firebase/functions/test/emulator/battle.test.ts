import { describe, expect, it } from "vitest";
import { pollMatchHandler, submitActionHandler } from "../../src/callables/battle";
import { joinQueueHandler } from "../../src/callables/matchmaking";
import { LIMITS } from "../../src/config";
import { COL, db } from "../../src/lib/firebase";
import type { PendingActions, TurnDoc } from "../../src/model";
import { errorCode, req, useEmulatorEnv } from "../helpers/emulator";
import { getMatch, pvpMatch, registeredPlayer } from "../helpers/fixtures";

const env = useEmulatorEnv();
const submit = (uid: string, matchId: string, turn: number, action: string) =>
  submitActionHandler(req(uid, { matchId, turn, action }));
const poll = (uid: string, matchId: string) => pollMatchHandler(req(uid, { matchId }));

describe("submitAction", () => {
  it("hides the first action and resolves the turn when both are in", async () => {
    const { matchId } = await pvpMatch();
    expect(await submit("alice", matchId, 1, "element")).toEqual({ resolved: false, status: "active", turn: 1 });
    const m1 = await getMatch(matchId);
    expect(m1.submitted).toEqual({ a: true, b: false });
    expect(JSON.stringify(m1)).not.toContain(`"a":"element"`);
    expect(m1).not.toHaveProperty("actions");
    // Idempotent retry.
    expect(await submit("alice", matchId, 1, "element")).toMatchObject({ resolved: false });

    expect(await submit("bob", matchId, 1, "tackle")).toEqual({ resolved: true, status: "active", turn: 2 });
    const m2 = await getMatch(matchId);
    expect(m2.turn).toBe(2);
    expect(m2.submitted).toEqual({ a: false, b: false });
    expect(m2.view.turn).toBe(1);
    const t1 = (await db().collection(COL.matches).doc(matchId).collection(COL.turns).doc("1").get()).data() as TurnDoc;
    expect(t1.actions).toEqual({ a: "element", b: "tackle" });
    expect(t1.events.length).toBeGreaterThan(0);
    const pending = (
      await db().collection(COL.matches).doc(matchId).collection(COL.matchPrivate).doc("actions").get()
    ).data() as PendingActions;
    expect(pending).toEqual({ turn: 2, a: null, b: null });
  });

  it("rejects wrong turns, illegal actions and outsiders", async () => {
    const { matchId } = await pvpMatch();
    expect(await errorCode(submit("alice", matchId, 2, "tackle"))).toBe("WRONG_TURN");
    expect(await errorCode(submit("alice", matchId, 1, "special"))).toBe("ILLEGAL_ACTION");
    expect(await errorCode(submit("alice", matchId, 1, "dance"))).toBe("INVALID_ARGUMENT");
    await registeredPlayer("eve");
    expect(await errorCode(submit("eve", matchId, 1, "tackle"))).toBe("NOT_IN_MATCH");
    expect(await errorCode(submit("alice", "nope", 1, "tackle"))).toBe("NOT_FOUND");
  });

  it("plays to the end and updates rating / xp / stats server-side", async () => {
    const { matchId } = await pvpMatch();
    for (let turn = 1; turn <= LIMITS.maxTurns; turn++) {
      await submit("alice", matchId, turn, "element");
      const r = await submit("bob", matchId, turn, "tackle");
      if (r.status !== "active") break;
    }
    const m = await getMatch(matchId);
    expect(m.status).toBe("finished");
    expect(["ko", "turn_limit"]).toContain(m.endReason);
    expect(m.result).not.toBeNull();
    const users = await Promise.all(["alice", "bob"].map(async (u) => (await db().collection(COL.users).doc(u).get()).data()!));
    expect(users[0]!.activeMatchId).toBeNull();
    expect(users[1]!.activeMatchId).toBeNull();
    expect(Number(users[0]!.rating) + Number(users[1]!.rating)).toBe(2000);
    if (m.winner === "a") {
      expect(m.result!.a).toEqual({ xp: 100, ratingDelta: 16, outcome: "win" });
      expect(users[0]!.onlineStats.wins).toBe(1);
      expect(users[1]!.onlineStats.losses).toBe(1);
    }
    expect(await errorCode(submit("alice", matchId, m.turn, "tackle"))).toBe("MATCH_NOT_ACTIVE");
  });

  it("ghost matches resolve immediately with a server-chosen action", async () => {
    await registeredPlayer("ghostowner");
    const sa = await registeredPlayer("alice");
    await joinQueueHandler(req("alice", { characterId: sa }));
    env.advance(LIMITS.ghostAfterMs);
    const r = await joinQueueHandler(req("alice", { characterId: sa }));
    if (r.status !== "matched") throw new Error("expected ghost match");
    expect(await submit("alice", r.matchId, 1, "tackle")).toEqual({ resolved: true, status: "active", turn: 2 });
  });
});

describe("turn deadline", () => {
  it("pollMatch resolves an expired turn with たいあたり for the absent player", async () => {
    const { matchId } = await pvpMatch();
    await submit("alice", matchId, 1, "element");
    env.advance(LIMITS.turnMs);
    expect(await poll("alice", matchId)).toMatchObject({ status: "active", turn: 1 }); // within grace
    env.advance(LIMITS.turnGraceMs);
    expect(await poll("alice", matchId)).toMatchObject({ status: "active", turn: 2 });
    const t1 = (await db().collection(COL.matches).doc(matchId).collection(COL.turns).doc("1").get()).data() as TurnDoc;
    expect(t1.actions).toEqual({ a: "element", b: "tackle" });
    expect(t1.timedOut).toEqual({ a: false, b: true });
    expect((await getMatch(matchId)).timeouts).toEqual({ a: 0, b: 1 });
    expect(await errorCode(poll("eve", matchId))).toBe("NOT_IN_MATCH");
  });

  it("a player who misses 3 turns in a row forfeits", async () => {
    const { matchId } = await pvpMatch();
    for (let turn = 1; turn <= 3; turn++) {
      await submit("alice", matchId, turn, "guard");
      env.advance(LIMITS.turnMs + LIMITS.turnGraceMs);
      await poll("alice", matchId);
    }
    const m = await getMatch(matchId);
    expect(m).toMatchObject({ status: "finished", winner: "a", endReason: "forfeit_timeout" });
    expect(m.result!.b.outcome).toBe("lose");
  });

  it("a late submit lets the timeout resolve first, then reports WRONG_TURN", async () => {
    const { matchId } = await pvpMatch();
    await submit("alice", matchId, 1, "tackle");
    env.advance(LIMITS.turnMs + LIMITS.turnGraceMs);
    expect(await errorCode(submit("bob", matchId, 1, "element"))).toBe("WRONG_TURN");
    expect((await getMatch(matchId)).turn).toBe(2);
  });
});
