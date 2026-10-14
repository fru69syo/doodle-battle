import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { AiUnavailableError } from "../../src/ai";
import { generateMoveHandler } from "../../src/callables/generateMove";
import { aiUsageDocId } from "../../src/cost/aiUsage";
import { resetCostModeCacheForTesting } from "../../src/cost/costMode";
import { clock } from "../../src/lib/clock";
import { db } from "../../src/lib/firebase";
import { DEFAULT_SPEC, moveContextOf } from "../../src/vendor/battle_engine_v3";
import { errorCode, okVerdict, req, seedUser, useEmulatorEnv } from "../helpers/emulator";
import { makePng, pngBase64 } from "../helpers/png";

const env = useEmulatorEnv();
const golden = JSON.parse(
  readFileSync(join(process.cwd(), "..", "..", "shared", "battle_spec_v3", "golden_vectors.json"), "utf8"),
) as { genomes: { input: { features: Record<string, number>; energy10: number; skill10: number } }[] };
const g0 = golden.genomes[0]!.input;
const character = { features: g0.features, energy10: g0.energy10, skill10: g0.skill10 };

const input = (over: Record<string, unknown> = {}) => ({
  imageBase64: pngBase64(),
  ...character,
  level: 10,
  slot: 2,
  otherNames: ["ねこパンチ"],
  ...over,
});
const generate = (over: Record<string, unknown> = {}, uid = "kid") => generateMoveHandler(req(uid, input(over)));

async function setMode(mode: string): Promise<void> {
  await db().collection("config").doc("costMode").set({ mode });
  resetCostModeCacheForTesting();
}

