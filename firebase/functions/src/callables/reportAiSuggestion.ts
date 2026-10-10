import { logger } from "firebase-functions/v2";
import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { RATE_LIMITS } from "../config";
import { requireUserWithConsent } from "../lib/auth";
import { clock } from "../lib/clock";
import { COL, db } from "../lib/firebase";
import { consumeRateLimit } from "../lib/rateLimit";
import { parseInput } from "../lib/validation";
import { BASE_CALLABLE } from "./options";

/** Which AI-suggested text is reported (Google Play AI-generated content policy). */
export const AI_SUGGESTION_KINDS = ["name", "element_move", "special_move", "subject"] as const;
/** Preset reasons (no free text). */
export const AI_REPORT_REASONS = ["mean", "scary", "strange", "other"] as const;

const Input = z
  .object({
    kind: z.enum(AI_SUGGESTION_KINDS),
    // AI suggestions are kana only, ≤ 12 characters (judgeDrawing sanitises them).
    text: z
      .string()
      .max(40)
      .transform((s) => s.normalize("NFKC").trim())
      .refine((s) => /^[ぁ-ゖァ-ヺー ]{1,12}$/u.test(s), "kana only"),
    reasonCode: z.enum(AI_REPORT_REASONS),
  })
  .strict();

export interface ReportAiSuggestionResponse {
  ok: true;
}

/**
 * reportAiSuggestion: a child flags a name / move name the AI suggested
 * (in-app reporting required by Google Play's AI-generated content policy).
 * Stored for human review in `aiSuggestionReports` (deleted by
 * deleteMyData); never shown to anybody else. Requires the cloud-judge
 * consent, because suggestions only exist with it.
 */
export async function reportAiSuggestionHandler(req: CallableRequest<unknown>): Promise<ReportAiSuggestionResponse> {
  const { uid } = await requireUserWithConsent(req, "cloudJudge");
  const { kind, text, reasonCode } = parseInput(Input, req.data);
  await consumeRateLimit(uid, RATE_LIMITS.reportAiSuggestion);
  await db().collection(COL.aiSuggestionReports).add({ uid, kind, text, reasonCode, state: "pending", atMs: clock.now() });
  logger.info("ai suggestion reported", { uid, kind, reasonCode });
  return { ok: true };
}

export const reportAiSuggestion = onCall(BASE_CALLABLE, reportAiSuggestionHandler);
