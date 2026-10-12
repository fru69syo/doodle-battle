/**
 * Plausibility check for drawings the app says were made with the in-app drawing tool
 * (`source: "canvas"`, docs/TRUST.md §8).
 *
 * The device skips its digital / AI checks for canvas drawings (their flat pixels would read as
 * "digital"), so a tampered client could label any picture `canvas`. The server therefore only
 * honours the label when the uploaded cut-out looks like it was rendered by the canvas:
 *
 *   1. the client sends a small stroke summary (counts, the palette colours used, the ink box);
 *   2. the colours must come from the app's fixed 12-colour palette, the counts must be within
 *      the canvas caps, and the cut-out's size must match the ink box (same crop as the app);
 *   3. most opaque pixels of the cut-out must be explained by the declared colours: a pixel is
 *      explained when it lies near the line between a declared colour and white/paper (crayon
 *      grain, soft brush and anti-aliasing only mix ink with paper). Only colours that really
 *      occur as solid ink count (declaring the whole palette gains nothing), and a good share of
 *      the ink must be solid palette colour. AI art, photos and digital paintings have shading,
 *      gradients and many unrelated colours, so they fail.
 *
 * Failing is never an error for the child: the drawing is simply treated like a photo (the
 * server's own AI verdict decides the hidden form). This is a cheap heuristic, not proof: a
 * determined attacker can posterise a picture to the palette (which also makes it look like a
 * flat crayon drawing). See docs/TRUST.md §8 for the trade-off.
 */
import { z } from "zod";
import { decodePngPixels } from "../lib/pngPixels";

/** The in-app crayon palette (app/lib/features/draw_canvas/stroke_drawing.dart, ARGB). */
export const CANVAS_PALETTE: readonly number[] = [
  0xff1f1a1a, 0xff8a5a3b, 0xffe53935, 0xffff8a1f, 0xffffd21f, 0xff7cc943, 0xff1e9e4a, 0xff2ec4e6, 0xff2f5fd8, 0xff8e4fd8,
  0xffff7eb6, 0xff9e9e9e,
];
/** Canvas size in units (StrokeDrawing.size × aspect) and the app's caps. */
export const CANVAS_W = 1000;
export const CANVAS_H = 1250;
export const MAX_STROKES = 600;
export const MAX_POINTS = 4000;

/** Tunables (documented in docs/TRUST.md §8). */
export const CANVAS_CHECK = {
  /** Alpha at or above this counts as ink. */
  opaqueAlpha: 128,
  /** Max RGB distance of an explained pixel from a colour→white line. */
  colourTolerance: 40,
  /** Position on the colour→white line (0 = white, 1 = the colour) from which a pixel is solid ink. */
  solidFrom: 0.6,
  /** A declared colour counts only with this many solid pixels (or this ‰ of the ink). */
  minSolidPixels: 8,
  minSolidPerMille: 1,
  /** Share of opaque pixels that must be explained by the present colours. */
  minExplainedPct: 75,
  /** Share of opaque pixels that must be solid ink of a present colour. */
  minSolidPct: 35,
  /** Fewer opaque pixels than this: nothing to judge (treated as not plausible). */
  minOpaquePixels: 64,
  /** The cut-out is the alpha bounding box plus this margin on each side (cutout.dart). */
  cropMarginPx: 4,
  /** Allowed size mismatch between the cut-out and the declared ink box. */
  sizeTolerancePct: 15,
  sizeTolerancePx: 6,
} as const;

/** Stroke summary sent by the app with `source: "canvas"` (all numbers are canvas units). */
export const CanvasSummary = z
  .object({
    v: z.literal(1),
    /** Non-eraser strokes. */
    strokes: z.number().int().min(1).max(MAX_STROKES),
    /** Total points of all strokes. */
    points: z.number().int().min(1).max(MAX_POINTS),
    /** ARGB palette colours used by the non-eraser strokes. */
    colors: z.array(z.number().int()).min(1).max(CANVAS_PALETTE.length),
    /** Ink bounding box [left, top, right, bottom] (StrokeDrawing.inkBounds). */
    inkBox: z.tuple([z.number(), z.number(), z.number(), z.number()]),
  })
  .strict();
export type CanvasSummary = z.infer<typeof CanvasSummary>;

export type CanvasProblem =
  | "SUMMARY_MISSING"
  | "SUMMARY_INVALID"
  | "COLOUR_NOT_IN_PALETTE"
  | "COUNTS_IMPLAUSIBLE"
  | "IMAGE_UNDECODABLE"
  | "TOO_LITTLE_INK"
  | "SIZE_MISMATCH"
  | "COLOURS_MISMATCH";

export interface CanvasCheckResult {
  plausible: boolean;
  problem: CanvasProblem | null;
  /** Share (0-100) of opaque pixels explained by the declared colours (for logs). */
  explainedPct: number | null;
}

const rgbOf = (argb: number): [number, number, number] => [(argb >>> 16) & 0xff, (argb >>> 8) & 0xff, argb & 0xff];

/**
 * Squared distance from p to the segment white→c, and the position t on it (0 = white, 1 = c).
 * Written into `out` to avoid allocations in the pixel loop.
 */
