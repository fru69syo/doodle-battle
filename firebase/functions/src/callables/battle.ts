import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { ACTION_IDS } from "../battle/engine";
import { enforceDeadline, matchRef, sideOf, submitAction as submit, type SubmitResult } from "../battle/matchService";
import { LIMITS } from "../config";
import { requireUid, requireUserWithConsent } from "../lib/auth";
import { clock } from "../lib/clock";
import { ErrorCode, fail } from "../lib/errors";
import { parseInput } from "../lib/validation";
import type { MatchDoc } from "../model";
import { BASE_CALLABLE } from "./options";

const SubmitInput = z
  .object({
    matchId: z.string().min(1).max(128),
    turn: z.number().int().min(1).max(1000),
    action: z.enum(ACTION_IDS),
  })
  .strict();

/** submitAction(matchId, turn, action) */
export async function submitActionHandler(req: CallableRequest<unknown>): Promise<SubmitResult> {
  const { uid } = await requireUserWithConsent(req, "online");
  const { matchId, turn, action } = parseInput(SubmitInput, req.data);
  // A late submit after the deadline first lets the timeout resolve the turn.
  await enforceDeadline(matchId);
  return submit(matchId, uid, turn, action);
}

const PollInput = z.object({ matchId: z.string().min(1).max(128) }).strict();

export interface PollResult {
  status: MatchDoc["status"];
  turn: number;
  turnDeadlineMs: number;
}

/**
 * pollMatch(matchId): clients call this when their local 20 s turn timer runs
 * out (and every few seconds while waiting) so that an absent opponent's turn
 * is resolved promptly without waiting for the minute sweep.
 */
export async function pollMatchHandler(req: CallableRequest<unknown>): Promise<PollResult> {
  const uid = requireUid(req);
  const { matchId } = parseInput(PollInput, req.data);
  const snap = await matchRef(matchId).get();
  if (!snap.exists) fail(ErrorCode.NOT_FOUND, "match not found");
  let match = snap.data() as MatchDoc;
  if (!sideOf(match, uid)) fail(ErrorCode.NOT_IN_MATCH, "not a player of this match");
  if (match.status === "active" && clock.now() >= match.turnDeadlineMs + LIMITS.turnGraceMs) {
    if (await enforceDeadline(matchId)) match = (await matchRef(matchId).get()).data() as MatchDoc;
  }
  return { status: match.status, turn: match.turn, turnDeadlineMs: match.turnDeadlineMs };
}

export const submitAction = onCall(BASE_CALLABLE, submitActionHandler);
export const pollMatch = onCall(BASE_CALLABLE, pollMatchHandler);
