import { describe, expect, it } from "vitest";
import { AiRefusalError, AiUnavailableError } from "../../src/ai";
import { registerCharacterHandler } from "../../src/callables/registerCharacter";
import { bucket, COL, db, snapshotImagePath } from "../../src/lib/firebase";
import type { SnapshotDoc } from "../../src/model";
import { errorCode, registerInput, req, seedUser, storageFiles, useEmulatorEnv } from "../helpers/emulator";
import { makePng } from "../helpers/png";

const env = useEmulatorEnv();

async function register(over: Record<string, unknown> = {}, uid = "kid") {
  return registerCharacterHandler(req(uid, registerInput(over)));
}

describe("registerCharacter", () => {
  it("requires online consent", async () => {
    await seedUser("kid", { cloudJudge: true, online: false });
    expect(await errorCode(register())).toBe("CONSENT_REQUIRED");
  });

  it("stores an immutable snapshot (Firestore + Storage) after moderation", async () => {
    await seedUser("kid");
    const res = await register();
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.name).toBe("ねこまる");
    expect(res.moveNames).toEqual({ element: "ほのおぱんち", special: "にゃんびーむ" });
    expect(res.displayName).toMatch(/^\S+ \S+$/);

    const snap = (await db().collection(COL.snapshots).doc(res.snapshotId).get()).data() as SnapshotDoc;
    expect(snap).toMatchObject({
      ownerUid: "kid",
      status: "active",
      level: 6,
      isShobo: false,
      evolution: "normal",
      stats: { hp: 108, atk: 103, def: 78, spd: 78 },
      imagePath: snapshotImagePath(res.snapshotId),
      reportCount: 0,
    });
    expect(await storageFiles()).toEqual([snapshotImagePath(res.snapshotId)]);
    const [meta] = await bucket().file(snap.imagePath).getMetadata();
    expect(meta.contentType).toBe("image/png");
    const user = (await db().collection(COL.users).doc("kid").get()).data();
    expect(user?.displayName?.text).toBe(res.displayName);

    // The AI saw the image and all three names as data.
    expect(env.ai.moderateCharacter).toHaveBeenCalledWith(expect.any(Buffer), ["ねこまる", "ほのおぱんち", "にゃんびーむ"]);
  });

  it("rejects low levels and tampered stats without calling the AI", async () => {
    await seedUser("kid");
    expect(await register({ level: 4, xp: 0, seedAllocations: {} })).toEqual({ ok: false, reason: "LEVEL_TOO_LOW" });
    expect(await register({ baseStats: { hp: 200, atk: 200, def: 200, spd: 200 } })).toEqual({
      ok: false,
      reason: "STATS_INVALID",
    });
    expect(await register({ skill: 90 })).toEqual({ ok: false, reason: "STATS_INVALID" });
    expect(env.ai.moderateCharacter).not.toHaveBeenCalled();
    const log = await db().collection(COL.moderationLog).get();
    expect(log.size).toBe(3);
    expect(Object.keys(log.docs[0]!.data()).sort()).toEqual(["atMs", "kind", "reason", "uid"]);
  });

  it("rejects NG / personal-info / malformed names with preset suggestions", async () => {
    await seedUser("kid");
    const ng = await register({ name: "シネシネ" });
    expect(ng).toMatchObject({ ok: false, reason: "NAME_NG" });
    expect(!ng.ok && ng.presetNames).toHaveLength(3);
    expect(await register({ name: "じゅうしょ" })).toMatchObject({ reason: "NAME_PERSONAL_INFO" });
    expect(await register({ name: "09012345678" })).toMatchObject({ reason: "NAME_INVALID" });
    expect(await register({ name: "ねこ😀" })).toMatchObject({ reason: "NAME_INVALID" });
    expect(await register({ name: "ｂ１ｔｃｈ" })).toMatchObject({ reason: "NAME_NG" });
    expect(env.ai.moderateCharacter).not.toHaveBeenCalled();
  });

  it("maps AI image verdicts to kid-friendly reason codes", async () => {
    await seedUser("kid");
    const cases = [
      ["real_person", "IMAGE_REAL_PERSON"],
      ["violence", "IMAGE_VIOLENCE"],
      ["sexual", "IMAGE_SEXUAL"],
      ["hate", "IMAGE_HATE"],
      ["copyright", "IMAGE_COPYRIGHT"],
      ["personal_info", "IMAGE_PERSONAL_INFO"],
      ["not_drawing", "IMAGE_NOT_DRAWING"],
      ["other", "IMAGE_OTHER"],
    ] as const;
    for (const [category, reason] of cases) {
      env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
        imageCategory: category,
        isHandDrawn: true,
        origin: "hand_drawn" as const,
        names: names.map(() => ({ ok: true, category: "ok" as const })),
        skillEstimate: 20,
      }));
      expect(await register()).toEqual({ ok: false, reason });
    }
    env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
      imageCategory: "ok",
      isHandDrawn: false,
      origin: "unsure" as const,
      names: names.map(() => ({ ok: true, category: "ok" as const })),
      skillEstimate: 95,
    }));
    expect(await register()).toEqual({ ok: false, reason: "IMAGE_NOT_DRAWING" });
    expect(await storageFiles()).toEqual([]);
    expect((await db().collection(COL.snapshots).get()).size).toBe(0);
  });

  it("refuses confidently AI-generated / non-drawing pictures (SPEC §11.1)", async () => {
    await seedUser("kid");
    env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
      imageCategory: "ok",
      isHandDrawn: false,
      origin: "ai_generated" as const,
      names: names.map(() => ({ ok: true, category: "ok" as const })),
      skillEstimate: 95,
    }));
    expect(await register()).toEqual({ ok: false, reason: "IMAGE_AI_GENERATED" });
    env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
      imageCategory: "ok",
      isHandDrawn: true,
      origin: "photo_print_or_screen" as const,
      names: names.map(() => ({ ok: true, category: "ok" as const })),
      skillEstimate: 95,
    }));
    expect(await register()).toEqual({ ok: false, reason: "IMAGE_NOT_DRAWING" });
    expect(await storageFiles()).toEqual([]);
  });

  it("rejects names the AI flags; drops flagged move names", async () => {
    await seedUser("kid");
    env.ai.moderateCharacter.mockImplementationOnce(async () => ({
      imageCategory: "ok",
      isHandDrawn: true,
      origin: "hand_drawn" as const,
      names: [{ ok: false, category: "personal_info" }, { ok: true, category: "ok" }, { ok: true, category: "ok" }],
      skillEstimate: 20,
    }));
    expect(await register({ name: "たなかたろう" })).toMatchObject({ ok: false, reason: "NAME_PERSONAL_INFO" });

    env.ai.moderateCharacter.mockImplementationOnce(async () => ({
      imageCategory: "ok",
      isHandDrawn: true,
      origin: "hand_drawn" as const,
      names: [{ ok: true, category: "ok" }, { ok: false, category: "insult" }, { ok: true, category: "ok" }],
      skillEstimate: 20,
    }));
    const res = await register();
    expect(res.ok && res.moveNames).toEqual({ element: null, special: "にゃんびーむ" });
  });

  it("fails closed when the AI is unavailable; refusals are rejections", async () => {
    await seedUser("kid");
    env.ai.moderateCharacter.mockRejectedValueOnce(new AiUnavailableError("down"));
    expect(await errorCode(register())).toBe("AI_UNAVAILABLE");
    env.ai.moderateCharacter.mockRejectedValueOnce(new AiRefusalError("no"));
    expect(await register()).toEqual({ ok: false, reason: "IMAGE_OTHER" });
    expect((await db().collection(COL.snapshots).get()).size).toBe(0);
  });

  it("supersedes the previous snapshot of the same local character", async () => {
    await seedUser("kid");
    const first = await register();
    const second = await register({ level: 7, xp: 0 });
    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    const a = (await db().collection(COL.snapshots).doc(first.snapshotId).get()).data() as SnapshotDoc;
    const b = (await db().collection(COL.snapshots).doc(second.snapshotId).get()).data() as SnapshotDoc;
    expect([a.status, b.status]).toEqual(["superseded", "active"]);
  });

  it("flags suspiciously skilled drawings for review", async () => {
    await seedUser("kid");
    env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
      imageCategory: "ok",
      isHandDrawn: true,
      origin: "hand_drawn" as const,
      names: names.map(() => ({ ok: true, category: "ok" as const })),
      skillEstimate: 90,
    }));
    const res = await register({ skill: 10 });
    if (!res.ok) throw new Error("expected ok");
    const s = (await db().collection(COL.snapshots).doc(res.snapshotId).get()).data() as SnapshotDoc;
    expect(s.moderation).toMatchObject({ aiSkillEstimate: 90, suspectSkill: true });
  });

  it("validates input shape and image", async () => {
    await seedUser("kid");
    expect(await errorCode(register({ element: "plasma" }))).toBe("INVALID_ARGUMENT");
    expect(await errorCode(register({ extra: 1 }))).toBe("INVALID_ARGUMENT");
    expect(await errorCode(register({ imageBase64: makePng(600, 600).toString("base64") }))).toBe("IMAGE_TOO_LARGE");
  });

  it("is rate limited", async () => {
    await seedUser("kid");
    for (let i = 0; i < 10; i++) await register({ level: 4, xp: 0, seedAllocations: {} });
    expect(await errorCode(register())).toBe("RATE_LIMITED");
    env.advance(3_600_001);
    expect((await register()).ok).toBe(true);
  });
});
