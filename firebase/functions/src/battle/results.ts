import type { MatchDoc, SideResult } from "../model";
import type { Side } from "./engine";

export const XP = { win: 100, lose: 40, draw: 70, shoboBonus: 1.5 } as const;
export const RATING = { initial: 1000, kPvp: 32, kGhost: 16, floor: 0 } as const;

function expected(ra: number, rb: number): number {
  return 1 / (1 + Math.pow(10, (rb - ra) / 400));
}

/**
 * XP (SPEC §4.2: win 100 / lose 40, しょぼキャラ +50%) and Elo rating changes.
 * Ghost sides and aborted matches get nothing. Draw XP (70) is an assumption.
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
    const baseXp = XP[outcome];
    const xp = Math.round(me.isShobo ? baseXp * XP.shoboBonus : baseXp);
    const ratingDelta = Math.round(k * (score - expected(me.rating, opp.rating)));
    return { xp, ratingDelta, outcome };
  };
  return { a: one("a"), b: one("b") };
}
