import { describe, expect, it } from "vitest";
import { ClaudeAiService, type MessagesClient } from "../../src/ai/claude";
import { movesUserText } from "../../src/ai/prompts";
import { V2DrawingInput } from "../../src/callables/judgeDrawing";
import { DEFAULT_SPEC, ENGINE_ID, validateAiMoveSet } from "../../src/vendor/battle_engine_v3";
import { makePng } from "../helpers/png";
import { vi } from "vitest";

describe("engine v3 in functions", () => {
  it("is vendored and validates AI moves", () => {
    expect(ENGINE_ID).toMatch(/^v3/);
    const r = validateAiMoveSet(DEFAULT_SPEC, { moves: [{ template: "strike", attribute: "gu", name: "パンチ" }] }, {
      own: "gu",
      moveFactorPct: 100,
    });
    expect(r.map((x) => x.accepted)).toEqual([true, false, false, false]);
  });

  it("the move prompt carries the attribute, budgets and kana rules", () => {
    const t = movesUserText("pa", [100, 100, 120, 150]);
    expect(t).toContain('"pa"');
    expect(t).toContain("slot 4: 150");
    expect(t).toMatch(/hiragana or katakana/);
  });

  it("v2 judge input only accepts the quantised contract", () => {
    expect(V2DrawingInput.safeParse({ features: {}, energy10: 1, skill10: 2, imageHash: "ab".repeat(32) }).success).toBe(true);
    expect(V2DrawingInput.safeParse({ features: { a: 0.5 }, energy10: 1, skill10: 2, imageHash: "ab".repeat(32) }).success).toBe(false);
  });

  it("asks Claude for moves with a schema when a move context is given", async () => {
    const parse = vi.fn(async () => ({
      stop_reason: "end_turn",
      parsed_output: { subject: "ねこ", suggestedNames: [], elementMoveName: "", specialMoveName: "", skillEstimate: 1, appropriate: true, concerns: [], origin: "hand_drawn", moves: [] },
    }));
    const svc = new ClaudeAiService({ client: { messages: { parse } } as unknown as MessagesClient, model: "m" });
    const out = await svc.judgeDrawing(makePng(32, 32), { moves: { attribute: "gu", slotBudgets: [100, 100, 120, 150] } });
    expect(out.moves).toEqual([]);
    const reqArg = (parse.mock.calls[0] as unknown[])[0] as Record<string, any>;
    expect(Object.keys(reqArg.output_config.format.schema.properties)).toContain("moves");
    expect(reqArg.messages[0].content[1].text).toContain("propose exactly 4 moves");
  });
});
