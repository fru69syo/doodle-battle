import type { BattleEngine } from "../engine";
import { DevEngine } from "./devEngine";

/**
 * Picks the battle engine (env BATTLE_ENGINE).
 *
 * "v3": the shared Engine v3. Not linked yet: the Engine team is writing
 * shared/battle_engine_v3_ts. Swap steps in docs/REALTIME_PROTOCOL.md §9:
 *   1. npm i ../../shared/battle_engine_v3_ts   (adds "file:" dependency)
 *   2. add engines/v3Engine.ts implementing BattleEngine with it
 *   3. return new V3Engine() below, run the golden-vector replay test
 */
export function loadEngine(kind: "v3" | "dev"): BattleEngine {
  if (kind === "dev") return new DevEngine();
  throw new Error("BATTLE_ENGINE=v3 requested but Engine v3 is not linked into the server yet (docs/REALTIME_PROTOCOL.md §9). Use BATTLE_ENGINE=dev for development.");
}
