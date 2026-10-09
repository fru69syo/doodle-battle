import { describe, expect, it } from "vitest";
import { joinQueueHandler, leaveQueueHandler } from "../../src/callables/matchmaking";
import { LIMITS } from "../../src/config";
import { COL, db } from "../../src/lib/firebase";
import type { QueueDoc } from "../../src/model";
import { errorCode, req, seedUser, useEmulatorEnv } from "../helpers/emulator";
import { getMatch, pvpMatch, registeredPlayer } from "../helpers/fixtures";

const env = useEmulatorEnv();
const join = (uid: string, characterId: string) => joinQueueHandler(req(uid, { characterId }));
const queueDoc = async (uid: string) => (await db().collection(COL.queue).doc(uid).get()).data() as QueueDoc | undefined;

describe("joinQueue / leaveQueue", () => {
  it("pairs two players within ±3 levels into a server-owned match", async () => {
    const { matchId, sa, sb } = await pvpMatch();
    const m = await getMatch(matchId);
    expect(m).toMatchObject({
      mode: "pvp",
      status: "active",
      turn: 1,
      playerUids: ["alice", "bob"],
      snapshotIds: [sa, sb],
      sides: { a: { uid: "alice", isGhost: false, characterName: "ねこまる" }, b: { uid: "bob" } },
    });
    expect(m.turnDeadlineMs).toBe(1_800_000_000_000 + LIMITS.turnMs);
    expect((await queueDoc("alice"))?.status).toBe("matched");
    expect((await queueDoc("bob"))?.matchId).toBe(matchId);
    const alice = (await db().collection(COL.users).doc("alice").get()).data();
    expect(alice?.activeMatchId).toBe(matchId);
    // Re-joining while the match is active returns the same match.
    expect(await join("alice", sa)).toEqual({ status: "matched", matchId });
  });

  it("does not pair players more than 3 levels apart, or stale entries", async () => {
    const s5 = await registeredPlayer("p5", { level: 5, xp: 0, seedAllocations: {} });
    const s9 = await registeredPlayer("p9", { level: 9, xp: 0, seedAllocations: {} });
    expect((await join("p5", s5)).status).toBe("waiting");
    expect((await join("p9", s9)).status).toBe("waiting");

    const s6 = await registeredPlayer("p6");
    env.advance(LIMITS.queueStaleMs); // p5 and p9 stopped heart-beating
    expect((await join("p6", s6)).status).toBe("waiting");
  });

  it("validates ownership and status of the character", async () => {
    const sa = await registeredPlayer("alice");
    await seedUser("eve");
    expect(await errorCode(join("eve", sa))).toBe("NOT_OWNER");
    expect(await errorCode(join("eve", "nope"))).toBe("NOT_FOUND");
    await db().collection(COL.snapshots).doc(sa).update({ status: "hidden" });
    expect(await errorCode(join("alice", sa))).toBe("SNAPSHOT_NOT_ACTIVE");
    await seedUser("nokid", { online: false });
    expect(await errorCode(join("nokid", sa))).toBe("CONSENT_REQUIRED");
  });

  it("falls back to a ghost after 60 s", async () => {
    const ghostSnap = await registeredPlayer("ghostowner", { level: 7, xp: 0 });
    const sa = await registeredPlayer("alice");
    expect(await join("alice", sa)).toEqual({ status: "waiting", waitedMs: 0 });
    env.advance(30_000);
    expect(await join("alice", sa)).toEqual({ status: "waiting", waitedMs: 30_000 });
    env.advance(30_000);
    const r = await join("alice", sa);
    expect(r.status).toBe("matched");
    if (r.status !== "matched") return;
    const m = await getMatch(r.matchId);
    expect(m.mode).toBe("ghost");
    expect(m.playerUids).toEqual(["alice"]);
    expect(m.sides.b).toMatchObject({ uid: null, isGhost: true, snapshotId: ghostSnap });
    expect(JSON.stringify(m.sides.b)).not.toContain("ghostowner");
  });

  it("keeps waiting when no ghost is available (only own snapshots)", async () => {
    const sa = await registeredPlayer("alice");
    await join("alice", sa);
    env.advance(LIMITS.ghostAfterMs + 1);
    expect((await join("alice", sa)).status).toBe("waiting");
  });

  it("leaveQueue removes a waiting entry and reports an active match", async () => {
    const sa = await registeredPlayer("alice");
    await join("alice", sa);
    expect(await leaveQueueHandler(req("alice", {}))).toEqual({ status: "left" });
    expect(await queueDoc("alice")).toBeUndefined();
    const { matchId } = await pvpMatch("carol", "dave");
    expect(await leaveQueueHandler(req("carol", {}))).toEqual({ status: "matched", matchId });
  });
});
