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
  /**
   * v2 only (when `JudgeOptions.moves` is set): four raw move proposals
   * (index = slot). Untrusted: validated by the engine v3 validator.
   */
  moves?: unknown[];
}

/** What the AI needs to propose moves (GAME_DESIGN_V2 §5.5). */
export interface MovePromptContext {
  /** The character's attribute: gu / choki / pa. */
  attribute: string;
  /** Budget points per slot (already × the move factor). */
  slotBudgets: number[];
}

export interface JudgeOptions {
  /** Ask for four move proposals in the same call (V2_INFRA §2.3). */
  moves?: MovePromptContext;
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

/** What the AI needs to design one move for one slot (generateMove). */
export interface MoveSlotContext {
  /** The character's attribute: gu / choki / pa. */
  attribute: string;
  /** 0-based slot index (2 = the Lv10 slot, 3 = the Lv50 slot). */
  slot: number;
  /** Budget points of this slot (already × the move factor). */
  budget: number;
  /** Kana names of the character's other moves (validated by the caller). */
  otherNames: readonly string[];
}

export interface AiService {
  judgeDrawing(png: Buffer, opts?: JudgeOptions): Promise<DrawingJudgement>;
  moderateCharacter(png: Buffer, candidateNames: readonly string[]): Promise<ModerationVerdict>;
  /**
   * One raw move proposal for one slot (untrusted: validated by the engine v3
   * validator and moderated by the caller). Cost-gated (`cloudMoveGen`).
   */
  generateMove(png: Buffer, ctx: MoveSlotContext): Promise<Record<string, unknown>>;
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
