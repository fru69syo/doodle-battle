import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { LIMITS, RATE_LIMITS } from "../config";
import { requireUserWithConsent } from "../lib/auth";
import { clock } from "../lib/clock";
import { ErrorCode, fail } from "../lib/errors";
import { COL, db } from "../lib/firebase";
import { consumeRateLimit } from "../lib/rateLimit";
import { parseInput } from "../lib/validation";
import type { MatchDoc, SnapshotDoc } from "../model";
import { BASE_CALLABLE } from "./options";

/** Preset report reasons (no free text). */
export const REPORT_REASONS = [
  "bad_picture",
  "bad_name",
  "real_person",
  "personal_info",
  "copied_character",
  "other",
] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

const Input = z
  .object({ snapshotId: z.string().min(1).max(128), reasonCode: z.enum(REPORT_REASONS) })
  .strict();

export interface ReportResponse {
  ok: true;
  alreadyReported: boolean;
}

export function reportId(snapshotId: string, reporterUid: string): string {
  return `${snapshotId}__${reporterUid}`;
}

/**
 * Did `uid` meet `snapshotId` in one of their last matches? v1 matches (`matches`, Cloud
 * Functions) and v2 realtime matches (`rtMatches`, written by the battle server when a match
 * is settled — the app sends a report made during a battle after its `end` arrives).
 */
async function seenInRecentMatch(uid: string, snapshotId: string): Promise<boolean> {
  const [v1, v2] = await Promise.all([
    db().collection(COL.matches).where("playerUids", "array-contains", uid).orderBy("createdAtMs", "desc").limit(LIMITS.reportLookbackMatches).get(),
    db().collection(COL.rtMatches).where("playerUids", "array-contains", uid).orderBy("endedAtMs", "desc").limit(LIMITS.reportLookbackMatches).get(),
  ]);
  const has = (d: FirebaseFirestore.QueryDocumentSnapshot) => {
    const ids = (d.data() as Pick<MatchDoc, "snapshotIds">).snapshotIds;
    return Array.isArray(ids) && ids.includes(snapshotId);
  };
  return v1.docs.some(has) || v2.docs.some(has);
}

/**
 * reportCharacter(snapshotId, reasonCode): one report per (reporter, snapshot).
 * Only opponents from the reporter's recent matches can be reported. After
 * LIMITS.reportHideThreshold distinct reports the snapshot is hidden (no longer
 * matchable, image unreadable) and waits in `moderationQueue` for a human.
 */
export async function reportCharacterHandler(req: CallableRequest<unknown>): Promise<ReportResponse> {
  const { uid } = await requireUserWithConsent(req, "online");
  const { snapshotId, reasonCode } = parseInput(Input, req.data);
  const snapRef = db().collection(COL.snapshots).doc(snapshotId);
  const snap0 = await snapRef.get();
  if (!snap0.exists) fail(ErrorCode.NOT_FOUND, "character not found");
  if ((snap0.data() as SnapshotDoc).ownerUid === uid) fail(ErrorCode.CANNOT_REPORT_SELF, "own character");

  if (!(await seenInRecentMatch(uid, snapshotId))) {
    fail(ErrorCode.NOT_SEEN_IN_MATCH, "you can only report characters you played against");
  }
  await consumeRateLimit(uid, RATE_LIMITS.reportCharacter);

  const now = clock.now();
  const result = await db().runTransaction(async (tx) => {
    const rRef = db().collection(COL.reports).doc(reportId(snapshotId, uid));
    const qRef = db().collection(COL.moderationQueue).doc(snapshotId);
    const [r, s, q] = await Promise.all([tx.get(rRef), tx.get(snapRef), tx.get(qRef)]);
    if (r.exists) return { hidden: false, already: true };
    const snap = s.data() as SnapshotDoc;
    const count = (snap.reportCount || 0) + 1;
    const hide = count >= LIMITS.reportHideThreshold && snap.status === "active";
    tx.create(rRef, { snapshotId, reporterUid: uid, ownerUid: snap.ownerUid, reasonCode, createdAtMs: now });
    tx.update(snapRef, {
      reportCount: count,
      [`reportReasons.${reasonCode}`]: FieldValue.increment(1),
      ...(hide ? { status: "hidden", statusChangedAtMs: now } : {}),
    });
    tx.set(
      qRef,
      {
        snapshotId,
        ownerUid: snap.ownerUid,
        reportCount: count,
        reasons: { [reasonCode]: FieldValue.increment(1) },
        hidden: hide || snap.status === "hidden",
        state: "pending",
        updatedAtMs: now,
        ...(q.exists ? {} : { createdAtMs: now }),
      },
      { merge: true },
    );
    return { hidden: hide, already: false };
  });
  if (result.hidden) logger.warn("snapshot auto-hidden", { snapshotId });
  return { ok: true, alreadyReported: result.already };
}

export const reportCharacter = onCall(BASE_CALLABLE, reportCharacterHandler);
