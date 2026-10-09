import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import "../config";
import { clock } from "../lib/clock";
import { COL, db } from "../lib/firebase";
import type { UserProfile } from "../lib/auth";

/**
 * When a parent withdraws online consent, the child's characters stop being
 * visible online immediately (no new matches, no ghost use, images
 * unreadable) and the child leaves the queue.
 */
export async function handleConsentChange(
  uid: string,
  before: UserProfile | undefined,
  after: UserProfile | undefined,
): Promise<number> {
  if (before?.consent?.online !== true || after?.consent?.online === true) return 0;
  const now = clock.now();
  const snaps = await db()
    .collection(COL.snapshots)
    .where("ownerUid", "==", uid)
    .where("status", "==", "active")
    .get();
  const batch = db().batch();
  snaps.docs.forEach((d) => batch.update(d.ref, { status: "withdrawn", statusChangedAtMs: now }));
  batch.delete(db().collection(COL.queue).doc(uid));
  await batch.commit();
  return snaps.size;
}

export const onUserConsentChanged = onDocumentUpdated(`${COL.users}/{uid}`, async (event) => {
  await handleConsentChange(
    event.params.uid,
    event.data?.before.data(),
    event.data?.after.data(),
  );
});
