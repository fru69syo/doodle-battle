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
      maxBars: 3,
    });
    expect(r.map((x) => x.accepted)).toEqual([true, false, false, false]);
  });

  it("the move prompt carries the attribute, budgets, the bar costs and kana rules", () => {
    const t = movesUserText({ attribute: "pa", slotBudgets: [100, 390, 390, 390], maxBars: 3, barBudgets: [100, 230, 390] });
    expect(t).toContain('"pa"');
    expect(t).toContain("slot 4: 390");
    expect(t).toContain("3 bars: up to 390");
    expect(t).toContain("at most 3 bars");
    expect(t).not.toContain("spCost");
    expect(t).toMatch(/hiragana or katakana/);
  });

  it("validated moves cost bars, never more than the character's max bars", () => {
    const big = { template: "blast", attribute: "none", name: "ドカーン", atkFormula: "INT80_DEX20", power: 1200, spCost: 0, bars: 1 };
    for (const maxBars of [2, 5]) {
      const r = validateAiMoveSet(DEFAULT_SPEC, { moves: [null, null, null, big] }, { own: "gu", moveFactorPct: 100, maxBars });
      const m = r[3]!.result.move!;
      expect(m.bars).toBe(maxBars);
      expect(r[3]!.proposal).not.toHaveProperty("spCost");
    }
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
    const out = await svc.judgeDrawing(makePng(32, 32), { moves: { attribute: "gu", slotBudgets: [100, 230, 230, 230], maxBars: 2, barBudgets: [100, 230] } });
    expect(out.moves).toEqual([]);
    const reqArg = (parse.mock.calls[0] as unknown[])[0] as Record<string, any>;
    expect(Object.keys(reqArg.output_config.format.schema.properties)).toContain("moves");
    expect(reqArg.messages[0].content[1].text).toContain("propose exactly 4 moves");
  });
});
