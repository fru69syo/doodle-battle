import { logger } from "firebase-functions/v2";
import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import {
  AiRefusalError,
  AiUnavailableError,
  getAiService,
  originRejectCode,
  type ImageConcern,
  type JudgeRejectCode,
} from "../ai";
import { RATE_LIMITS } from "../config";
import { requireUserWithConsent } from "../lib/auth";
import { clock } from "../lib/clock";
import { ErrorCode, fail } from "../lib/errors";
import { decodePng } from "../lib/png";
import { consumeRateLimit } from "../lib/rateLimit";
import { parseInput } from "../lib/validation";
import { pickPresetNames } from "../names/presetNames";
import { sanitizeKanaText, sanitizeSubject } from "../names/validateName";
import { isClean } from "../ngwords/ngFilter";
import { DEFAULT_SPEC, moveContextOf, validateAiMoveSet } from "../vendor/battle_engine_v3";
import { AI_CALLABLE } from "./options";

/** v2 apps send the analyser's quantised output so the server can size the move proposals. */
export const V2DrawingInput = z
  .object({
    features: z.record(z.string().max(40), z.number().int()).refine((f) => Object.keys(f).length <= 40),
    energy10: z.number().int().min(0).max(1000),
    skill10: z.number().int().min(0).max(1000),
    imageHash: z.string().regex(/^[0-9a-f]{64}$/),
    /** Device trust verdict (digital / printed / screen), if any. */
    verdict: z.enum(["digital", "printed", "screen"]).optional(),
  })
  .strict();

const Input = z.object({ imageBase64: z.string().max(1_000_000), v2: V2DrawingInput.optional() }).strict();

export interface JudgeDrawingResponse {
  subject: string;
  suggestedNames: [string, string, string];
  moveNames: { element: string; special: string };
  skillEstimate: number;
  appropriate: boolean;
  /** `ai_generated` is added when the picture is not hand-drawn (see rejectCode). */
  reasons: (ImageConcern | "ai_generated")[];
  /**
   * Set when the judge is confident the picture is not a hand drawing on
   * paper (SPEC §11.1): the app asks for a new photo 「かみに かいた えを とってね」.
   */
  rejectCode: JudgeRejectCode | null;
  /**
   * v2 only: normalised AI move proposals per slot (null = use the offline
   * move). Numbers are already clamped / shrunk by the engine v3 validator;
   * the app re-validates them at every level.
   */
  moves?: (Record<string, unknown> | null)[];
}


export const DEFAULT_SUBJECT = "ふしぎな いきもの";
export const DEFAULT_MOVES = { element: "きらきらあたっく", special: "すーぱーびーむ" } as const;

function clampSkill(x: number): number {
  return Number.isFinite(x) ? Math.min(100, Math.max(0, Math.round(x))) : 50;
}

function threeNames(raw: readonly string[]): [string, string, string] {
  const names: string[] = [];
  for (const n of raw) {
    const s = sanitizeKanaText(n, 2, 8);
    if (s && !names.includes(s)) names.push(s);
    if (names.length === 3) break;
  }
  for (const p of pickPresetNames(6)) {
    if (names.length === 3) break;
    if (!names.includes(p)) names.push(p);
  }
  const [a = "", b = "", c = ""] = names;
  return [a, b, c];
}

/**
 * judgeDrawing: cloud judgement of a cut-out drawing (SPEC §3.3).
 * The image is only held in memory for the duration of the request.
 */
export async function judgeDrawingHandler(req: CallableRequest<unknown>): Promise<JudgeDrawingResponse> {
  const { uid } = await requireUserWithConsent(req, "cloudJudge");
  const { imageBase64, v2 } = parseInput(Input, req.data);
  const png = decodePng(imageBase64);
  await consumeRateLimit(uid, RATE_LIMITS.judgeDrawing);

  const started = clock.now();
  const ctx = v2 ? moveContextOf(v2) : null;
  try {
    const j = await getAiService().judgeDrawing(
      png.bytes,
      ctx ? { moves: { attribute: ctx.attribute, slotBudgets: ctx.slotBudgets } } : {},
    );
    // v2.0 (GAME_DESIGN_V2 §1): AI-generated / digital pictures are accepted
    // (internally weaker); only a confident photo/print/screen verdict refuses.
    const rejectCode = v2
      ? j.origin === "photo_print_or_screen"
        ? "IMAGE_NOT_DRAWING"
        : null
      : originRejectCode(j.origin);
    const concerns: JudgeDrawingResponse["reasons"] = [...new Set(j.concerns)];
    if (rejectCode === "IMAGE_AI_GENERATED") concerns.push("ai_generated");
    if (rejectCode === "IMAGE_NOT_DRAWING" && !concerns.includes("not_drawing")) concerns.push("not_drawing");
    const appropriate = j.appropriate && concerns.length === 0;
    const res: JudgeDrawingResponse = {
      subject: sanitizeSubject(j.subject) ?? DEFAULT_SUBJECT,
      suggestedNames: threeNames(j.suggestedNames),
      moveNames: {
        element: sanitizeKanaText(j.elementMoveName, 1, 10) ?? DEFAULT_MOVES.element,
        special: sanitizeKanaText(j.specialMoveName, 1, 10) ?? DEFAULT_MOVES.special,
      },
      skillEstimate: clampSkill(j.skillEstimate),
      appropriate,
      reasons: appropriate ? [] : concerns.length > 0 ? concerns : ["other"],
      rejectCode,
    };
    if (v2) {
      // Hidden-state aware context: the server's own ai_generated verdict
      // sizes the budgets exactly like registerCharacter will.
      const c2 =
        moveContextOf(v2, { serverOrigin: j.origin === "ai_generated" ? "ai_generated" : null }) ?? ctx;
      const checked = c2
        ? validateAiMoveSet(DEFAULT_SPEC, { moves: j.moves ?? [] }, {
            own: c2.attribute,
            moveFactorPct: c2.moveFactorPct,
            ngCheck: (x) => !isClean(x),
          })
        : [];
      res.moves = [0, 1, 2, 3].map((i) => checked[i]?.proposal ?? null);
      // Outcome codes only, never the generated text.
      logger.info("judgeDrawing moves", {
        uid,
        moves: checked.map((c) => (c.accepted ? `ok:${c.result.warnings.length}` : `x:${c.result.reason ?? ""}`)),
      });
    }
    logger.info("judgeDrawing ok", {
      uid,
      w: png.width,
      h: png.height,
      ms: clock.now() - started,
      appropriate,
      rejectCode,
    });
    return res;
  } catch (err) {
    if (err instanceof AiRefusalError) {
      logger.warn("judgeDrawing refusal", { uid, message: err.message });
      return {
        subject: DEFAULT_SUBJECT,
        suggestedNames: threeNames([]),
        moveNames: { ...DEFAULT_MOVES },
        skillEstimate: 50,
        appropriate: false,
        reasons: ["other"],
        rejectCode: null,
        ...(v2 ? { moves: [null, null, null, null] } : {}),
      };
    }
    if (err instanceof AiUnavailableError) {
      logger.warn("judgeDrawing ai unavailable", { uid, message: err.message });
      fail(ErrorCode.AI_UNAVAILABLE, "judge temporarily unavailable");
    }
    throw err;
  }
}

export const judgeDrawing = onCall(AI_CALLABLE, judgeDrawingHandler);
