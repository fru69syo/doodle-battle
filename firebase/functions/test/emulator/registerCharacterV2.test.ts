import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { judgeDrawingHandler } from "../../src/callables/judgeDrawing";
import { requireOwnActiveSnapshot, pickGhost } from "../../src/battle/matchmaking";
import { registerCharacterHandler } from "../../src/callables/registerCharacter";
import { COL, db } from "../../src/lib/firebase";
import type { SnapshotDocV2 } from "../../src/model";
import { DEFAULT_SPEC, Genome, parseFeatures, ratedFighterFromSnapshot } from "../../src/vendor/battle_engine_v3";
import { errorCode, okJudgement, req, seedUser, useEmulatorEnv } from "../helpers/emulator";
import { pngBase64 } from "../helpers/png";

const env = useEmulatorEnv();
const golden = JSON.parse(
  readFileSync(join(process.cwd(), "..", "..", "shared", "battle_spec_v3", "golden_vectors.json"), "utf8"),
) as { genomes: { input: { features: Record<string, number>; energy10: number; skill10: number } }[] };
const g0 = golden.genomes[0]!.input;
const hash = "ab".repeat(32);
const genome = new Genome(DEFAULT_SPEC, {
  features: parseFeatures(g0.features)!,
  energy10: g0.energy10,
  skill10: g0.skill10,
  imageHash: hash,
});
const v2 = { features: g0.features, energy10: g0.energy10, skill10: g0.skill10, imageHash: hash };

function input(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schema: 2,
    localCharacterId: "c2",
    imageBase64: pngBase64(),
    name: "ねこまる",
    level: 12,
    xp: 10,
    ...v2,
    moves: [{ template: "strike", attribute: genome.attr, name: "ねこパンチ", power: 200 }, null],
    rig: { v: 1, width: 100, height: 120, root: [50, 100], chest: [50, 60], limbs: [] },
    subject: "ねこ",
    ...over,
  };
}
const register = (over: Record<string, unknown> = {}, uid = "kid") =>
  registerCharacterHandler(req(uid, input(over)));

