import { createHash } from "node:crypto";
import { logger } from "firebase-functions/v2";
import type { CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { AiRefusalError, AiUnavailableError, getAiService } from "../ai";
import { LIMITS, RATE_LIMITS } from "../config";
import { requireUserWithConsent, type UserProfile } from "../lib/auth";
import { clock } from "../lib/clock";
import { ErrorCode, fail } from "../lib/errors";
import { bucket, COL, db, snapshotImagePath } from "../lib/firebase";
import { decodePng } from "../lib/png";
import { consumeRateLimit } from "../lib/rateLimit";
import { parseInput } from "../lib/validation";
import type { SnapshotDocV2 } from "../model";
import { randomDisplayName } from "../names/displayName";
import { canonicalName, checkCharacterName, sanitizeSubject } from "../names/validateName";
import { isClean, NG_WORDS_VERSION } from "../ngwords/ngFilter";
import { DEFAULT_SPEC, ENGINE_ID, EVOLUTIONS, validateCharacterClaimV2 } from "../vendor/battle_engine_v3";
import {
  IMAGE_REASON,
  MAX_ACTIVE_SNAPSHOTS,
  reject,
  SUSPECT_SKILL_GAP,
  type RejectionReason,
} from "./registerCharacter";

/** Max level of v2 characters (GAME_DESIGN_V2: Lv100). */
export const V2_MAX_LEVEL = DEFAULT_SPEC.maxLevel;

const Input = z
  .object({
    schema: z.literal(2),
    localCharacterId: z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/),
    imageBase64: z.string().max(1_000_000),
    name: z.string().min(1).max(40),
    level: z.number().int().min(1).max(V2_MAX_LEVEL),
    xp: z.number().int().min(0),
    features: z.record(z.string().max(40), z.number()).refine((f) => Object.keys(f).length <= 40),
    energy10: z.number().int(),
    skill10: z.number().int(),
    imageHash: z.string().max(80),
    verdict: z.string().max(20).optional(),
    stats: z.array(z.number().int()).length(10).optional(),
    moves: z.array(z.record(z.string(), z.unknown()).nullable()).max(4).default([]),
    rig: z.unknown().optional(),
    subject: z.string().max(40).optional(),
  })
  .strict();

export type RegisterCharacterV2Response =
  | { ok: true; snapshotId: string; name: string; moveNames: (string | null)[]; displayName: string }
  | { ok: false; reason: RejectionReason; presetNames?: string[] };

const ngCheck = (x: string) => !isClean(x);

/** Logs and returns a kid-friendly rejection (same codes as v1). */
async function no(uid: string, reason: RejectionReason): Promise<RegisterCharacterV2Response> {
  const r = await reject(uid, reason);
  return r.ok ? { ok: false, reason } : r;
}

/**
 * registerCharacter for v2 characters (engine v3): moderates the image and
 * the names, recomputes stats from the quantised features and level (the
 * client's numbers are only cross-checked), re-validates every AI move
 * proposal against its slot budget and keeps a valid rig blob. Fail-closed.
 * Nothing in the response depends on the hidden late-bloomer state.
 */
