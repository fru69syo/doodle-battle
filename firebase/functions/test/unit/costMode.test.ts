import { describe, expect, it } from "vitest";
import { aiUsageDocId, COST_GATED_AI_METHODS } from "../../src/cost/aiUsage";
import { decideMode, type BudgetMessage } from "../../src/cost/budgetAlert";
import { COST_MODES, COST_THRESHOLDS, costModeOf, effectiveGhostAfterMs } from "../../src/cost/costMode";

const msg = (costAmount: number, extra: Partial<BudgetMessage> = {}): BudgetMessage => ({
  budgetDisplayName: "doodle-battle prod monthly",
  costAmount,
  budgetAmount: 5000,
  currencyCode: "JPY",
  costIntervalStart: "2026-10-01T07:00:00Z",
  budgetAmountType: "SPECIFIED_AMOUNT",
  ...extra,
});

describe("decideMode (kill switch)", () => {
  it("normal below 80 %, saving from 80 %, minimal from 100 %", () => {
    expect(COST_THRESHOLDS).toMatchObject({ savingAtPct: 80, minimalAtPct: 100 });
    expect(decideMode(msg(0), 0).mode).toBe("normal");
    expect(decideMode(msg(3999), 0)).toMatchObject({ mode: "normal", spentPct: 79.9 });
    expect(decideMode(msg(3990), 0).mode).toBe("normal");
    expect(decideMode(msg(4000), 0).mode).toBe("saving");
    expect(decideMode(msg(4999), 0).mode).toBe("saving");
    expect(decideMode(msg(5000), 0).mode).toBe("minimal");
    expect(decideMode(msg(9000), 0).mode).toBe("minimal");
  });

  it("adds the AI provider estimate (billed outside GCP) for JPY budgets", () => {
    expect(decideMode(msg(3000), 1000)).toMatchObject({ mode: "saving", spentPct: 80 });
    expect(decideMode(msg(3000, { currencyCode: "USD", budgetAmount: 35 }), 1000).mode).toBe("minimal");
    expect(decideMode(msg(20, { currencyCode: "USD", budgetAmount: 35 }), 100_000).mode).toBe("normal");
  });

  it("a strong forecast (>= 120 %) switches to saving early", () => {
    expect(decideMode(msg(1000, { forecastThresholdExceeded: 1.0 }), 0).mode).toBe("normal");
    expect(decideMode(msg(1000, { forecastThresholdExceeded: 1.2 }), 0).mode).toBe("saving");
  });
});

describe("cost mode flags", () => {
  it("unknown values mean normal", () => {
    expect(costModeOf("weird")).toEqual({ mode: "normal", flags: COST_MODES.normal });
  });

  it("saving/minimal shorten the v1 ghost wait, normal keeps it", () => {
    expect(effectiveGhostAfterMs(60_000, costModeOf("normal"))).toBe(60_000);
    expect(effectiveGhostAfterMs(60_000, costModeOf("saving"))).toBe(8_000);
    expect(effectiveGhostAfterMs(60_000, costModeOf("minimal"))).toBe(3_000);
    expect(effectiveGhostAfterMs(2_000, costModeOf("saving"))).toBe(2_000);
  });

  it("gates optional cloud AI only; moderation is never gated", () => {
    expect(COST_GATED_AI_METHODS.get("judgeDrawing")).toBe("cloudJudge");
    expect(COST_GATED_AI_METHODS.has("moderateCharacter")).toBe(false);
  });

  it("meters per Japanese calendar month", () => {
    expect(aiUsageDocId(Date.UTC(2026, 9, 31, 14, 59))).toBe("aiUsage_202610");
    expect(aiUsageDocId(Date.UTC(2026, 9, 31, 15, 0))).toBe("aiUsage_202611");
  });
});
