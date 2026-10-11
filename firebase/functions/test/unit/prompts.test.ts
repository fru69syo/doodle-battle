import { describe, expect, it } from "vitest";
import * as prompts from "../../src/ai/prompts";
import { CHILD_SAFETY_RULES, movesUserText } from "../../src/ai/prompts";

describe("child-safety rules", () => {
  it("state the audience, content limits, no addressing the child, and the safer default", () => {
    expect(CHILD_SAFETY_RULES).toMatch(/children aged roughly 6-12/);
    expect(CHILD_SAFETY_RULES).toMatch(/cartoon play-fighting/);
    expect(CHILD_SAFETY_RULES).toMatch(/no sexual content/);
    expect(CHILD_SAFETY_RULES).toMatch(/no fear-inducing content/);
    expect(CHILD_SAFETY_RULES).toMatch(/no brand names and no names of real people/);
    expect(CHILD_SAFETY_RULES).toMatch(/no requests for personal information/);
    expect(CHILD_SAFETY_RULES).toMatch(/Never address the child and never ask them questions/);
    expect(CHILD_SAFETY_RULES).toMatch(/When unsure, choose the safer output/);
  });

  it("are part of every exported system prompt and the move prompt", () => {
    const systemPrompts = Object.entries(prompts).filter(
      ([k, v]) => k.endsWith("_SYSTEM_PROMPT") && typeof v === "string",
    );
    expect(systemPrompts.map(([k]) => k).sort()).toEqual(["JUDGE_SYSTEM_PROMPT", "MODERATION_SYSTEM_PROMPT"]);
    for (const [k, v] of systemPrompts) expect(v, k).toContain(CHILD_SAFETY_RULES);
    expect(movesUserText("gu", [100, 100, 120, 150])).toContain(CHILD_SAFETY_RULES);
  });
});