describe("registerCharacter (v2, engine v3)", () => {
  it("stores a server-computed snapshot the realtime server can field", async () => {
    await seedUser("kid");
    const res = await register({ stats: genome.statsAt(12) });
    expect(res).toMatchObject({ ok: true, name: "ねこまる" });
    if (!res.ok) return;
    expect(res.moveNames).toEqual(["ねこパンチ", null, null, null]);
    expect(JSON.stringify(res)).not.toMatch(/bloomer|trust|stats/i);
    const snap = (await db().collection(COL.snapshots).doc(res.snapshotId).get()).data() as SnapshotDocV2;
    expect(snap).toMatchObject({ schema: 2, status: "active", level: 12, attribute: genome.attr });
    expect(snap.stats).toEqual(genome.statsAt(12));
    expect(snap.ratedStats).toEqual(genome.statsAt(50));
    expect(snap.rig).toMatchObject({ v: 1 });
    expect(snap.engine.proposals[0]).toMatchObject({ template: "strike", name: "ねこパンチ" });
    expect(env.ai.moderateCharacter).toHaveBeenCalledWith(expect.any(Buffer), ["ねこまる", "ねこパンチ"]);
    const rated = ratedFighterFromSnapshot(snap.engine, snap.level)!;
    expect(rated.setup.stats).toEqual(genome.statsAt(50));
    expect(rated.setup.moves).toHaveLength(3);
    // The v1 turn-based matchmaking never fields v2 snapshots.
    expect(await errorCode(requireOwnActiveSnapshot("kid", res.snapshotId))).toBe("SNAPSHOT_NOT_ACTIVE");
    expect(await pickGhost("other", 12)).toBeNull();
  });

  it("rejects tampered stats and bad claims before calling the AI", async () => {
    await seedUser("kid");
    expect(await register({ stats: [999, 1, 1, 1, 1, 1, 1, 1, 1, 1] })).toEqual({ ok: false, reason: "STATS_INVALID" });
    expect(await register({ imageHash: "zz" })).toEqual({ ok: false, reason: "STATS_INVALID" });
    expect(await register({ level: 3 })).toEqual({ ok: false, reason: "LEVEL_TOO_LOW" });
    expect(await errorCode(register({ level: 101 }))).toBe("INVALID_ARGUMENT");
    expect(env.ai.moderateCharacter).not.toHaveBeenCalled();
  });

  it("accepts AI-generated pictures (hidden form) but refuses photos/prints", async () => {
    await seedUser("kid");
    env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
      imageCategory: "ok",
      isHandDrawn: false,
      origin: "ai_generated",
      names: names.map(() => ({ ok: true, category: "ok" as const })),
      skillEstimate: 95,
    }));
    const res = await register();
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    const snap = (await db().collection(COL.snapshots).doc(res.snapshotId).get()).data() as SnapshotDocV2;
    const sum = (x: number[]) => x.reduce((a, b) => a + b, 0);
    expect(sum(snap.stats)).toBeLessThan(sum(genome.statsAt(12)));
    env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
      imageCategory: "ok",
      isHandDrawn: false,
      origin: "photo_print_or_screen",
      names: names.map(() => ({ ok: true, category: "ok" as const })),
      skillEstimate: 95,
    }));
    expect(await register({ localCharacterId: "c3" })).toEqual({ ok: false, reason: "IMAGE_NOT_DRAWING" });
  });

  it("a move name the moderator refuses falls back to the offline move", async () => {
    await seedUser("kid");
    env.ai.moderateCharacter.mockImplementationOnce(async (_p, names) => ({
      imageCategory: "ok",
      isHandDrawn: true,
      origin: "hand_drawn",
      names: names.map((_, i) => (i === 1 ? { ok: false, category: "insult" as const } : { ok: true, category: "ok" as const })),
      skillEstimate: 20,
    }));
    const res = await register();
    expect(res).toMatchObject({ ok: true, moveNames: [null, null, null, null] });
  });
});

describe("judgeDrawing (v2: AI move proposals)", () => {
  it("returns validated move proposals and does not refuse AI-generated pictures", async () => {
    await seedUser("kid");
    env.ai.judgeDrawing.mockResolvedValueOnce({
      ...okJudgement,
      origin: "ai_generated",
      moves: [
        { template: "strike", attribute: genome.attr, name: "ねこパンチ", flavor: "", vfx: "punch", colour: "red", power: 999 },
        { template: "heal", attribute: "none", name: "Heal!", flavor: "", vfx: "hearts", colour: "pink", healPct: 40 },
        { template: "fireball", name: "ファイア" },
      ],
    });
    const res = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64(), v2 }));
    expect(res.rejectCode).toBeNull();
    expect(res.reasons).toEqual([]);
    expect(res.moves).toHaveLength(4);
    expect(res.moves![0]).toMatchObject({ template: "strike", name: "ねこパンチ" });
    expect((res.moves![0] as { power: number }).power).toBeLessThanOrEqual(200);
    expect(res.moves!.slice(1)).toEqual([null, null, null]);
    const opts = env.ai.judgeDrawing.mock.calls[0]![1];
    expect(opts?.moves?.attribute).toBe(genome.attr);
    expect(opts?.moves?.slotBudgets).toHaveLength(4);
  });

  it("v1 requests keep the v1 response and rejection rules", async () => {
    await seedUser("kid");
    env.ai.judgeDrawing.mockResolvedValueOnce({ ...okJudgement, origin: "ai_generated" });
    const res = await judgeDrawingHandler(req("kid", { imageBase64: pngBase64() }));
    expect(res.rejectCode).toBe("IMAGE_AI_GENERATED");
    expect(res).not.toHaveProperty("moves");
  });
});
