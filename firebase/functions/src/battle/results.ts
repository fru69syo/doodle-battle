import type { MatchDoc, SideResult } from "../model";
import { xpForBattle } from "../vendor/battle_engine";
import { SPEC, type Side } from "./engine";
export const RATING = { initial: 1000, kPvp: 32, kGhost: 16, floor: 0 } as const;

function expected(ra: number, rb: number): number {
  return 1 / (1 + Math.pow(10, (rb - ra) / 400));
}

/**
 * XP via the shared `xpForBattle` (SPEC §4.2: win 100 / lose 40, しょぼキャラ
 * +50%; online has no stage multiplier and no ad boost) so the app and the
 * server always agree, and Elo rating changes. Ghost sides and aborted
 * matches get nothing. The shared engine never ends in a draw; a "draw"
 * outcome (kept for older matches) earns the losing XP.
 */
export function computeResults(match: Pick<MatchDoc, "mode" | "sides">, winner: Side | "draw" | null): Record<Side, SideResult> {
  const none: SideResult = { xp: 0, ratingDelta: 0, outcome: "none" };
  if (winner === null) return { a: { ...none }, b: { ...none } };
  const k = match.mode === "pvp" ? RATING.kPvp : RATING.kGhost;
  const one = (side: Side): SideResult => {
    const me = match.sides[side];
    if (me.isGhost) return { ...none };
    const opp = match.sides[side === "a" ? "b" : "a"];
    const outcome = winner === "draw" ? "draw" : winner === side ? "win" : "lose";
    const score = outcome === "win" ? 1 : outcome === "draw" ? 0.5 : 0;
    const xp = xpForBattle(SPEC, { won: outcome === "win", isShobo: me.isShobo });
    const ratingDelta = Math.round(k * (score - expected(me.rating, opp.rating)));
    return { xp, ratingDelta, outcome };
  };
  return { a: one("a"), b: one("b") };
}
