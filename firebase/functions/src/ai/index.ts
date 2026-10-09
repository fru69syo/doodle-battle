import Anthropic from "@anthropic-ai/sdk";
import { ANTHROPIC_API_KEY, CLAUDE_MODEL } from "../config";
import { ClaudeAiService } from "./claude";
import type { AiService } from "./types";

export * from "./types";

let override: AiService | undefined;
let cached: AiService | undefined;

/** Returns the process-wide AI service (lazily built from secret + param). */
export function getAiService(): AiService {
  if (override) return override;
  cached ??= new ClaudeAiService({
    client: new Anthropic({ apiKey: ANTHROPIC_API_KEY.value(), timeout: 25_000, maxRetries: 1 }),
    model: CLAUDE_MODEL.value(),
  });
  return cached;
}

/** Test hook: replace the AI service (pass undefined to reset). */
export function setAiServiceForTesting(service: AiService | undefined): void {
  override = service;
}
