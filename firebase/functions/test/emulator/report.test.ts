import { describe, expect, it } from "vitest";
import { reportCharacterHandler, reportId } from "../../src/callables/reportCharacter";
import { LIMITS } from "../../src/config";
import { COL, db } from "../../src/lib/firebase";
import type { SnapshotDoc } from "../../src/model";
import { errorCode, req, seedUser, useEmulatorEnv } from "../helpers/emulator";
import { pvpMatch } from "../helpers/fixtures";

useEmulatorEnv();
const report = (uid: string, snapshotId: string, reasonCode = "bad_picture") =>
  reportCharacterHandler(req(uid, { snapshotId, reasonCode }));

/** Minimal match record so that `uid` has "seen" the snapshot. */
async function seenIn(uid: string, snapshotId: string) {
  await db().collection(COL.matches).add({ playerUids: [uid], snapshotIds: ["x", snapshotId], createdAtMs: 1, status: "finished" });
}

describe("reportCharacter", () => {
  it("records one report per reporter and only for opponents actually met", async () => {
    const { sa, sb } = await pvpMatch();
    expect(await report("alice", sb)).toEqual({ ok: true, alreadyReported: false });
    expect(await report("alice", sb, "bad_name")).toEqual({ ok: true, alreadyReported: true });
    expect(await errorCode(report("alice", sa))).toBe("CANNOT_REPORT_SELF");
    await seedUser("carol");
    expect(await errorCode(report("carol", sb))).toBe("NOT_SEEN_IN_MATCH");
    expect(await errorCode(report("alice", sb, "free text!"))).toBe("INVALID_ARGUMENT");
    expect(await errorCode(report("alice", "missing"))).toBe("NOT_FOUND");

    const r = (await db().collection(COL.reports).doc(reportId(sb, "alice")).get()).data();
    expect(r).toMatchObject({ snapshotId: sb, reporterUid: "alice", ownerUid: "bob", reasonCode: "bad_picture" });
    const q = (await db().collection(COL.moderationQueue).doc(sb).get()).data();
    expect(q).toMatchObject({ reportCount: 1, state: "pending", hidden: false, reasons: { bad_picture: 1 } });
  });

  it("realtime (v2) opponents can be reported once the match is settled; ghosts too", async () => {
    const { sa, sb } = await pvpMatch();
    await seedUser("dave");
    expect(await errorCode(report("dave", sb))).toBe("NOT_SEEN_IN_MATCH");
    // As written by server/realtime FirestoreStore.settleMatch (dave played bob's character as a ghost).
    await db().collection(COL.rtMatches).doc("rt1").set({
      mode: "ghost",
      playerUids: ["dave"],
      snapshotIds: ["dave_snap", sb],
      sides: { a: { snapshotId: "dave_snap", isGhost: false }, b: { snapshotId: sb, isGhost: true } },
      endedAtMs: 5,
    });
    expect(await report("dave", sb)).toEqual({ ok: true, alreadyReported: false });
    // Only the reporter's own matches count.
    expect(await errorCode(report("dave", sa))).toBe("NOT_SEEN_IN_MATCH");
  });

  it(`auto-hides after ${LIMITS.reportHideThreshold} distinct reporters`, async () => {
    const { sb } = await pvpMatch();
    for (const u of ["r1", "r2"]) {
      await seedUser(u);
      await seenIn(u, sb);
    }
    await report("alice", sb, "real_person");
    await report("r1", sb, "real_person");
    let s = (await db().collection(COL.snapshots).doc(sb).get()).data() as SnapshotDoc;
    expect(s.status).toBe("active");
    await report("r2", sb, "personal_info");
    s = (await db().collection(COL.snapshots).doc(sb).get()).data() as SnapshotDoc;
    expect(s).toMatchObject({ status: "hidden", reportCount: 3, reportReasons: { real_person: 2, personal_info: 1 } });
    const q = (await db().collection(COL.moderationQueue).doc(sb).get()).data();
    expect(q).toMatchObject({ hidden: true, reportCount: 3, state: "pending" });
  });
});
