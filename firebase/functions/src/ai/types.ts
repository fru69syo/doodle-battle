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

/** Raw (unsanitised) judgement returned by the AI for judgeDrawing. */
export interface DrawingJudgement {
  subject: string;
  suggestedNames: string[];
  elementMoveName: string;
  specialMoveName: string;
  skillEstimate: number;
  appropriate: boolean;
  concerns: ImageConcern[];
}

/** Moderation verdict for registerCharacter. */
export interface ModerationVerdict {
  imageCategory: ImageCategory;
  isHandDrawn: boolean;
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
