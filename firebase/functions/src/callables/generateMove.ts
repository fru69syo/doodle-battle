import { logger } from "firebase-functions/v2";
import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { getAiService } from "../ai";
import { RATE_LIMITS } from "../config";
import { getCostMode } from "../cost/costMode";
import { requireUserWithConsent } from "../lib/auth";
import { ErrorCode, fail } from "../lib/errors";
import { decodePng } from "../lib/png";
import { consumeRateLimit } from "../lib/rateLimit";
import { parseInput } from "../lib/validation";
import { isClean } from "../ngwords/ngFilter";
import {
  DEFAULT_SPEC,
  moveContextOf,
  moveToJson,
  unlockedSlots,
  validateAiMove,
} from "../vendor/battle_engine_v3";
import { AI_CALLABLE } from "./options";
import { seedImageHash } from "./registerCharacterV2";

const KANA_NAME = /^[ぁ-ゖァ-ヺー]{1,10}$/;

const Input = z
  .object({
    /** The character's cut-out PNG (context for the AI and for the name moderation). */
    imageBase64: z.string().max(1_000_000),
    features: z.record(z.string().max(40), z.number().int()).refine((f) => Object.keys(f).length <= 40),
    energy10: z.number().int().min(0).max(1000),
    skill10: z.number().int().min(0).max(1000),
    /** Accepted for symmetry with registerCharacter; budgets do not depend on it. */
    imageHash: z.string().max(80).optional(),
    /** The device's trust verdict, as stored in the local character (budgets only). */
    verdict: z.enum(["digital", "printed", "screen", "ai_generated"]).optional(),
    level: z.number().int().min(1).max(DEFAULT_SPEC.maxLevel),
    /**
     * 0-based slot, any slot unlocked at `level` (2 = the Lv10 slot, 3 = the Lv50 slot). The
     * same rule for every character: at the Lv50 evolution the app may ask for slots 0-3
     * (docs/BACKEND.md §5 generateMove), and nothing here depends on why it asks.
     */
    slot: z.number().int().min(0).max(3),
    /** Names of the other moves (kana, 1-10 chars): the new name must differ. */
    otherNames: z.array(z.string().regex(KANA_NAME)).max(3).default([]),
  })
  .strict();

/**
 * Why the template move is used instead of an AI move (logged, also returned so the app can
 * decide whether to ask again later; never shown to children).
 */
export type GenerateMoveFallback = "cost_mode" | "ai_unavailable" | "rejected" | "duplicate" | "moderation";

export type GenerateMoveResponse =
  | { slot: number; source: "ai"; proposal: Record<string, unknown> }
  | { slot: number; source: "template"; proposal: null; reason: GenerateMoveFallback };

const ngCheck = (x: string) => !isClean(x);

/**
 * generateMove: when a character reaches Lv10 / Lv50 the app may ask Claude for the new slot's
 * move (name, flavour, template and enums; docs/BACKEND.md §5). The answer is validated by the
 * engine v3 validator against the slot budget, the name is moderated, and on ANY failure the
 * app keeps its deterministic template move (`proposal: null`). Optional and cost-gated: in the
 * saving / minimal cost modes no AI is called at all.
 *
 * Hidden state: budgets come only from what the device sent (its own verdict), never from a
 * server-side verdict, so the response cannot reveal anything the device does not already know.
 */
export async function generateMoveHandler(req: CallableRequest<unknown>): Promise<GenerateMoveResponse> {
  const { uid } = await requireUserWithConsent(req, "cloudJudge");
  const input = parseInput(Input, req.data);
  const png = decodePng(input.imageBase64);
  if (input.slot >= unlockedSlots(DEFAULT_SPEC, input.level)) {
    fail(ErrorCode.INVALID_ARGUMENT, `slot ${input.slot + 1} is not unlocked at Lv${input.level}`);
  }
  const ctx = moveContextOf(
    { ...input, imageHash: seedImageHash(png.bytes), verdict: input.verdict ?? null },
    { level: input.level },
  );
  if (!ctx) fail(ErrorCode.INVALID_ARGUMENT, "invalid character data");
  await consumeRateLimit(uid, RATE_LIMITS.generateMove);

  const slot = input.slot;
  const template = (reason: GenerateMoveFallback): GenerateMoveResponse => {
    logger.info("generateMove template", { uid, slot, reason });
    return { slot, source: "template", proposal: null, reason };
  };
  // Cheap early exit (the AI service gate would refuse too).
  if (!(await getCostMode()).flags.cloudMoveGen) return template("cost_mode");

  const ai = getAiService();
  let raw: Record<string, unknown>;
  try {
    raw = await ai.generateMove(png.bytes, {
      attribute: ctx.attribute,
      slot,
      budget: ctx.slotBudgets[slot] ?? 0,
      maxBars: ctx.maxBars,
      barBudgets: ctx.barBudgets,
      otherNames: input.otherNames,
    });
  } catch (err) {
    logger.warn("generateMove ai failed", { uid, message: err instanceof Error ? err.message : String(err) });
    return template("ai_unavailable");
  }

  const v = validateAiMove(DEFAULT_SPEC, raw, { slot, own: ctx.attribute, moveFactorPct: ctx.moveFactorPct, maxBars: ctx.maxBars, ngCheck });
  if (v.rejected || !v.move) {
    logger.info("generateMove rejected", { uid, slot, reason: v.reason });
    return template("rejected");
  }
  let move = v.move;
  if (input.otherNames.includes(move.name)) return template("duplicate");

  // Moderation of the generated words (never cost-gated; fails closed to the template move).
  const words = move.flavor ? [move.name, move.flavor] : [move.name];
  try {
    const verdict = await ai.moderateCharacter(png.bytes, words);
    const ok = (i: number) => {
      const n = verdict.names[i];
      return n !== undefined && n.ok && n.category === "ok";
    };
    if (!ok(0)) return template("moderation");
    if (words.length > 1 && !ok(1)) move = { ...move, flavor: "" };
  } catch (err) {
    logger.warn("generateMove moderation failed", { uid, message: err instanceof Error ? err.message : String(err) });
    return template("moderation");
  }

  logger.info("generateMove ok", { uid, slot, warnings: v.warnings.length, template: move.template });
  return { slot, source: "ai", proposal: moveToJson(move) };
}

export const generateMove = onCall(AI_CALLABLE, generateMoveHandler);
