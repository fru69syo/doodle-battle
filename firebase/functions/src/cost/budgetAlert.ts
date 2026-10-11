/**
 * Kill switch: Cloud Billing budget -> Pub/Sub topic `budget-alerts` -> this function ->
 * config/costMode (docs/LEARN_GCP.md §6, infra/terraform/modules/cost_guard).
 *
 * Cloud Billing publishes the month-to-date cost several times a day (not only when a
 * threshold is crossed). Each message recomputes the mode from
 *     (GCP cost + estimated AI provider cost) / budget
 * so the mode only rises during a month and falls back to normal when the new month starts
 * (cost resets) or when the owner raises the budget. Billing data lags by hours, which is why
 * "saving" already starts at 80 %.
 *
 * Owner override: set `pinned: true` on config/costMode in the console and the function stops
 * changing it (e.g. to force "minimal" for maintenance, or "normal" for a demo).
 */
import { logger, type CloudEvent } from "firebase-functions/v2";
import { onMessagePublished, type MessagePublishedData } from "firebase-functions/v2/pubsub";
import { z } from "zod";
import { clock } from "../lib/clock";
import { db } from "../lib/firebase";
import { readAiEstimateYen } from "./aiUsage";
import { COST_MODE_DOC, COST_MODES, COST_THRESHOLDS, isCostModeName, type CostModeName } from "./costMode";

/** Topic created by Terraform (modules/cost_guard). */
export const BUDGET_TOPIC = "budget-alerts";

/** Runtime service account created by Terraform (least privilege: Firestore + logging). */
export const COST_GUARD_SA = "cost-guard@";

/** Budget notification payload (Cloud Billing programmatic notifications, schema 1.0). */
export const BudgetMessage = z.object({
  budgetDisplayName: z.string().optional(),
  costAmount: z.number().nonnegative(),
  costIntervalStart: z.string().optional(),
  budgetAmount: z.number().positive(),
  budgetAmountType: z.string().optional(),
  currencyCode: z.string().optional(),
  alertThresholdExceeded: z.number().optional(),
  forecastThresholdExceeded: z.number().optional(),
});
export type BudgetMessage = z.infer<typeof BudgetMessage>;

export interface Decision {
  mode: CostModeName;
  spentPct: number;
  reason: string;
}

/** Pure decision (unit-tested): which mode for this spend? */
export function decideMode(msg: BudgetMessage, aiEstimateYen: number): Decision {
  const ai = (msg.currencyCode ?? "JPY") === "JPY" ? aiEstimateYen : 0;
  const rawPct = ((msg.costAmount + ai) / msg.budgetAmount) * 100;
  const spentPct = Math.floor(rawPct * 10) / 10; // for logs only; thresholds use rawPct
  const forecastPct = (msg.forecastThresholdExceeded ?? 0) * 100;
  if (rawPct >= COST_THRESHOLDS.minimalAtPct) return { mode: "minimal", spentPct, reason: `spent ${spentPct}% >= ${COST_THRESHOLDS.minimalAtPct}%` };
  if (rawPct >= COST_THRESHOLDS.savingAtPct) return { mode: "saving", spentPct, reason: `spent ${spentPct}% >= ${COST_THRESHOLDS.savingAtPct}%` };
  if (forecastPct >= COST_THRESHOLDS.forecastSavingAtPct) return { mode: "saving", spentPct, reason: `forecast ${forecastPct}% >= ${COST_THRESHOLDS.forecastSavingAtPct}%` };
  return { mode: "normal", spentPct, reason: `spent ${spentPct}%` };
}

export interface ApplyResult {
  changed: boolean;
  previous: CostModeName;
  decision: Decision;
  pinned: boolean;
}

/** Reads the AI estimate, decides, and writes config/costMode (only on change) + ops/costStatus. */
export async function applyBudgetMessage(raw: unknown): Promise<ApplyResult | null> {
  const parsed = BudgetMessage.safeParse(raw);
  if (!parsed.success) {
    logger.error("budget message not understood", { event: "budget_message_invalid", issues: parsed.error.issues.length });
    return null;
  }
  const msg = parsed.data;
  const now = clock.now();
  const aiYen = await readAiEstimateYen(now).catch(() => 0);
  const decision = decideMode(msg, aiYen);
  const ref = db().collection(COST_MODE_DOC.collection).doc(COST_MODE_DOC.id);

  const result = await db().runTransaction(async (tx): Promise<ApplyResult> => {
    const cur = (await tx.get(ref)).data() ?? {};
    const previous: CostModeName = isCostModeName(cur.mode) ? cur.mode : "normal";
    const pinned = cur.pinned === true;
    const changed = !pinned && previous !== decision.mode;
    if (changed) {
      tx.set(ref, { mode: decision.mode, flags: COST_MODES[decision.mode], updatedAtMs: now, source: "budget", pinned: false }, { merge: true });
    }
    // Server-only status for the owner (Firestore console) and debugging.
    tx.set(db().collection("ops").doc("costStatus"), {
      lastMessageAtMs: now,
      costAmount: msg.costAmount,
      budgetAmount: msg.budgetAmount,
      currencyCode: msg.currencyCode ?? null,
      aiEstimateYen: aiYen,
      spentPct: decision.spentPct,
      decidedMode: decision.mode,
      appliedMode: changed ? decision.mode : previous,
      pinned,
      reason: decision.reason,
      costIntervalStart: msg.costIntervalStart ?? null,
    });
    return { changed, previous, decision, pinned };
  });

  if (result.changed) {
    // The log-based metric cost/mode_changed and the alert policy key on `event`.
    logger.warn("cost mode changed", { event: "cost_mode_changed", mode: decision.mode, previous: result.previous, spentPct: decision.spentPct, reason: decision.reason });
  } else {
    logger.info("budget message", { event: "budget_message", mode: result.pinned ? "pinned" : result.previous, spentPct: decision.spentPct });
  }
  return result;
}

export async function onBudgetAlertHandler(event: CloudEvent<MessagePublishedData>): Promise<void> {
  let payload: unknown;
  try {
    payload = event.data.message.json;
  } catch {
    logger.error("budget message is not JSON", { event: "budget_message_invalid" });
    return;
  }
  await applyBudgetMessage(payload);
}

export const onBudgetAlert = onMessagePublished(
  {
    topic: BUDGET_TOPIC,
    serviceAccount: COST_GUARD_SA,
    memory: "256MiB",
    timeoutSeconds: 60,
    maxInstances: 1,
    // A failed write is retried by Pub/Sub; the next budget message would fix it anyway.
    retry: false,
  },
  onBudgetAlertHandler,
);