function tint(p: readonly [number, number, number], c: readonly [number, number, number], out: { d2: number; t: number }): void {
  const dx = 255 - c[0];
  const dy = 255 - c[1];
  const dz = 255 - c[2];
  const len2 = dx * dx + dy * dy + dz * dz;
  let t = len2 === 0 ? 0 : ((p[0] - c[0]) * dx + (p[1] - c[1]) * dy + (p[2] - c[2]) * dz) / len2;
  t = t < 0 ? 0 : t > 1 ? 1 : t;
  const ex = p[0] - (c[0] + t * dx);
  const ey = p[1] - (c[1] + t * dy);
  const ez = p[2] - (c[2] + t * dz);
  out.d2 = ex * ex + ey * ey + ez * ez;
  out.t = 1 - t;
}

function sizeOk(actual: number, expected: number): boolean {
  const tol = Math.max(CANVAS_CHECK.sizeTolerancePx, (expected * CANVAS_CHECK.sizeTolerancePct) / 100);
  return Math.abs(actual - expected) <= tol;
}

const no = (problem: CanvasProblem, explainedPct: number | null = null): CanvasCheckResult => ({ plausible: false, problem, explainedPct });

/** Is `png` (the uploaded cut-out) plausibly the canvas drawing the summary describes? */
export function checkCanvasClaim(summary: unknown, png: Buffer): CanvasCheckResult {
  if (summary === undefined || summary === null) return no("SUMMARY_MISSING");
  const parsed = CanvasSummary.safeParse(summary);
  if (!parsed.success) return no("SUMMARY_INVALID");
  const s = parsed.data;
  const colours = [...new Set(s.colors.map((c) => c >>> 0))];
  if (colours.some((c) => !CANVAS_PALETTE.includes(c))) return no("COLOUR_NOT_IN_PALETTE");
  const [l, t, r, b] = s.inkBox;
  const boxW = r - l;
  const boxH = b - t;
  if (s.points < s.strokes || !(boxW > 0 && boxH > 0) || boxW > CANVAS_W + 40 || boxH > CANVAS_H + 40) return no("COUNTS_IMPLAUSIBLE");

  const img = decodePngPixels(png);
  if (!img) return no("IMAGE_UNDECODABLE");

  // Same crop as the app: the ink box at the working scale + the margin. The scale is taken
  // from the longer side so the check does not depend on the app's working resolution.
  const m = 2 * CANVAS_CHECK.cropMarginPx;
  const k = boxH >= boxW ? (img.height - m) / boxH : (img.width - m) / boxW;
  if (!(k > 0) || !sizeOk(img.width, boxW * k + m) || !sizeOk(img.height, boxH * k + m)) return no("SIZE_MISMATCH");

  const tints = colours.map(rgbOf);
  const tol2 = CANVAS_CHECK.colourTolerance * CANVAS_CHECK.colourTolerance;
  // Pass 1: which declared colours really occur as solid ink.
  const solidCount = new Array<number>(tints.length).fill(0);
  const near = new Uint16Array(img.width * img.height); // bit i = explained by colour i; bit 15 = opaque
  const solidOfPx = new Int8Array(img.width * img.height).fill(-1); // colour this pixel is solid ink of
  const OPAQUE = 1 << 15;
  const px: [number, number, number] = [0, 0, 0];
  const o = { d2: 0, t: 0 };
  let opaque = 0;
  for (let i = 0, p = 0; i < img.rgba.length; i += 4, p++) {
    if ((img.rgba[i + 3] ?? 0) < CANVAS_CHECK.opaqueAlpha) continue;
    opaque++;
    px[0] = img.rgba[i] ?? 0;
    px[1] = img.rgba[i + 1] ?? 0;
    px[2] = img.rgba[i + 2] ?? 0;
    let bits = OPAQUE;
    let solidOf = -1;
    tints.forEach((c, ci) => {
      tint(px, c, o);
      if (o.d2 > tol2) return;
      bits |= 1 << ci;
      if (o.t >= CANVAS_CHECK.solidFrom && solidOf < 0) solidOf = ci;
    });
    if (solidOf >= 0) {
      solidCount[solidOf] = (solidCount[solidOf] ?? 0) + 1;
      solidOfPx[p] = solidOf;
    }
    near[p] = bits;
  }
  if (opaque < CANVAS_CHECK.minOpaquePixels) return no("TOO_LITTLE_INK");
  const minSolid = Math.min(CANVAS_CHECK.minSolidPixels, Math.ceil((opaque * CANVAS_CHECK.minSolidPerMille) / 1000));
  let present = 0;
  solidCount.forEach((n, ci) => {
    if (n >= minSolid) present |= 1 << ci;
  });
  // Pass 2: share of the ink explained by present colours, and solid share.
  let explained = 0;
  let solid = 0;
  near.forEach((bits, p) => {
    if ((bits & OPAQUE) === 0 || (bits & present) === 0) return;
    explained++;
    const so = solidOfPx[p] ?? -1;
    if (so >= 0 && (present & (1 << so)) !== 0) solid++;
  });
  const pct = Math.floor((explained * 100) / opaque);
  if (pct < CANVAS_CHECK.minExplainedPct || (solid * 100) / opaque < CANVAS_CHECK.minSolidPct) return no("COLOURS_MISMATCH", pct);
  return { plausible: true, problem: null, explainedPct: pct };
}
