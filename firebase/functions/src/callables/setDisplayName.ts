import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { RATE_LIMITS } from "../config";
import { requireUserWithConsent } from "../lib/auth";
import { ErrorCode, fail } from "../lib/errors";
import { COL, db } from "../lib/firebase";
import { consumeRateLimit } from "../lib/rateLimit";
import { parseInput } from "../lib/validation";
import { composeDisplayName, randomDisplayName, type DisplayName } from "../names/displayName";
import { BASE_CALLABLE } from "./options";

const Input = z
  .object({ adjectiveId: z.string().max(8).optional(), nounId: z.string().max(8).optional() })
  .strict()
  .refine((v) => (v.adjectiveId === undefined) === (v.nounId === undefined));

/**
 * setDisplayName: picks the online display name from preset word ids
 * (display_name_words.json). Omit both ids for a random name. No free text.
 */
export async function setDisplayNameHandler(req: CallableRequest<unknown>): Promise<{ displayName: DisplayName }> {
  const { uid } = await requireUserWithConsent(req, "online");
  const input = parseInput(Input, req.data ?? {});
  await consumeRateLimit(uid, RATE_LIMITS.setDisplayName);
  let dn: DisplayName | null;
  if (input.adjectiveId !== undefined && input.nounId !== undefined) {
    dn = composeDisplayName(input.adjectiveId, input.nounId);
  } else {
    dn = randomDisplayName();
  }
  if (!dn) fail(ErrorCode.INVALID_ARGUMENT, "unknown word id");
  await db().collection(COL.users).doc(uid).set({ displayName: dn }, { merge: true });
  return { displayName: dn };
}

export const setDisplayName = onCall(BASE_CALLABLE, setDisplayNameHandler);
