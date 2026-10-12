import { describe, expect, it } from "vitest";
import { decodePngPixels } from "../../src/lib/pngPixels";
import { CANVAS_PALETTE, checkCanvasClaim } from "../../src/trust/canvasCheck";
import { hiddenOrigin } from "../../src/trust/origin";
import { CANVAS_TEST_BOX, CANVAS_TEST_SIZE, canvasLikePng, encodeRgbaPng, gradientPng, makePng } from "../helpers/png";

const colors = [CANVAS_PALETTE[0]!, CANVAS_PALETTE[2]!, CANVAS_PALETTE[4]!, CANVAS_PALETTE[8]!];
const summary = (over: Record<string, unknown> = {}) => ({ v: 1, strokes: 14, points: 560, colors, inkBox: CANVAS_TEST_BOX, ...over });

describe("decodePngPixels", () => {
  it("decodes every row filter to the same pixels", () => {
    const ref = decodePngPixels(gradientPng(0));
    expect(ref).toMatchObject({ width: CANVAS_TEST_SIZE.width, height: CANVAS_TEST_SIZE.height });
    for (const f of [1, 2, 3, 4] as const) expect(decodePngPixels(gradientPng(f))?.rgba).toEqual(ref?.rgba);
  });

  it("returns null for shapes it does not support or broken files", () => {
    expect(decodePngPixels(makePng(32, 32))).toBeNull(); // no IDAT
    expect(decodePngPixels(Buffer.from("not a png at all, really not one"))).toBeNull();
    const ok = encodeRgbaPng(2, 2, new Uint8Array(16).fill(200));
    expect(decodePngPixels(ok)?.rgba[0]).toBe(200);
    expect(decodePngPixels(ok, 3)).toBeNull(); // over the pixel budget
    expect(decodePngPixels(ok.subarray(0, ok.length - 20))).toBeNull(); // truncated
  });
});

describe("canvas plausibility (docs/TRUST.md §7)", () => {
  it("accepts a stroke-rendered drawing in the declared palette colours", () => {
    const r = checkCanvasClaim(summary(), canvasLikePng(colors));
    expect(r).toMatchObject({ plausible: true, problem: null });
    expect(r.explainedPct).toBeGreaterThanOrEqual(90);
  });

  it("refuses a shaded / gradient picture claimed as canvas", () => {
    expect(checkCanvasClaim(summary({ colors: CANVAS_PALETTE }), gradientPng())).toMatchObject({ plausible: false, problem: "COLOURS_MISMATCH" });
  });

  it("refuses colours the summary did not declare", () => {
    const r = checkCanvasClaim(summary({ colors: [CANVAS_PALETTE[5]!] }), canvasLikePng(colors));
    expect(r).toMatchObject({ plausible: false, problem: "COLOURS_MISMATCH" });
  });

  it("checks the summary itself", () => {
    const png = canvasLikePng(colors);
    expect(checkCanvasClaim(undefined, png).problem).toBe("SUMMARY_MISSING");
    expect(checkCanvasClaim({ v: 1 }, png).problem).toBe("SUMMARY_INVALID");
    expect(checkCanvasClaim(summary({ extra: 1 }), png).problem).toBe("SUMMARY_INVALID");
    expect(checkCanvasClaim(summary({ colors: [0xff123456] }), png).problem).toBe("COLOUR_NOT_IN_PALETTE");
    expect(checkCanvasClaim(summary({ points: 3 }), png).problem).toBe("COUNTS_IMPLAUSIBLE");
    expect(checkCanvasClaim(summary({ inkBox: [0, 0, 0, 10] }), png).problem).toBe("COUNTS_IMPLAUSIBLE");
    expect(checkCanvasClaim(summary(), makePng(64, 64)).problem).toBe("IMAGE_UNDECODABLE");
  });

  it("the cut-out must have the size of the declared ink box", () => {
    expect(checkCanvasClaim(summary({ inkBox: [0, 0, 800, 800] }), canvasLikePng(colors)).problem).toBe("SIZE_MISMATCH");
    // Scale-free: the same box at another resolution is fine.
    const [l, t, r, b] = CANVAS_TEST_BOX;
    expect(checkCanvasClaim(summary({ inkBox: [l / 2, t / 2, r / 2, b / 2] }), canvasLikePng(colors)).plausible).toBe(true);
  });

  it("needs some ink", () => {
    const empty = encodeRgbaPng(CANVAS_TEST_SIZE.width, CANVAS_TEST_SIZE.height, new Uint8Array(CANVAS_TEST_SIZE.width * CANVAS_TEST_SIZE.height * 4));
    expect(checkCanvasClaim(summary(), empty).problem).toBe("TOO_LITTLE_INK");
  });
});

describe("hidden origin (which verdict feeds the hidden form)", () => {
  const photo = { source: "photo" as const, canvasPlausible: false };
  it("photos: a decided Claude verdict wins over the device", () => {
    expect(hiddenOrigin({ ...photo, serverOrigin: "ai_generated", deviceVerdict: null })).toBe("ai_generated");
    expect(hiddenOrigin({ ...photo, serverOrigin: "hand_drawn", deviceVerdict: "digital" })).toBeNull();
    expect(hiddenOrigin({ ...photo, serverOrigin: "unsure", deviceVerdict: "printed" })).toBe("printed");
    expect(hiddenOrigin({ ...photo, serverOrigin: "unsure", deviceVerdict: null })).toBeNull();
  });

  it("plausible canvas keeps the device verdict; an implausible canvas claim is treated as a photo", () => {
    expect(hiddenOrigin({ source: "canvas", canvasPlausible: true, serverOrigin: "ai_generated", deviceVerdict: null })).toBeNull();
    expect(hiddenOrigin({ source: "canvas", canvasPlausible: false, serverOrigin: "ai_generated", deviceVerdict: null })).toBe("ai_generated");
    expect(hiddenOrigin({ source: "canvas", canvasPlausible: false, serverOrigin: "unsure", deviceVerdict: null })).toBeNull();
  });
});
