/**
 * Cost mode: how much paid cloud work the backend does this month (docs/LEARN_GCP.md §6).
 *
 *   normal   everything on
 *   saving   cloud AI judging / move generation off (the app silently uses the on-device result),
 *            ghosts after 8 s instead of 20 s
 *   minimal  as saving, plus no PvP pairing (ghosts after 3 s)
 *
 * The single writer is the kill switch (onBudgetAlert) or the owner in the console. Readers
 * cache the document for a minute, so a change takes effect within ~1 minute everywhere.
 * Moderation for registerCharacter is never switched off (safety, fails closed).
 */
import costModeSpec from "../vendor/cost_mode/cost_mode.json";
import { clock } from "../lib/clock";
import { db } from "../lib/firebase";
import { logger } from "firebase-functions/v2";

export type CostModeName = "normal" | "saving" | "minimal";

export interface CostFlags {
  cloudJudge: boolean;
  cloudMoveGen: boolean;
  pvp: boolean;
  ghostAfterSec: number;
}

export interface CostMode {
  mode: CostModeName;
  flags: CostFlags;
}

export const COST_MODES: Record<CostModeName, CostFlags> = costModeSpec.modes;
export const COST_THRESHOLDS = costModeSpec.thresholds;
export const AI_YEN_PER_CALL: Record<string, number> = costModeSpec.aiEstimateYenPerCall;

/** Firestore location of the switch. Clients may read it (firestore.rules), never write. */
export const COST_MODE_DOC = { collection: "config", id: "costMode" } as const;

export function isCostModeName(v: unknown): v is CostModeName {
  return v === "normal" || v === "saving" || v === "minimal";
}

export function costModeOf(name: unknown): CostMode {
  const mode = isCostModeName(name) ? name : "normal";
  return { mode, flags: COST_MODES[mode] };
}

const TTL_MS = 60_000;
let cached: { value: CostMode; atMs: number } | undefined;

/** Current cost mode (cached ~1 minute). Read errors fail open to "normal". */
export async function getCostMode(): Promise<CostMode> {
  const now = clock.now();
  if (cached && now - cached.atMs < TTL_MS) return cached.value;
  let value = costModeOf("normal");
  try {
    const snap = await db().collection(COST_MODE_DOC.collection).doc(COST_MODE_DOC.id).get();
    value = costModeOf(snap.data()?.mode);
  } catch (err) {
    logger.warn("costMode read failed; assuming normal", { message: err instanceof Error ? err.message : String(err) });
    value = cached?.value ?? value;
  }
  cached = { value, atMs: now };
  return value;
}

/** Test hook: forget the cached mode. */
export function resetCostModeCacheForTesting(): void {
  cached = undefined;
}

/**
 * How long a v1 queue entry waits before a ghost match (the callable matchmaking). Normal mode
 * keeps LIMITS.ghostAfterMs; saving/minimal shorten it to the cost-mode value.
 */
export function effectiveGhostAfterMs(defaultMs: number, mode: CostMode): number {
  return mode.mode === "normal" ? defaultMs : Math.min(defaultMs, mode.flags.ghostAfterSec * 1000);
}
