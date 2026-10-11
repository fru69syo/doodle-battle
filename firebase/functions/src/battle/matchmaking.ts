import type { DocumentSnapshot, Query } from "firebase-admin/firestore";
import { LIMITS } from "../config";
import type { UserProfile } from "../lib/auth";
import { clock } from "../lib/clock";
import { ErrorCode, fail } from "../lib/errors";
import { COL, db } from "../lib/firebase";
import { isV2Snapshot, type MatchDoc, type QueueDoc, type SideInfo, type SnapshotDoc } from "../model";
import { createMatchInTx } from "./matchService";
import { RATING } from "./results";

export type QueueResult =
  | { status: "matched"; matchId: string }
  | { status: "waiting"; waitedMs: number }
  | { status: "left" };

/** Levels within ±LIMITS.levelBand, clamped to [1, maxLevel] (≤ 7 values for `in`). */
export function levelBand(level: number): number[] {
  const out: number[] = [];
  for (let l = level - LIMITS.levelBand; l <= level + LIMITS.levelBand; l++) {
    if (l >= 1 && l <= LIMITS.maxLevel) out.push(l);
  }
  return out;
}

function sideInfo(
  snapshotId: string,
  snap: SnapshotDoc,
  uid: string | null,
  displayName: string,
  rating: number,
): SideInfo {
  return {
    uid,
    isGhost: uid === null,
    snapshotId,
    displayName,
    characterName: snap.name,
    element: snap.element,
    level: snap.level,
    isShobo: snap.isShobo,
    evolution: snap.evolution,
    stats: snap.stats,
    imagePath: snap.imagePath,
    moveNames: snap.moveNames,
    rating,
  };
}

async function activeMatchOf(profile: UserProfile | undefined): Promise<string | null> {
  const id = profile?.activeMatchId;
  if (!id) return null;
  const m = await db().collection(COL.matches).doc(id).get();
  return m.exists && (m.data() as MatchDoc).status === "active" ? id : null;
}

/** Loads a snapshot the caller owns and that is allowed online. */
export async function requireOwnActiveSnapshot(uid: string, snapshotId: string): Promise<SnapshotDoc> {
  const s = await db().collection(COL.snapshots).doc(snapshotId).get();
  if (!s.exists) fail(ErrorCode.NOT_FOUND, "character not registered");
  const snap = s.data() as SnapshotDoc;
  if (snap.ownerUid !== uid) fail(ErrorCode.NOT_OWNER, "not your character");
  if (snap.status !== "active") fail(ErrorCode.SNAPSHOT_NOT_ACTIVE, `character is ${snap.status}`);
  // v2 characters (engine v3) battle on the realtime server, not here.
  if (isV2Snapshot(snap)) fail(ErrorCode.SNAPSHOT_NOT_ACTIVE, "v2 character");
  return snap;
}

/**
 * Joins (or heart-beats) the matchmaking queue. Clients call this every ~10 s
 * while waiting; each call retries PvP pairing and, after 60 s, starts a
 * ghost match. Idempotent.
 */
export async function joinQueue(
  uid: string,
  profile: UserProfile,
  snapshotId: string,
): Promise<QueueResult> {
  const existing = await activeMatchOf(profile);
  if (existing) return { status: "matched", matchId: existing };
  const mine = await requireOwnActiveSnapshot(uid, snapshotId);
  const myName = profile.displayName?.text ?? mine.ownerDisplayName;
  const myRating = profile.rating ?? RATING.initial;

  const result = await db().runTransaction(async (tx): Promise<QueueResult & { joinedAtMs?: number }> => {
    const now = clock.now();
    const qRef = db().collection(COL.queue).doc(uid);
    const qSnap = await tx.get(qRef);
    const q = qSnap.data() as QueueDoc | undefined;
    const candidates = await tx.get(
      db()
        .collection(COL.queue)
        .where("status", "==", "waiting")
        .where("level", "in", levelBand(mine.level))
        .orderBy("joinedAtMs")
        .limit(10),
    );
    const cand = candidates.docs
      .map((d) => d.data() as QueueDoc)
      .find((c) => c.uid !== uid && now - c.lastSeenMs < LIMITS.queueStaleMs);
    if (cand) {
      const [cSnap, cUser] = await Promise.all([
        tx.get(db().collection(COL.snapshots).doc(cand.snapshotId)),
        tx.get(db().collection(COL.users).doc(cand.uid)),
      ]);
      const cs = cSnap.data() as SnapshotDoc | undefined;
      const cu = (cUser.data() ?? {}) as UserProfile;
      if (cs && cs.status === "active" && cu.consent?.online === true) {
        // The player who waited longer is side "a".
        const matchId = createMatchInTx(
          tx,
          sideInfo(cand.snapshotId, cs, cand.uid, cu.displayName?.text ?? cs.ownerDisplayName, cu.rating ?? RATING.initial),
          sideInfo(snapshotId, mine, uid, myName, myRating),
          "pvp",
        );
        const matched = { status: "matched", matchId, lastSeenMs: now } as const;
        tx.update(db().collection(COL.queue).doc(cand.uid), matched);
        tx.set(qRef, {
          uid,
          snapshotId,
          level: mine.level,
          joinedAtMs: now,
          ...matched,
        } satisfies QueueDoc);
        return { status: "matched", matchId };
      }
    }
    const joinedAtMs =
      q && q.status === "waiting" && q.snapshotId === snapshotId ? q.joinedAtMs : now;
    const doc: QueueDoc = {
      uid,
      snapshotId,
      level: mine.level,
      status: "waiting",
      matchId: null,
      joinedAtMs,
      lastSeenMs: now,
    };
    tx.set(qRef, doc);
    return { status: "waiting", waitedMs: now - joinedAtMs, joinedAtMs };
  });

  if (result.status === "waiting" && result.waitedMs >= LIMITS.ghostAfterMs) {
    const ghost = await startGhostMatch(uid);
    if (ghost) return ghost;
  }
  if (result.status === "waiting") return { status: "waiting", waitedMs: result.waitedMs };
  return result;
}