export async function registerCharacterV2Handler(req: CallableRequest<unknown>): Promise<RegisterCharacterV2Response> {
  const { uid, profile } = await requireUserWithConsent(req, "online");
  const input = parseInput(Input, req.data);
  const png = decodePng(input.imageBase64);
  await consumeRateLimit(uid, RATE_LIMITS.registerCharacter);

  if (input.level < LIMITS.onlineMinLevel) return no(uid, "LEVEL_TOO_LOW");
  const claim = {
    features: input.features,
    energy10: input.energy10,
    skill10: input.skill10,
    imageHash: input.imageHash,
    verdict: input.verdict ?? null,
    level: input.level,
    xp: input.xp,
    ...(input.stats ? { stats: input.stats } : {}),
    moves: input.moves,
  };
  const first = validateCharacterClaimV2(claim, { ngCheck, maxLevel: V2_MAX_LEVEL });
  if (!first.ok || !first.snapshot) {
    logger.warn("registerCharacterV2 claim invalid", { uid, problems: first.problems });
    return no(uid, "STATS_INVALID");
  }

  const name = canonicalName(input.name);
  const nameProblem = checkCharacterName(name);
  if (nameProblem?.kind === "invalid") return no(uid, "NAME_INVALID");
  if (nameProblem?.kind === "ng") {
    return no(uid, nameProblem.hit.category === "personal_info" ? "NAME_PERSONAL_INFO" : "NAME_NG");
  }
  const subject = input.subject ? sanitizeSubject(input.subject) : null;

  const active = await db()
    .collection(COL.snapshots)
    .where("ownerUid", "==", uid)
    .where("status", "==", "active")
    .select("localCharacterId")
    .get();
  const otherActive = active.docs.filter((d) => d.get("localCharacterId") !== input.localCharacterId).length;
  if (otherActive >= MAX_ACTIVE_SNAPSHOTS) return no(uid, "TOO_MANY_CHARACTERS");

  // AI moderation of the image, the name and every AI move name.
  const moveSlots = first.snapshot.proposals
    .map((p, slot) => ({ slot, name: typeof p?.name === "string" ? p.name : null }))
    .filter((m): m is { slot: number; name: string } => m.name !== null);
  let verdict;
  try {
    verdict = await getAiService().moderateCharacter(png.bytes, [name, ...moveSlots.map((m) => m.name)]);
  } catch (err) {
    if (err instanceof AiRefusalError) return no(uid, "IMAGE_OTHER");
    if (err instanceof AiUnavailableError) {
      logger.warn("registerCharacterV2 ai unavailable", { uid, message: err.message });
      fail(ErrorCode.AI_UNAVAILABLE, "review temporarily unavailable");
    }
    throw err;
  }
  if (verdict.imageCategory !== "ok") return no(uid, IMAGE_REASON[verdict.imageCategory]);
  // v2.0: AI-generated / digital pictures are accepted (internally weaker,
  // GAME_DESIGN_V2 §4.4); photos, prints and screens are still refused.
  if (verdict.origin === "photo_print_or_screen") return no(uid, "IMAGE_NOT_DRAWING");
  const nameVerdict = verdict.names[0];
  if (!nameVerdict?.ok || nameVerdict.category !== "ok") {
    return no(uid, nameVerdict?.category === "personal_info" ? "NAME_PERSONAL_INFO" : "NAME_NG");
  }
  const proposals = [...first.snapshot.proposals];
  moveSlots.forEach((m, i) => {
    const v = verdict.names[i + 1];
    if (!v?.ok || v.category !== "ok") proposals[m.slot] = null; // offline move instead
  });

  // Final, server-authoritative recomputation (the moderation verdict can
  // make the hidden form; the response never says so).
  const serverOrigin = verdict.origin === "ai_generated" ? "ai_generated" : null;
  const final = validateCharacterClaimV2(
    { ...claim, moves: proposals, rig: input.rig ?? null },
    { ngCheck, serverOrigin, maxLevel: V2_MAX_LEVEL },
  );
  if (!final.ok || !final.snapshot) return no(uid, "STATS_INVALID");
  const snap = final.snapshot;
  if (final.rigDropped) logger.info("registerCharacterV2 rig dropped", { uid, reason: final.rigDropped });
  logger.info("registerCharacterV2 moves", { uid, moves: final.moveLog });

  const displayName = profile.displayName ?? randomDisplayName();
  if (!profile.displayName) {
    await db().collection(COL.users).doc(uid).set({ displayName } satisfies UserProfile, { merge: true });
  }
  const aiSkill = Number.isFinite(verdict.skillEstimate)
    ? Math.min(100, Math.max(0, Math.round(verdict.skillEstimate)))
    : 50;
  const moveNames = snap.proposals.map((p) => (typeof p?.name === "string" ? p.name : null));
  const ref = db().collection(COL.snapshots).doc();
  const imagePath = snapshotImagePath(ref.id);
  const now = clock.now();
  let evolution: string | null = null;
  for (const [lv, id] of EVOLUTIONS) if (input.level >= lv) evolution = id;
  const doc: SnapshotDocV2 = {
    schema: 2,
    engineId: ENGINE_ID,
    ownerUid: uid,
    localCharacterId: input.localCharacterId,
    status: "active",
    name,
    moveNames,
    ownerDisplayName: displayName.text,
    attribute: snap.attribute,
    level: snap.level,
    xp: input.xp,
    stats: snap.stats,
    ratedStats: snap.rated.stats as number[],
    maxHp: snap.maxHp,
    evolution,
    subject,
    rig: snap.rig,
    engine: {
      features: snap.features,
      energy10: snap.energy10,
      skill10: snap.skill10,
      imageHash: snap.imageHash,
      trust: serverOrigin ?? (input.verdict ?? null),
      proposals: snap.proposals,
    },
    imagePath,
    imageSha256: createHash("sha256").update(png.bytes).digest("hex"),
    moderation: {
      aiSkillEstimate: aiSkill,
      suspectSkill: aiSkill - Math.round(input.skill10 / 10) >= SUSPECT_SKILL_GAP,
      ngWordsVersion: NG_WORDS_VERSION,
    },
    reportCount: 0,
    reportReasons: {},
    randomKey: Math.random(),
    createdAtMs: now,
  };
  const file = bucket().file(imagePath);
  await file.save(png.bytes, {
    contentType: "image/png",
    resumable: false,
    metadata: { cacheControl: "private, max-age=86400" },
  });
  try {
    await db().runTransaction(async (tx) => {
      const previous = await tx.get(
        db()
          .collection(COL.snapshots)
          .where("ownerUid", "==", uid)
          .where("localCharacterId", "==", input.localCharacterId)
          .where("status", "==", "active"),
      );
      for (const p of previous.docs) tx.update(p.ref, { status: "superseded", statusChangedAtMs: now });
      tx.create(ref, doc);
    });
  } catch (err) {
    await file.delete({ ignoreNotFound: true });
    throw err;
  }
  logger.info("registerCharacterV2 ok", { uid, snapshotId: ref.id });
  return { ok: true, snapshotId: ref.id, name, moveNames, displayName: displayName.text };
}
