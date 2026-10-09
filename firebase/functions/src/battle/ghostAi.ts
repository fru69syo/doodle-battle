import type { ActionId, EngineState, SharedEngine, Side } from "./engine";
import { turnSeed } from "./rng";

/**
 * Server-side AI for ghost opponents: the shared CPU AI at "ふつう" strength
 * (SPEC §4.3 — special when ready, element move unless type-disadvantaged,
 * occasional guard). Its rng is seeded from (match seed, turn, side), separate
 * from the battle rng, so it is deterministic and never shifts battle rolls.
 */
export function chooseGhostAction(engine: SharedEngine, state: EngineState, side: Side): ActionId {
  return engine.chooseGhostAction(state, side, (seed, turn) => turnSeed(seed, turn, `ghost-${side}`));
}
