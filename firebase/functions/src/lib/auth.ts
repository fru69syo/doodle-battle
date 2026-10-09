import type { CallableRequest } from "firebase-functions/v2/https";
import { COL, db } from "./firebase";
import { ErrorCode, fail } from "./errors";

export interface Consent {
  cloudJudge: boolean;
  online: boolean;
  policyVersion: number;
}

export interface UserProfile {
  consent?: Partial<Consent>;
  displayName?: { adjectiveId: string; nounId: string; text: string };
  rating?: number;
  onlineStats?: { wins: number; losses: number; draws: number };
  activeMatchId?: string | null;
}

export function requireUid(req: Pick<CallableRequest, "auth">): string {
  const uid = req.auth?.uid;
  if (!uid) fail(ErrorCode.UNAUTHENTICATED, "sign-in required");
  return uid;
}

export async function getProfile(uid: string): Promise<UserProfile | undefined> {
  const snap = await db().collection(COL.users).doc(uid).get();
  return snap.exists ? (snap.data()) : undefined;
}

/**
 * Consent flags are written by the app behind the parent gate (SPEC §7) and
 * validated by firestore.rules. Functions refuse to do anything a parent has
 * not allowed.
 */
export function requireConsent(
  profile: UserProfile | undefined,
  kind: "cloudJudge" | "online",
): UserProfile {
  if (profile?.consent?.[kind] !== true) {
    fail(ErrorCode.CONSENT_REQUIRED, `parent consent required: ${kind}`);
  }
  return profile;
}

export async function requireUserWithConsent(
  req: Pick<CallableRequest, "auth">,
  kind: "cloudJudge" | "online",
): Promise<{ uid: string; profile: UserProfile }> {
  const uid = requireUid(req);
  const profile = requireConsent(await getProfile(uid), kind);
  return { uid, profile };
}
