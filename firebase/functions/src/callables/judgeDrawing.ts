import { logger } from "firebase-functions/v2";
import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { AiRefusalError, AiUnavailableError, getAiService, type ImageConcern } from "../ai";
import { RATE_LIMITS } from "../config";
import { requireUserWithConsent } from "../lib/auth";
import { clock } from "../lib/clock";
import { ErrorCode, fail } from "../lib/errors";
import { decodePng } from "../lib/png";
import { consumeRateLimit } from "../lib/rateLimit";
import { parseInput } from "../lib/validation";
import { pickPresetNames } from "../names/presetNames";
import { sanitizeKanaText, sanitizeSubject } from "../names/validateName";
import { AI_CALLABLE } from "./options";

const Input = z.object({ imageBase64: z.string().max(1_000_000) }).strict();

export interface JudgeDrawingResponse {
  subject: string;
  suggestedNames: [string, string, string];
  moveNames: { element: string; special: string };
  skillEstimate: number;
  appropriate: boolean;
  reasons: ImageConcern[];
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
  const { imageBase64 } = parseInput(Input, req.data);
  const png = decodePng(imageBase64);
  await consumeRateLimit(uid, RATE_LIMITS.judgeDrawing);

  const started = clock.now();
  try {
    const j = await getAiService().judgeDrawing(png.bytes);
    const concerns = [...new Set(j.concerns)];
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
    };
    logger.info("judgeDrawing ok", { uid, w: png.width, h: png.height, ms: clock.now() - started, appropriate });
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
