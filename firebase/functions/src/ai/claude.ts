import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import {
  AiRefusalError,
  AiUnavailableError,
  IMAGE_CATEGORIES,
  IMAGE_CONCERNS,
  NAME_CATEGORIES,
  type AiService,
  type DrawingJudgement,
  type ModerationVerdict,
} from "./types";
import {
  JUDGE_SYSTEM_PROMPT,
  JUDGE_USER_TEXT,
  MODERATION_SYSTEM_PROMPT,
  moderationUserText,
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
});

const ModerationSchema = z.object({
  imageCategory: z.enum(IMAGE_CATEGORIES),
  isHandDrawn: z.boolean(),
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

  async judgeDrawing(png: Buffer): Promise<DrawingJudgement> {
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
