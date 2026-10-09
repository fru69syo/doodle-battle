import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { joinQueue as join, leaveQueue as leave, type QueueResult } from "../battle/matchmaking";
import { requireUid, requireUserWithConsent } from "../lib/auth";
import { parseInput } from "../lib/validation";
import { BASE_CALLABLE } from "./options";

const JoinInput = z.object({ characterId: z.string().min(1).max(128) }).strict();

/** joinQueue(characterId): characterId is the registered snapshot id (Character.onlineId). */
export async function joinQueueHandler(req: CallableRequest<unknown>): Promise<QueueResult> {
  const { uid, profile } = await requireUserWithConsent(req, "online");
  const { characterId } = parseInput(JoinInput, req.data);
  return join(uid, profile, characterId);
}

export async function leaveQueueHandler(req: CallableRequest<unknown>): Promise<QueueResult> {
  const uid = requireUid(req);
  return leave(uid);
}

export const joinQueue = onCall(BASE_CALLABLE, joinQueueHandler);
export const leaveQueue = onCall(BASE_CALLABLE, leaveQueueHandler);
