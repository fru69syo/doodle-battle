import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import {
  AiRefusalError,
  AiUnavailableError,
  IMAGE_CATEGORIES,
  IMAGE_CONCERNS,
  IMAGE_ORIGINS,
  NAME_CATEGORIES,
  type AiService,
  type DrawingJudgement,
  type JudgeOptions,
  type ModerationVerdict,
  type MoveSlotContext,
} from "./types";
import {
  JUDGE_SYSTEM_PROMPT,
  JUDGE_USER_TEXT,
  MODERATION_SYSTEM_PROMPT,
  MOVE_SYSTEM_PROMPT,
  moderationUserText,
  moveSlotUserText,
  movesUserText,
} from "./prompts";

/**
 * Output schemas. Length/range limits are deliberately NOT encoded here:
 * structured outputs only enforce a subset of JSON Schema, and the server
 * sanitises every field afterwards anyway (fail-safe rather than fail-parse).
 */
const JudgeSchema = z.object({
  subject: z.string().describe("hiragana word for what the drawing shows"),
  suggestedNames: z.array(z.string()).describe("exactly 3 names, hiragana/katakana, 2-8 chars"),
  elementMoveName: z.string(),
  specialMoveName: z.string(),
  skillEstimate: z.number().describe("integer 0-100"),
  appropriate: z.boolean(),
  concerns: z.array(z.enum(IMAGE_CONCERNS as [string, ...string[]])),
  origin: z.enum(IMAGE_ORIGINS),
});

const Num = z.number().nullable();
const StatEnum = z.enum(["STR", "DEF", "INT", "RES", "AGI", "DEX", "LUK"]).nullable();
/** One AI move proposal (GAME_DESIGN_V2 §5.5; shared/battle_spec_v3/ai_moves.schema.json). */
const AiMoveSchema = z.object({
  template: z.enum(["strike", "combo", "blast", "barrage", "heal", "power_up", "weaken", "poison", "paralyze", "barrier"]),
  attribute: z.enum(["gu", "choki", "pa", "none"]),
  name: z.string(),
  flavor: z.string(),
  vfx: z.enum(["slash", "punch", "beam", "orb", "burst", "wave", "rain", "spiral", "stars", "hearts", "bubbles", "leaves", "sparks", "shield", "glow"]),
  colour: z.enum(["red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink", "black", "white", "rainbow"]),
  atkFormula: z
    .enum(["STR80_AGI20", "STR70_VIT30", "STR60_DEX40", "INT80_DEX20", "INT70_RES30", "INT60_LUK40"])
    .nullable(),
  power: Num,
  hits: Num,
  accuracy: Num,
  critBonus: Num,
  castTicks: Num,
  cooldownTicks: Num,
  healPct: Num,
  stat: StatEnum,
  stages: Num,
  durationTicks: Num,
  chance: Num,
  shieldPct: Num,
  secondary: z
    .object({
      type: z.enum(["none", "poison", "paralyze", "debuff", "drain"]),
      chance: Num,
      stat: StatEnum,
      drainPct: Num,
    })
    .nullable(),
});
const JudgeWithMovesSchema = JudgeSchema.extend({ moves: z.array(AiMoveSchema) });

const ModerationSchema = z.object({
  imageCategory: z.enum(IMAGE_CATEGORIES),
  isHandDrawn: z.boolean(),
  origin: z.enum(IMAGE_ORIGINS),
  names: z.array(z.object({ ok: z.boolean(), category: z.enum(NAME_CATEGORIES) })),
  skillEstimate: z.number().describe("integer 0-100"),
});

/** The subset of the Anthropic client this service uses (mocked in tests). */
export interface MessagesClient {
  messages: Pick<Anthropic["messages"], "parse">;
}

export interface ClaudeServiceOptions {
  client: MessagesClient;
  model: string;
}

const MAX_TOKENS = 4096;

function imageBlock(png: Buffer): Anthropic.ImageBlockParam {
  return {
    type: "image",
    source: { type: "base64", media_type: "image/png", data: png.toString("base64") },
  };
}

export class ClaudeAiService implements AiService {
  constructor(private readonly opts: ClaudeServiceOptions) {
    if (!opts.model) throw new AiUnavailableError("CLAUDE_MODEL is not configured");
  }

  async judgeDrawing(png: Buffer, opts: JudgeOptions = {}): Promise<DrawingJudgement> {
    if (opts.moves) {
      const text = `${JUDGE_USER_TEXT}\n\n${movesUserText(opts.moves)}`;
      const out = await this.call(
        JUDGE_SYSTEM_PROMPT,
        [imageBlock(png), { type: "text", text }],
        JudgeWithMovesSchema,
        "low",
      );
      return { ...out, concerns: out.concerns as DrawingJudgement["concerns"] };
    }
    const out = await this.call(
      JUDGE_SYSTEM_PROMPT,
      [imageBlock(png), { type: "text", text: JUDGE_USER_TEXT }],
      JudgeSchema,
      "low",
    );
    return { ...out, concerns: out.concerns as DrawingJudgement["concerns"] };
  }

  async moderateCharacter(png: Buffer, candidateNames: readonly string[]): Promise<ModerationVerdict> {
    const out = await this.call(
      MODERATION_SYSTEM_PROMPT,
      [imageBlock(png), { type: "text", text: moderationUserText(candidateNames) }],
      ModerationSchema,
      "medium",
    );
    if (out.names.length !== candidateNames.length) {
      throw new AiUnavailableError(
        `moderation returned ${out.names.length} name verdicts for ${candidateNames.length} names`,
      );
    }
    return out;
  }

  async generateMove(png: Buffer, ctx: MoveSlotContext): Promise<Record<string, unknown>> {
    const out = await this.call(
      MOVE_SYSTEM_PROMPT,
      [imageBlock(png), { type: "text", text: moveSlotUserText(ctx) }],
      AiMoveSchema,
      "low",
    );
    return out;
  }

  private async call<T extends z.ZodType>(
    system: string,
    content: Anthropic.ContentBlockParam[],
    schema: T,
    effort: "low" | "medium",
  ): Promise<z.infer<T>> {
    let res;
    try {
      res = await this.opts.client.messages.parse({
        model: this.opts.model,
        max_tokens: MAX_TOKENS,
        system,
        messages: [{ role: "user", content }],
        output_config: { effort, format: zodOutputFormat(schema) },
      });
    } catch (err) {
      // APIError subclasses (429/5xx/connection) and structured-output parse
      // failures (AnthropicError) are all "try again later" for the app.
      if (err instanceof Anthropic.AnthropicError) {
        const status = err instanceof Anthropic.APIError ? String(err.status) : "parse";
        throw new AiUnavailableError(`claude request failed (${status})`, { cause: err });
      }
      throw err;
    }
    if (res.stop_reason === "refusal") {
      throw new AiRefusalError(`claude refused (${res.stop_details?.category ?? "unknown"})`);
    }
    if (res.stop_reason === "max_tokens" || res.parsed_output == null) {
      throw new AiUnavailableError(`no structured output (stop_reason=${String(res.stop_reason)})`);
    }
    return res.parsed_output;
  }
}
