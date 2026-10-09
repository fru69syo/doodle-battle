import { logger } from "firebase-functions/v2";
import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { requireUid } from "../lib/auth";
import { ErrorCode, fail } from "../lib/errors";
import { auth, bucket, COL, db } from "../lib/firebase";
import { BASE_CALLABLE } from "./options";


export interface DeleteMyDataResponse {
  ok: true;
  deleted: { snapshots: number; matches: number; reports: number };
}

async function deleteQuery(q: FirebaseFirestore.Query): Promise<number> {
  let n = 0;
  for (;;) {
    const page = await q.limit(300).get();
    if (page.empty) return n;
    const batch = db().batch();
    page.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    n += page.size;
  }
}

/** Deletes every match document (and sub-collections) returned by `q`. */
async function deleteMatches(q: FirebaseFirestore.Query, seen: Set<string>): Promise<void> {
  for (;;) {
    const page = await q.limit(100).get();
    const fresh = page.docs.filter((d) => !seen.has(d.id));
    if (fresh.length === 0) return;
    for (const d of fresh) {
      seen.add(d.id);
      await db().recursiveDelete(d.ref);
    }
  }
}

/**
 * deleteMyData: parent-initiated deletion of everything the server holds for
 * this account (Families policy / Data safety): snapshots + images, matches
 * the user played or appeared in as a ghost, reports made by or about the
 * user, queue/rate-limit/moderation records, the profile, and the auth user.
 */
export async function deleteMyDataHandler(req: CallableRequest<unknown>): Promise<DeleteMyDataResponse> {
  const uid = requireUid(req);
  const data: unknown = req.data;
  if (typeof data !== "object" || data === null || (data as { confirm?: unknown }).confirm !== "DELETE") {
    fail(ErrorCode.CONFIRMATION_REQUIRED, 'pass { confirm: "DELETE" }');
  }
  const fs = db();

  const snaps = await fs.collection(COL.snapshots).where("ownerUid", "==", uid).get();
  const matchIds = new Set<string>();
  await deleteMatches(fs.collection(COL.matches).where("playerUids", "array-contains", uid), matchIds);
  let reports = 0;
  for (const s of snaps.docs) {
    await deleteMatches(fs.collection(COL.matches).where("snapshotIds", "array-contains", s.id), matchIds);
    reports += await deleteQuery(fs.collection(COL.reports).where("snapshotId", "==", s.id));
    await fs.collection(COL.moderationQueue).doc(s.id).delete();
    await bucket().deleteFiles({ prefix: `snapshotImages/${s.id}/` });
    await s.ref.delete();
  }
  reports += await deleteQuery(fs.collection(COL.reports).where("reporterUid", "==", uid));
  await deleteQuery(fs.collection(COL.moderationLog).where("uid", "==", uid));
  await Promise.all([
    fs.collection(COL.queue).doc(uid).delete(),
    fs.collection(COL.rateLimits).doc(uid).delete(),
    fs.collection(COL.users).doc(uid).delete(),
  ]);
  try {
    await auth().deleteUser(uid);
  } catch (err) {
    const code = (err as { code?: string }).code;
    if (code !== "auth/user-not-found") {
      logger.error("deleteMyData: auth deletion failed", { uid, code });
      fail(ErrorCode.INTERNAL, "auth deletion failed; data was deleted, please retry");
    }
  }
  logger.info("deleteMyData done", { uid, snapshots: snaps.size, matches: matchIds.size, reports });
  return { ok: true, deleted: { snapshots: snaps.size, matches: matchIds.size, reports } };
}

export const deleteMyData = onCall({ ...BASE_CALLABLE, timeoutSeconds: 300 }, deleteMyDataHandler);