describe("generateMove (Lv10 / Lv50 AI move naming)", () => {
  it("returns a validated, budget-fitted move whose words were moderated", async () => {
    await seedUser("kid");
    const res = await generate();
    expect(res).toMatchObject({ slot: 2, source: "ai", proposal: { template: "strike", name: "きらきらスター", flavor: "ほしが きらきら ふってくる" } });
    // The AI asked for power 300: the validator clamps it to the template range / slot budget.
    expect((res.proposal as { power: number }).power).toBeLessThanOrEqual(200);
    const ctx = moveContextOf({ ...character, imageHash: "x" }, { level: 10 })!;
    expect(env.ai.generateMove).toHaveBeenCalledWith(expect.any(Buffer), {
      attribute: ctx.attribute,
      slot: 2,
      budget: ctx.slotBudgets[2],
      otherNames: ["ねこパンチ"],
    });
    expect(env.ai.moderateCharacter).toHaveBeenCalledWith(expect.any(Buffer), ["きらきらスター", "ほしが きらきら ふってくる"]);
    // Metered like every AI call (the AI provider bills outside GCP).
    const usage = (await db().collection("ops").doc(aiUsageDocId(clock.now())).get()).data();
    expect(usage).toMatchObject({ calls: { generateMove: 1, moderateCharacter: 1 } });
  });

  it("the Lv50 slot is a neutral damage move", async () => {
    await seedUser("kid");
    const res = await generate({ level: 50, slot: 3 });
    expect(res).toMatchObject({ slot: 3, source: "ai", proposal: { template: "blast", attribute: "none" } });
  });

  it("at Lv50 every slot can be renamed, for every character alike (no hint of the hidden form)", async () => {
    const shapes: string[] = [];
    for (const verdict of [undefined, "ai_generated", "digital"]) {
      const uid = `kid_${verdict ?? "plain"}`;
      await seedUser(uid);
      for (const slot of [3, 0, 1, 2]) {
        const res = await generate({ level: 50, slot, otherNames: [], ...(verdict ? { verdict } : {}) }, uid);
        expect(res.slot).toBe(slot);
        // Same response shape whatever the verdict: slot, source, proposal (+ reason).
        shapes.push(Object.keys(res).sort().join(","));
        const ctx = moveContextOf({ ...character, imageHash: "x", verdict: verdict ?? null }, { level: 50 })!;
        expect(env.ai.generateMove).toHaveBeenLastCalledWith(expect.any(Buffer), {
          attribute: ctx.attribute,
          slot,
          budget: ctx.slotBudgets[slot],
          otherNames: [],
        });
      }
    }
    expect(new Set(shapes).size).toBeLessThanOrEqual(2); // "ai" or "template" answers only
    expect(env.ai.generateMove).toHaveBeenCalledTimes(12);
  });

  it("refuses slots that are not unlocked yet and bad input before calling the AI", async () => {
    await seedUser("kid");
    expect(await errorCode(generate({ level: 9 }))).toBe("INVALID_ARGUMENT");
    expect(await errorCode(generate({ level: 49, slot: 3 }))).toBe("INVALID_ARGUMENT");
    expect(await errorCode(generate({ otherNames: ["<script>"] }))).toBe("INVALID_ARGUMENT");
    expect(await errorCode(generate({ features: { roundness: 0.5 } }))).toBe("INVALID_ARGUMENT");
    expect(await errorCode(generate({ imageBase64: makePng(2048, 2048).toString("base64") }))).toBe("IMAGE_TOO_LARGE");
    expect(env.ai.generateMove).not.toHaveBeenCalled();
  });

  it("needs sign-in and the parent's cloud consent", async () => {
    await seedUser("kid", { cloudJudge: false, online: true });
    expect(await errorCode(generate({}, null as unknown as string))).toBe("UNAUTHENTICATED");
    expect(await errorCode(generate())).toBe("CONSENT_REQUIRED");
    expect(env.ai.generateMove).not.toHaveBeenCalled();
  });

  it("saving / minimal cost modes skip the AI entirely (template move)", async () => {
    await seedUser("kid");
    for (const mode of ["saving", "minimal"]) {
      await setMode(mode);
      expect(await generate()).toEqual({ slot: 2, source: "template", proposal: null, reason: "cost_mode" });
    }
    expect(env.ai.generateMove).not.toHaveBeenCalled();
    expect(env.ai.moderateCharacter).not.toHaveBeenCalled();
  });

  it("falls back to the template move on any AI or validation failure", async () => {
    await seedUser("kid");
    env.ai.generateMove.mockRejectedValueOnce(new AiUnavailableError("down"));
    expect(await generate()).toMatchObject({ source: "template", proposal: null, reason: "ai_unavailable" });

    env.ai.generateMove.mockResolvedValueOnce({ template: "fireball", name: "ファイア" });
    expect(await generate()).toMatchObject({ source: "template", reason: "rejected" });

    env.ai.generateMove.mockResolvedValueOnce({ template: "strike", attribute: "gu", name: "Punch!" });
    expect(await generate()).toMatchObject({ source: "template", reason: "rejected" });

    env.ai.generateMove.mockResolvedValueOnce({ template: "strike", attribute: "gu", name: "ねこパンチ" });
    expect(await generate()).toMatchObject({ source: "template", reason: "duplicate" });

    env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
      ...okVerdict(names),
      names: names.map(() => ({ ok: false, category: "insult" as const })),
    }));
    expect(await generate()).toMatchObject({ source: "template", reason: "moderation" });

    env.ai.moderateCharacter.mockRejectedValueOnce(new AiUnavailableError("down"));
    expect(await generate()).toMatchObject({ source: "template", reason: "moderation" });
  });

  it("a refused flavour text is dropped, the move is kept", async () => {
    await seedUser("kid");
    env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
      ...okVerdict(names),
      names: names.map((_, i) => (i === 1 ? { ok: false, category: "other" as const } : { ok: true, category: "ok" as const })),
    }));
    const res = await generate();
    expect(res).toMatchObject({ source: "ai", proposal: { name: "きらきらスター", flavor: "" } });
  });

  it("is rate-limited per child", async () => {
    await seedUser("kid");
    for (let i = 0; i < 10; i++) await generate();
    expect(await errorCode(generate())).toBe("RATE_LIMITED");
  });

  it("budgets come from the device's data only (no server verdict leaks into the answer)", async () => {
    await seedUser("kid");
    await generate({ verdict: "digital" });
    const ctx = moveContextOf({ ...character, imageHash: "x", verdict: "digital" }, { level: 10 })!;
    expect(env.ai.generateMove.mock.calls[0]![1].budget).toBe(ctx.slotBudgets[2]);
    expect(DEFAULT_SPEC.slotBudgets).toHaveLength(4);
  });
});
