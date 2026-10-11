import { describe, expect, it } from "vitest";
import { deleteMyDataHandler } from "../../src/callables/deleteMyData";
import { reportCharacterHandler } from "../../src/callables/reportCharacter";
import { setDisplayNameHandler } from "../../src/callables/setDisplayName";
import { submitActionHandler } from "../../src/callables/battle";
import { auth, COL, db } from "../../src/lib/firebase";
import { handleConsentChange } from "../../src/triggers/consent";
import type { SnapshotDoc } from "../../src/model";
import { errorCode, req, seedUser, storageFiles, useEmulatorEnv } from "../helpers/emulator";
import { pvpMatch, registeredPlayer } from "../helpers/fixtures";
import { joinQueueHandler } from "../../src/callables/matchmaking";

useEmulatorEnv();

describe("setDisplayName", () => {
  it("only accepts preset word ids", async () => {
    await seedUser("kid");
    expect(await setDisplayNameHandler(req("kid", { adjectiveId: "a01", nounId: "n02" }))).toEqual({
      displayName: { adjectiveId: "a01", nounId: "n02", text: "あおい ネコ" },
    });
    const random = await setDisplayNameHandler(req("kid", {}));
    expect(random.displayName.text).toMatch(/^\S+ \S+$/);
    expect(await errorCode(setDisplayNameHandler(req("kid", { adjectiveId: "a01", nounId: "x" })))).toBe(
      "INVALID_ARGUMENT",
    );
    expect(await errorCode(setDisplayNameHandler(req("kid", { adjectiveId: "a01" })))).toBe("INVALID_ARGUMENT");
    expect(await errorCode(setDisplayNameHandler(req("kid", { text: "freetext" })))).toBe("INVALID_ARGUMENT");
    await seedUser("nokid", { online: false });
    expect(await errorCode(setDisplayNameHandler(req("nokid", {})))).toBe("CONSENT_REQUIRED");
  });
});

describe("consent withdrawal", () => {
  it("withdraws the child's snapshots and queue entry", async () => {
    const sa = await registeredPlayer("alice");
    await joinQueueHandler(req("alice", { characterId: sa }));
    const n = await handleConsentChange(
      "alice",
      { consent: { online: true } },
      { consent: { online: false } },
    );
    expect(n).toBe(1);
    const s = (await db().collection(COL.snapshots).doc(sa).get()).data() as SnapshotDoc;
    expect(s.status).toBe("withdrawn");
    expect((await db().collection(COL.queue).doc("alice").get()).exists).toBe(false);
    expect(await handleConsentChange("alice", { consent: { online: false } }, { consent: { online: false } })).toBe(0);
  });
});

describe("deleteMyData", () => {
  it("requires explicit confirmation", async () => {
    expect(await errorCode(deleteMyDataHandler(req("kid", {})))).toBe("CONFIRMATION_REQUIRED");
    expect(await errorCode(deleteMyDataHandler(req(null, { confirm: "DELETE" })))).toBe("UNAUTHENTICATED");
  });

  it("deletes Firestore data, Storage images and the auth user, leaving others intact", async () => {
    await auth().createUser({ uid: "alice" }).catch(() => undefined);
    const { matchId, sa, sb } = await pvpMatch("alice", "bob");
    await submitActionHandler(req("alice", { matchId, turn: 1, action: "tackle" }));
    await reportCharacterHandler(req("alice", { snapshotId: sb, reasonCode: "other" }));
    // bob reports alice too (report *about* alice must go as well)
    await reportCharacterHandler(req("bob", { snapshotId: sa, reasonCode: "bad_name" }));
    // a ghost match where alice's character appears
    await db().collection(COL.matches).add({ playerUids: ["zed"], snapshotIds: ["z", sa], createdAtMs: 1 });
    // v2 realtime: a match alice played, one where her character was a ghost, and their replays
    await db().collection(COL.rtMatches).doc("rt1").set({ playerUids: ["alice", "bob"], snapshotIds: [sa, sb] });
    await db().collection(COL.rtMatches).doc("rt2").set({ playerUids: ["zed"], snapshotIds: ["z", sa] });
    await db().collection(COL.replays).doc("rt1").set({ seed: 1 });
    await db().collection(COL.replays).doc("rt2").set({ seed: 2 });

    const res = await deleteMyDataHandler(req("alice", { confirm: "DELETE" }));
    expect(res).toEqual({ ok: true, deleted: { snapshots: 1, matches: 4, reports: 2 } });
    expect((await db().collection(COL.rtMatches).get()).size).toBe(0);
    expect((await db().collection(COL.replays).get()).size).toBe(0);

    expect((await db().collection(COL.users).doc("alice").get()).exists).toBe(false);
    expect((await db().collection(COL.snapshots).doc(sa).get()).exists).toBe(false);
    expect((await db().collection(COL.matches).get()).size).toBe(0);
    expect((await db().collection(COL.matches).doc(matchId).collection(COL.turns).get()).size).toBe(0);
    expect((await db().collection(COL.reports).get()).size).toBe(0);
    expect((await db().collection(COL.queue).doc("alice").get()).exists).toBe(false);
    expect((await db().collection(COL.rateLimits).doc("alice").get()).exists).toBe(false);
    expect((await db().collection(COL.moderationLog).where("uid", "==", "alice").get()).size).toBe(0);
    expect((await db().collection(COL.moderationQueue).doc(sa).get()).exists).toBe(false);
    expect(await storageFiles()).toEqual([`snapshotImages/${sb}/image.png`]);
    await expect(auth().getUser("alice")).rejects.toMatchObject({ code: "auth/user-not-found" });

    // bob is untouched
    expect((await db().collection(COL.snapshots).doc(sb).get()).exists).toBe(true);
    expect((await db().collection(COL.users).doc("bob").get()).exists).toBe(true);
  });
});
