import type { BattleEngine } from "../engine";
import { DevEngine } from "./devEngine";
import { V3Engine } from "./v3Engine";

/**
 * Picks the battle engine (env BATTLE_ENGINE).
 *
 * "v3" (default, production): the shared Engine v3 (`shared/battle_engine_v3_ts`, a `file:`
 * dependency) through `engines/v3Engine.ts`; checked against the golden vectors in
 * test/unit/v3Engine.test.ts (docs/REALTIME_PROTOCOL.md §9).
 * "dev": the simplified stand-in, for local development only (refused in production).
 */
export function loadEngine(kind: "v3" | "dev"): BattleEngine {
  return kind === "dev" ? new DevEngine() : new V3Engine();
}
