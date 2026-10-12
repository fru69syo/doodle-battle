/**
 * Cost gate + meter around the AI service.
 *
 * - Gate: methods in COST_GATED_AI_METHODS (cloud features that are optional for children) are
 *   refused with AiUnavailableError while the cost mode turns cloud judging off. Callers already
 *   treat AiUnavailableError as "use the on-device result", so children see no difference.
 * - Meter: every AI call adds an estimate to ops/aiUsage_<YYYYMM>. The AI provider bills outside
 *   GCP, so the GCP budget cannot see it; the kill switch adds this estimate to the GCP spend.
 *
 * NOTE for new AI methods: add their names to COST_GATED_AI_METHODS if they are optional
 * (generateMove is); moderation must never be gated.
 */
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { AiUnavailableError, type AiService } from "../ai/types";
import { clock } from "../lib/clock";
import { db } from "../lib/firebase";
import { AI_YEN_PER_CALL, getCostMode } from "./costMode";

/** AI method -> the cost flag that must be on for it to run. */
export const COST_GATED_AI_METHODS: ReadonlyMap<string, "cloudJudge" | "cloudMoveGen"> = new Map([
  ["judgeDrawing", "cloudJudge"],
  ["generateMove", "cloudMoveGen"],
  ["generateMoves", "cloudMoveGen"],
] as const);

/** ops/aiUsage_YYYYMM, month in Japan time (matches how the owner reads the bill). */
export function aiUsageDocId(ms: number): string {
  const d = new Date(ms + 9 * 3_600_000);
  return `aiUsage_${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

export async function recordAiCall(method: string): Promise<void> {
  const yen = AI_YEN_PER_CALL[method] ?? 0.2;
  try {
    await db()
      .collection("ops")
      .doc(aiUsageDocId(clock.now()))
      .set({ calls: { [method]: FieldValue.increment(1) }, estYen: FieldValue.increment(yen), updatedAtMs: clock.now() }, { merge: true });
  } catch (err) {
    logger.warn("aiUsage write failed", { message: err instanceof Error ? err.message : String(err) });
  }
}

export async function readAiEstimateYen(ms: number): Promise<number> {
  const snap = await db().collection("ops").doc(aiUsageDocId(ms)).get();
  const v: unknown = snap.data()?.estYen;
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

/** Wraps every method of the service: gate (if listed) -> call -> meter. */
export function withCostControls<T extends AiService>(svc: T): T {
  return new Proxy(svc, {
    get(target, prop, receiver) {
      const value: unknown = Reflect.get(target, prop, receiver);
      if (typeof prop !== "string" || typeof value !== "function") return value;
      return async (...args: unknown[]) => {
        const flag = COST_GATED_AI_METHODS.get(prop);
        if (flag) {
          const mode = await getCostMode();
          if (!mode.flags[flag]) throw new AiUnavailableError(`cost mode ${mode.mode}: cloud ${prop} is off`);
        }
        const result: unknown = await (value as (...a: unknown[]) => Promise<unknown>).apply(target, args);
        await recordAiCall(prop);
        return result;
      };
    },
  });
}
