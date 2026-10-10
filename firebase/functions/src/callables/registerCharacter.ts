import { createHash } from "node:crypto";
import { logger } from "firebase-functions/v2";
import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { AiRefusalError, AiUnavailableError, getAiService, originRejectCode, type ImageCategory } from "../ai";
import { LIMITS, RATE_LIMITS } from "../config";
import { requireUserWithConsent, type UserProfile } from "../lib/auth";
import { clock } from "../lib/clock";
import { ErrorCode, fail } from "../lib/errors";
import { bucket, COL, db, snapshotImagePath } from "../lib/firebase";
import { decodePng } from "../lib/png";
import { consumeRateLimit } from "../lib/rateLimit";
import { parseInput } from "../lib/validation";
import type { SnapshotDoc } from "../model";
import { randomDisplayName } from "../names/displayName";
import { pickPresetNames } from "../names/presetNames";
import { canonicalName, checkCharacterName, sanitizeKanaText, sanitizeSubject } from "../names/validateName";
import { NG_WORDS_VERSION } from "../ngwords/ngFilter";
import {
  effectiveStats,
  ELEMENTS,
  evolutionStage,
  isShobo,
  STAT_KEYS,
  validateStatClaim,
  type Stats,
} from "../stats/statLimits";
import { AI_CALLABLE } from "./options";

const StatValue = z.number().int().min(0).max(100_000);
const StatsSchema = z.object({ hp: StatValue, atk: StatValue, def: StatValue, spd: StatValue }).strict();

const Input = z
  .object({
    localCharacterId: z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/),
    imageBase64: z.string().max(1_000_000),
    name: z.string().min(1).max(40),
    element: z.enum(ELEMENTS),
    baseStats: StatsSchema,
    energy: z.number().min(0).max(100),
    skill: z.number().min(0).max(100),
    level: z.number().int().min(1).max(LIMITS.maxLevel),
    xp: z.number().int().min(0),
    seedAllocations: z.partialRecord(z.enum(STAT_KEYS), z.number().int().min(0).max(LIMITS.maxLevel)).default({}),
    features: z
      .record(z.string().max(40), z.number())
      .refine((f) => Object.keys(f).length <= 40 && Object.values(f).every(Number.isFinite))
      .default({}),
    subject: z.string().max(40).optional(),
    moveNames: z
      .object({ element: z.string().max(40).optional(), special: z.string().max(40).optional() })
      .strict()
      .optional(),
  })
  .strict();

/** Kid-friendly rejection reason codes (the app maps them to messages). */
export const REJECTION_REASONS = [
  "LEVEL_TOO_LOW",
  "STATS_INVALID",
  "NAME_INVALID",
  "NAME_NG",
  "NAME_PERSONAL_INFO",
  "IMAGE_VIOLENCE",
  "IMAGE_SEXUAL",
  "IMAGE_HATE",
  "IMAGE_COPYRIGHT",
  "IMAGE_REAL_PERSON",
  "IMAGE_PERSONAL_INFO",
  "IMAGE_NOT_DRAWING",
  "IMAGE_AI_GENERATED",
  "IMAGE_OTHER",
  "TOO_MANY_CHARACTERS",
] as const;
export type RejectionReason = (typeof REJECTION_REASONS)[number];

const IMAGE_REASON: Record<Exclude<ImageCategory, "ok">, RejectionReason> = {
  violence: "IMAGE_VIOLENCE",
  sexual: "IMAGE_SEXUAL",
  hate: "IMAGE_HATE",
  copyright: "IMAGE_COPYRIGHT",
  real_person: "IMAGE_REAL_PERSON",
  personal_info: "IMAGE_PERSONAL_INFO",
  not_drawing: "IMAGE_NOT_DRAWING",
  other: "IMAGE_OTHER",
};

export const MAX_ACTIVE_SNAPSHOTS = 40;
/** AI skill estimate this far above the claimed skill flags the snapshot for review. */
export const SUSPECT_SKILL_GAP = 50;

export type RegisterCharacterResponse =
  | {
      ok: true;
      snapshotId: string;
      name: string;
      moveNames: { element: string | null; special: string | null };
      displayName: string;
    }
  | { ok: false; reason: RejectionReason; presetNames?: string[] };

async function reject(
  uid: string,
  reason: RejectionReason,
  extra: Record<string, unknown> = {},
): Promise<RegisterCharacterResponse> {
  // Only the reason code is logged: never the image or the rejected text.
  await db().collection(COL.moderationLog).add({ uid, kind: "register_rejected", reason, atMs: clock.now() });
  logger.info("registerCharacter rejected", { uid, reason });
  const presetNames = reason.startsWith("NAME_") ? pickPresetNames(3) : undefined;
  return { ok: false, reason, ...(presetNames ? { presetNames } : {}), ...extra };
}

/**
 * registerCharacter: moderates a character and stores it as an immutable
 * online snapshot (SPEC §5). Fail-closed: nothing is stored unless the
 * image and the name passed every check.
 */
