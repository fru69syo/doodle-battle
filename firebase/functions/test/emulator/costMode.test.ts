import { describe, expect, it } from "vitest";
import { joinQueueHandler } from "../../src/callables/matchmaking";
import { judgeDrawingHandler } from "../../src/callables/judgeDrawing";
import { registerCharacterHandler } from "../../src/callables/registerCharacter";
import { aiUsageDocId } from "../../src/cost/aiUsage";
import { applyBudgetMessage, onBudgetAlertHandler } from "../../src/cost/budgetAlert";
import { getCostMode, resetCostModeCacheForTesting } from "../../src/cost/costMode";
import { clock } from "../../src/lib/clock";
import { db } from "../../src/lib/firebase";
import { errorCode, registerInput, req, seedUser, useEmulatorEnv } from "../helpers/emulator";
import { registeredPlayer } from "../helpers/fixtures";
import { pngBase64 } from "../helpers/png";

const env = useEmulatorEnv();
const costDoc = () => db().collection("config").doc("costMode");
const budget = (costAmount: number, extra: Record<string, unknown> = {}) => ({ costAmount, budgetAmount: 5000, currencyCode: "JPY", ...extra });

async function setMode(mode: string, extra: Record<string, unknown> = {}): Promise<void> {
  await costDoc().set({ mode, ...extra });
  resetCostModeCacheForTesting();
}

describe("kill switch: onBudgetAlert", () => {
  it("writes config/costMode only when the mode changes, and always ops/costStatus", async () => {
    expect(await applyBudgetMessage(budget(1000))).toMatchObject({ changed: false, previous: "normal" });
    expect((await costDoc().get()).exists).toBe(false);

    const r = await applyBudgetMessage(budget(4100));
    expect(r).toMatchObject({ changed: true, previous: "normal", decision: { mode: "saving" } });
    expect((await costDoc().get()).data()).toMatchObject({ mode: "saving", flags: { cloudJudge: false, pvp: true, ghostAfterSec: 8 }, source: "budget" });

    await applyBudgetMessage(budget(5200));
    expect((await costDoc().get()).data()?.mode).toBe("minimal");
    expect((await db().collection("ops").doc("costStatus").get()).data()).toMatchObject({ spentPct: 104, appliedMode: "minimal" });

    // New month: spend resets -> back to normal automatically.
    await applyBudgetMessage(budget(10, { costIntervalStart: "2026-11-01T07:00:00Z" }));
    expect((await costDoc().get()).data()?.mode).toBe("normal");
  });

  it("includes the metered AI estimate", async () => {
    await db().collection("ops").doc(aiUsageDocId(clock.now())).set({ estYen: 1200 });
    expect((await applyBudgetMessage(budget(3000)))?.decision).toMatchObject({ mode: "saving", spentPct: 84 });
  });

  it("respects an owner pin", async () => {
    await costDoc().set({ mode: "normal", pinned: true });
    expect(await applyBudgetMessage(budget(6000))).toMatchObject({ changed: false, pinned: true });
    expect((await costDoc().get()).data()?.mode).toBe("normal");
  });

  it("ignores messages it does not understand", async () => {
    expect(await applyBudgetMessage({ hello: "world" })).toBeNull();
    await onBudgetAlertHandler({ data: { message: { json: budget(4500) } } } as never);
    expect((await costDoc().get()).data()?.mode).toBe("saving");
  });
});

describe("cost mode readers", () => {
  it("is cached for a minute", async () => {
    await setMode("saving");
    expect((await getCostMode()).mode).toBe("saving");
    await costDoc().set({ mode: "minimal" });
    expect((await getCostMode()).mode).toBe("saving");
    env.advance(60_000);
    expect((await getCostMode()).mode).toBe("minimal");
  });

  it("judgeDrawing: saving mode refuses before calling the AI (the app falls back on device)", async () => {
    await seedUser("kid");
    await setMode("saving");
    expect(await errorCode(judgeDrawingHandler(req("kid", { imageBase64: pngBase64() })))).toBe("AI_UNAVAILABLE");
    expect(env.ai.judgeDrawing).not.toHaveBeenCalled();
  });

  it("judgeDrawing: normal mode calls the AI and meters the call", async () => {
    await seedUser("kid");
    await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect(env.ai.judgeDrawing).toHaveBeenCalledTimes(1);
    const usage = (await db().collection("ops").doc(aiUsageDocId(clock.now())).get()).data();
    expect(usage).toMatchObject({ calls: { judgeDrawing: 1 } });
    expect(usage?.estYen).toBeGreaterThan(0);
  });

  it("registerCharacter moderation keeps working in minimal mode (safety is never degraded)", async () => {
    await seedUser("kid");
    await setMode("minimal");
    const res = await registerCharacterHandler(req("kid", registerInput()));
    expect(env.ai.moderateCharacter).toHaveBeenCalledTimes(1);
    expect(res).toBeDefined();
  });

  it("matchmaking: saving mode uses a ghost after 8 s instead of 60 s", async () => {
    await registeredPlayer("ghostowner", { level: 7, xp: 0 });
    const sa = await registeredPlayer("alice");
    await setMode("saving");
    expect((await joinQueueHandler(req("alice", { characterId: sa }))).status).toBe("waiting");
    env.advance(8_000);
    expect((await joinQueueHandler(req("alice", { characterId: sa }))).status).toBe("matched");
  });

  it("matchmaking: minimal mode does not pair two children", async () => {
    const sa = await registeredPlayer("alice");
    const sb = await registeredPlayer("bob");
    await setMode("minimal");
    expect((await joinQueueHandler(req("alice", { characterId: sa }))).status).toBe("waiting");
    expect((await joinQueueHandler(req("bob", { characterId: sb }))).status).toBe("waiting");
  });
});
