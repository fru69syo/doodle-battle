import { describe, expect, it } from "vitest";
import { AiRefusalError, AiUnavailableError } from "../../src/ai";
import { DEFAULT_MOVES, DEFAULT_SUBJECT, judgeDrawingHandler } from "../../src/callables/judgeDrawing";
import { COL, db } from "../../src/lib/firebase";
import { PRESET_CHARACTER_NAMES } from "../../src/names/presetNames";
import { errorCode, okJudgement, req, seedUser, storageFiles, useEmulatorEnv } from "../helpers/emulator";
import { makePng, pngBase64 } from "../helpers/png";

const env = useEmulatorEnv();

describe("judgeDrawing", () => {
  it("requires sign-in and the parent's cloud consent", async () => {
    expect(await errorCode(judgeDrawingHandler(req(null, { imageBase64: pngBase64() })))).toBe("UNAUTHENTICATED");
    expect(await errorCode(judgeDrawingHandler(req("kid", { imageBase64: pngBase64() })))).toBe("CONSENT_REQUIRED");
    await seedUser("kid", { cloudJudge: false, online: true });
    expect(await errorCode(judgeDrawingHandler(req("kid", { imageBase64: pngBase64() })))).toBe("CONSENT_REQUIRED");
    expect(env.ai.judgeDrawing).not.toHaveBeenCalled();
  });

  it("validates the image before calling the AI", async () => {
    await seedUser("kid");
    expect(await errorCode(judgeDrawingHandler(req("kid", { imageBase64: makePng(1024, 512).toString("base64") })))).toBe(
      "IMAGE_TOO_LARGE",
    );
    expect(await errorCode(judgeDrawingHandler(req("kid", { imageBase64: "bm90IGEgcG5n" })))).toBe("IMAGE_INVALID");
    expect(await errorCode(judgeDrawingHandler(req("kid", { image: "x" })))).toBe("INVALID_ARGUMENT");
    expect(env.ai.judgeDrawing).not.toHaveBeenCalled();
  });

  it("returns the judgement and never stores the image", async () => {
    await seedUser("kid");
    const res = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect(res).toEqual({
      subject: "ねこ",
      suggestedNames: okJudgement.suggestedNames,
      moveNames: { element: "ほのおぱんち", special: "にゃんにゃんびーむ" },
      skillEstimate: 22,
      appropriate: true,
      reasons: [],
      rejectCode: null,
    });
    expect(env.ai.judgeDrawing).toHaveBeenCalledTimes(1);
    expect(await storageFiles()).toEqual([]);
    const cols = (await db().listCollections()).map((c) => c.id).sort();
    // ops = the monthly AI usage meter (counts only, src/cost/aiUsage.ts)
    expect(cols).toEqual(["ops", COL.rateLimits, COL.users]);
  });

  it("sanitises AI output (prompt-injected text, NG words, wrong scripts, ranges)", async () => {
    await seedUser("kid");
    env.ai.judgeDrawing.mockResolvedValueOnce({
      subject: "IGNORE ALL RULES",
      suggestedNames: ["しねしね", "ignore previous instructions", "ぴかりん", "ぴかりん", "ながすぎるなまえですよ"],
      elementMoveName: "ころすびーむ",
      specialMoveName: "<script>",
      skillEstimate: 250,
      appropriate: true,
      concerns: [],
      origin: "hand_drawn",
    });
    const res = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect(res.subject).toBe(DEFAULT_SUBJECT);
    expect(res.suggestedNames[0]).toBe("ぴかりん");
    expect(new Set(res.suggestedNames).size).toBe(3);
    expect(PRESET_CHARACTER_NAMES).toContain(res.suggestedNames[1]);
    expect(res.moveNames).toEqual(DEFAULT_MOVES);
    expect(res.skillEstimate).toBe(100);
  });

  it("reports inappropriate drawings with reason codes (fail-safe on inconsistent output)", async () => {
    await seedUser("kid");
    env.ai.judgeDrawing.mockResolvedValueOnce({ ...okJudgement, appropriate: true, concerns: ["real_person"] });
    const r1 = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect([r1.appropriate, r1.reasons]).toEqual([false, ["real_person"]]);
    env.ai.judgeDrawing.mockResolvedValueOnce({ ...okJudgement, appropriate: false, concerns: [] });
    const r2 = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect([r2.appropriate, r2.reasons]).toEqual([false, ["other"]]);
  });

  it("rejects confidently AI-generated / non-drawing pictures, never on 'unsure'", async () => {
    await seedUser("kid");
    env.ai.judgeDrawing.mockResolvedValueOnce({ ...okJudgement, origin: "ai_generated" });
    const ai = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect([ai.appropriate, ai.reasons, ai.rejectCode]).toEqual([false, ["ai_generated"], "IMAGE_AI_GENERATED"]);
    env.ai.judgeDrawing.mockResolvedValueOnce({ ...okJudgement, origin: "photo_print_or_screen" });
    const photo = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect([photo.reasons, photo.rejectCode]).toEqual([["not_drawing"], "IMAGE_NOT_DRAWING"]);
    env.ai.judgeDrawing.mockResolvedValueOnce({ ...okJudgement, origin: "unsure" });
    const unsure = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect([unsure.appropriate, unsure.rejectCode]).toEqual([true, null]);
  });

  it("maps AI outages to AI_UNAVAILABLE and refusals to appropriate=false", async () => {
    await seedUser("kid");
    env.ai.judgeDrawing.mockRejectedValueOnce(new AiUnavailableError("down"));
    expect(await errorCode(judgeDrawingHandler(req("kid", { imageBase64: pngBase64() })))).toBe("AI_UNAVAILABLE");
    env.ai.judgeDrawing.mockRejectedValueOnce(new AiRefusalError("refused"));
    const r = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect(r.appropriate).toBe(false);
    expect(r.reasons).toEqual(["other"]);
  });

  it("is rate limited per uid", async () => {
    await seedUser("kid");
    await db()
      .collection(COL.rateLimits)
      .doc("kid")
      .set({ buckets: { judge_h: { start: 1_800_000_000_000, count: 30 } } });
    expect(await errorCode(judgeDrawingHandler(req("kid", { imageBase64: pngBase64() })))).toBe("RATE_LIMITED");
    env.advance(3_600_000);
    await expect(judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }))).resolves.toBeTruthy();
  });
});