export async function registerCharacterHandler(req: CallableRequest<unknown>): Promise<RegisterCharacterResponse> {
  const { uid, profile } = await requireUserWithConsent(req, "online");
  const input = parseInput(Input, req.data);
  const png = decodePng(input.imageBase64);
  await consumeRateLimit(uid, RATE_LIMITS.registerCharacter);

  // 1. Level gate and stat plausibility (anti-tamper).
  if (input.level < LIMITS.onlineMinLevel) return reject(uid, "LEVEL_TOO_LOW");
  const seeds = input.seedAllocations as Partial<Stats>;
  const problems = validateStatClaim({ ...input, seedAllocations: seeds });
  if (problems.length > 0) {
    logger.warn("registerCharacter stats invalid", { uid, problems });
    return reject(uid, "STATS_INVALID");
  }

  // 2. Name: charset/length, then NG dictionary (cheap, before the AI call).
  const name = canonicalName(input.name);
  const nameProblem = checkCharacterName(name);
  if (nameProblem?.kind === "invalid") return reject(uid, "NAME_INVALID");
  if (nameProblem?.kind === "ng") {
    return reject(uid, nameProblem.hit.category === "personal_info" ? "NAME_PERSONAL_INFO" : "NAME_NG");
  }
  const moveCandidates = {
    element: input.moveNames?.element ? sanitizeKanaText(input.moveNames.element, 1, 10) : null,
    special: input.moveNames?.special ? sanitizeKanaText(input.moveNames.special, 1, 10) : null,
  };
  const subject = input.subject ? sanitizeSubject(input.subject) : null;

  const active = await db()
    .collection(COL.snapshots)
    .where("ownerUid", "==", uid)
    .where("status", "==", "active")
    .select("localCharacterId")
    .get();
  const otherActive = active.docs.filter((d) => d.get("localCharacterId") !== input.localCharacterId).length;
  if (otherActive >= MAX_ACTIVE_SNAPSHOTS) return reject(uid, "TOO_MANY_CHARACTERS");

  // 3. AI moderation of image + name (+ move names).
  const candidates = [name, moveCandidates.element, moveCandidates.special].filter(
    (s): s is string => s !== null,
  );
  let verdict;
  try {
    verdict = await getAiService().moderateCharacter(png.bytes, candidates);
  } catch (err) {
    if (err instanceof AiRefusalError) return reject(uid, "IMAGE_OTHER");
    if (err instanceof AiUnavailableError) {
      logger.warn("registerCharacter ai unavailable", { uid, message: err.message });
      fail(ErrorCode.AI_UNAVAILABLE, "review temporarily unavailable");
    }
    throw err;
  }
  if (verdict.imageCategory !== "ok") return reject(uid, IMAGE_REASON[verdict.imageCategory]);
  // SPEC §11.1: AI-generated / digital pictures are refused (a confident
  // verdict only; `unsure` falls through to the hand-drawn check).
  const originCode = originRejectCode(verdict.origin);
  if (originCode) return reject(uid, originCode);
  if (!verdict.isHandDrawn) return reject(uid, "IMAGE_NOT_DRAWING");
  const nameVerdict = verdict.names[0];
  if (!nameVerdict?.ok || nameVerdict.category !== "ok") {
    return reject(uid, nameVerdict?.category === "personal_info" ? "NAME_PERSONAL_INFO" : "NAME_NG");
  }
  let idx = 1;
  const moveNames = { element: null as string | null, special: null as string | null };
  for (const key of ["element", "special"] as const) {
    const m = moveCandidates[key];
    if (m === null) continue;
    const v = verdict.names[idx++];
    moveNames[key] = v?.ok && v.category === "ok" ? m : null;
  }

  // 4. Persist: Storage image + immutable Firestore snapshot.
  const displayName = profile.displayName ?? randomDisplayName();
  if (!profile.displayName) {
    await db().collection(COL.users).doc(uid).set({ displayName } satisfies UserProfile, { merge: true });
  }
  const aiSkill = Number.isFinite(verdict.skillEstimate)
    ? Math.min(100, Math.max(0, Math.round(verdict.skillEstimate)))
    : 50;
  const ref = db().collection(COL.snapshots).doc();
  const imagePath = snapshotImagePath(ref.id);
  const now = clock.now();
  const doc: SnapshotDoc = {
    ownerUid: uid,
    localCharacterId: input.localCharacterId,
    status: "active",
    name,
    moveNames,
    ownerDisplayName: displayName.text,
    element: input.element,
    baseStats: input.baseStats,
    stats: effectiveStats(input.baseStats, input.level, seeds, isShobo(input.skill)),
    energy: input.energy,
    skill: input.skill,
    isShobo: isShobo(input.skill),
    level: input.level,
    xp: input.xp,
    seedAllocations: seeds,
    evolution: evolutionStage(input.level),
    subject,
    features: input.features,
    imagePath,
    imageSha256: createHash("sha256").update(png.bytes).digest("hex"),
    moderation: {
      aiSkillEstimate: aiSkill,
      suspectSkill: aiSkill - input.skill >= SUSPECT_SKILL_GAP,
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
  logger.info("registerCharacter ok", { uid, snapshotId: ref.id, suspectSkill: doc.moderation.suspectSkill });
  return { ok: true, snapshotId: ref.id, name, moveNames, displayName: displayName.text };
}

export const registerCharacter = onCall(AI_CALLABLE, registerCharacterHandler);
