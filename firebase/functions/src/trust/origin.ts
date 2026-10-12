/**
 * Which trust verdict feeds the hidden late-bloomer form of a v2 character (GAME_DESIGN_V2 §1,
 * docs/TRUST.md §8). The verdict is internal: it is stored in `snapshots/{id}.engine.trust` and
 * never returned to any client.
 *
 * - photo (or a `canvas` claim that is not plausible): the server's Claude verdict wins when it
 *   is decided (`ai_generated` -> hidden form, `hand_drawn` -> normal, even if the device said
 *   otherwise); only when Claude is `unsure` does the device's own verdict count.
 * - plausible `canvas`: the device's internal verdict is kept (normally none: the canvas is never
 *   judged "digital"), because Claude cannot tell flat finger-painted pixels from digital art.
 *
 * Photo / print / screen and inappropriate images are refused before this, for every source.
 */
import type { ImageOrigin } from "../ai/types";

export type DrawingSource = "photo" | "canvas";

export function hiddenOrigin(o: {
  source: DrawingSource;
  canvasPlausible: boolean;
  serverOrigin: ImageOrigin;
  deviceVerdict: string | null;
}): string | null {
  if (o.source === "canvas" && o.canvasPlausible) return o.deviceVerdict;
  if (o.serverOrigin === "ai_generated") return "ai_generated";
  if (o.serverOrigin === "hand_drawn") return null;
  return o.deviceVerdict;
}
