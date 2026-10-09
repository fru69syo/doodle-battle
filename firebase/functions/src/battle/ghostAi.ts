import type { Element } from "../stats/statLimits";
import { typeMultiplier, type ActionId, type BattleEngine, type EngineState, type Side } from "./engine";
import { mulberry32, turnSeed } from "./rng";

/**
 * Server-side AI for ghost opponents ("ふつう" strength, SPEC §4.3):
 * uses the special when ready, prefers the element move unless it is weak
 * against the opponent, and sometimes guards when low on HP.
 * Deterministic for (match seed, turn).
 */
export function chooseGhostAction(
  engine: BattleEngine,
  state: EngineState,
  side: Side,
  elements: Record<Side, Element>,
): ActionId {
  const legal = engine.legalActions(state, side);
  const view = engine.view(state);
  const me = view[side];
  const rng = mulberry32(turnSeed(state.seed, view.turn + 1, `ghost-${side}`));
  if (legal.includes("special")) return "special";
  const opp: Side = side === "a" ? "b" : "a";
  if (legal.includes("guard") && me.hp < me.maxHp * 0.3 && rng() < 0.35) return "guard";
  const mult = typeMultiplier(elements[side], elements[opp]);
  const elementChance = mult > 1 ? 0.9 : mult < 1 ? 0.25 : 0.65;
  return rng() < elementChance && legal.includes("element") ? "element" : "tackle";
}
