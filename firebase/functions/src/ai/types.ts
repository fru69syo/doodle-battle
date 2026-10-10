export const IMAGE_CATEGORIES = [
  "ok",
  "violence",
  "sexual",
  "hate",
  "copyright",
  "real_person",
  "personal_info",
  "not_drawing",
  "other",
] as const;
export type ImageCategory = (typeof IMAGE_CATEGORIES)[number];
export type ImageConcern = Exclude<ImageCategory, "ok">;
export const IMAGE_CONCERNS = IMAGE_CATEGORIES.filter((c): c is ImageConcern => c !== "ok");

export const NAME_CATEGORIES = [
  "ok",
  "insult",
  "sexual",
  "violence",
  "hate",
  "personal_info",
  "copyright",
  "other",
] as const;
export type NameCategory = (typeof NAME_CATEGORIES)[number];

/**
 * Where the picture comes from (SPEC §11.1). Only a confident
 * `ai_generated` / `photo_print_or_screen` rejects; `unsure` never does, so
 * real children's drawings are not refused on a hunch.
 */
export const IMAGE_ORIGINS = ["hand_drawn", "unsure", "ai_generated", "photo_print_or_screen"] as const;
export type ImageOrigin = (typeof IMAGE_ORIGINS)[number];

export type JudgeRejectCode = "IMAGE_AI_GENERATED" | "IMAGE_NOT_DRAWING";

/** Only confident verdicts reject; `unsure` and `hand_drawn` never do. */
export function originRejectCode(origin: ImageOrigin | undefined): JudgeRejectCode | null {
  if (origin === "ai_generated") return "IMAGE_AI_GENERATED";
  if (origin === "photo_print_or_screen") return "IMAGE_NOT_DRAWING";
  return null;
}

/** Raw (unsanitised) judgement returned by the AI for judgeDrawing. */
export interface DrawingJudgement {
  subject: string;
  suggestedNames: string[];
  elementMoveName: string;
  specialMoveName: string;
  skillEstimate: number;
  appropriate: boolean;
  concerns: ImageConcern[];
  /** AI-generated / digital vs. hand-drawn on paper. */
  origin: ImageOrigin;
}

/** Moderation verdict for registerCharacter. */
export interface ModerationVerdict {
  imageCategory: ImageCategory;
  isHandDrawn: boolean;
  /** AI-generated / digital vs. hand-drawn on paper. */
  origin: ImageOrigin;
  /** One verdict per candidate name, same order as the request. */
  names: { ok: boolean; category: NameCategory }[];
  skillEstimate: number;
}

export interface AiService {
  judgeDrawing(png: Buffer): Promise<DrawingJudgement>;
  moderateCharacter(png: Buffer, candidateNames: readonly string[]): Promise<ModerationVerdict>;
}

/** The AI could not produce a usable answer (network, quota, bad output). */
export class AiUnavailableError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options);
    this.name = "AiUnavailableError";
  }
}

/** The model declined to process the request (stop_reason "refusal"). */
export class AiRefusalError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AiRefusalError";
  }
}