/** Leaves the queue if still waiting. */
export async function leaveQueue(uid: string): Promise<QueueResult> {
  return db().runTransaction(async (tx) => {
    const ref = db().collection(COL.queue).doc(uid);
    const snap = await tx.get(ref);
    const q = snap.data() as QueueDoc | undefined;
    if (q?.status === "matched" && q.matchId) {
      const m = await tx.get(db().collection(COL.matches).doc(q.matchId));
      if (m.exists && (m.data() as MatchDoc).status === "active") return { status: "matched", matchId: q.matchId };
    }
    if (snap.exists) tx.delete(ref);
    return { status: "left" };
  });
}

/** Picks a random active snapshot not owned by `uid`, preferring the level band. */
export async function pickGhost(uid: string, level: number): Promise<DocumentSnapshot | null> {
  const r = Math.random();
  const base = db().collection(COL.snapshots).where("status", "==", "active");
  const inBand = base.where("level", "in", levelBand(level));
  const queries: Query[] = [
    inBand.where("randomKey", ">=", r).orderBy("randomKey").limit(10),
    inBand.where("randomKey", "<", r).orderBy("randomKey").limit(10),
    base.where("randomKey", ">=", r).orderBy("randomKey").limit(10),
    base.where("randomKey", "<", r).orderBy("randomKey").limit(10),
  ];
  for (const q of queries) {
    const res = await q.get();
    const hit = res.docs.find((d) => {
      const doc = d.data() as SnapshotDoc;
      return doc.ownerUid !== uid && !isV2Snapshot(doc);
    });
    if (hit) return hit;
  }
  return null;
}

/**
 * Starts a match against a ghost (another player's registered snapshot,
 * driven by the server AI) for a player who has waited ≥ 60 s.
 */
export async function startGhostMatch(uid: string): Promise<QueueResult | null> {
  const qRef = db().collection(COL.queue).doc(uid);
  const q0 = (await qRef.get()).data() as QueueDoc | undefined;
  if (q0?.status !== "waiting") return null;
  const ghost = await pickGhost(uid, q0.level);
  if (!ghost) return null;
  return db().runTransaction(async (tx) => {
    const now = clock.now();
    const qSnap = await tx.get(qRef);
    const q = qSnap.data() as QueueDoc | undefined;
    if (q?.status !== "waiting" || now - q.joinedAtMs < LIMITS.ghostAfterMs) return null;
    const [mineSnap, ghostSnap, userSnap] = await Promise.all([
      tx.get(db().collection(COL.snapshots).doc(q.snapshotId)),
      tx.get(ghost.ref),
      tx.get(db().collection(COL.users).doc(uid)),
    ]);
    const mine = mineSnap.data() as SnapshotDoc | undefined;
    const g = ghostSnap.data() as SnapshotDoc | undefined;
    const profile = (userSnap.data() ?? {}) as UserProfile;
    if (!mine || mine.status !== "active" || !g || g.status !== "active") return null;
    if (profile.consent?.online !== true) return null;
    const myRating = profile.rating ?? RATING.initial;
    const matchId = createMatchInTx(
      tx,
      sideInfo(q.snapshotId, mine, uid, profile.displayName?.text ?? mine.ownerDisplayName, myRating),
      // Ghost rating mirrors the player's so the Elo expectation is neutral.
      sideInfo(ghostSnap.id, g, null, g.ownerDisplayName, myRating),
      "ghost",
    );
    tx.update(qRef, { status: "matched", matchId, lastSeenMs: now });
    return { status: "matched", matchId } as const;
  });
}
