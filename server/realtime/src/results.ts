/**
 * Pure settlement of a finished match: who won, rating changes, XP, badges, and the records to
 * persist. Runs inside the store's transaction (so it must not do I/O).
 */
import type { BattleEvent, Side } from "./engine";
import { applyRated, badgeFor, type BadgeId, type RatedState } from "./rating";

export type EndReason = "ko" | "timeout" | "forfeit" | "aborted";

export interface InputRecord {
  tick: number;
  side: Side;
  slot: number;
  /** player = the child chose; auto = 5 s timeout おまかせ; ai = ghost / disconnected side */
  src: "player" | "auto" | "ai";
}

export interface SideSummary {
  uid: string | null;
  snapshotId: string;
  level: number;
  isGhost: boolean;
  /** Rating the opponent is rated against (ghost: the ghost's stored rating). */
  ratingAtStart: number;
}

export interface MatchSummary {
  matchId: string;
  mode: "pvp" | "ghost";
  engineId: string;
  seed: number;
  startedAtMs: number;
  endedAtMs: number;
  ticks: number;
  sides: [SideSummary, SideSummary];
  winner: Side | null;
  reason: EndReason;
  /** Side that lost by staying disconnected (forfeit). */
  forfeitSide: Side | null;
  inputs: InputRecord[];
  finalHash: string;
  /** Last events, for audits (bounded). */
  tailEvents: BattleEvent[];
}

export interface PlayerResult {
  uid: string;
  side: Side;
  outcome: "win" | "lose" | "none";
  xp: number;
  ratingDelta: number;
  badge: BadgeId;
  badgeUp: boolean;
  /** New rated state to write (null = unchanged, e.g. aborted). */
  next: RatedState | null;
}

export interface Settlement {
  players: PlayerResult[];
}

/**
 * @param rated current rated state of each human uid (missing = defaults by the caller)
 */
export function settle(summary: MatchSummary, rated: Map<string, RatedState>): Settlement {
  const players: PlayerResult[] = [];
  for (const side of [0, 1] as const) {
    const me = summary.sides[side];
    if (me.isGhost || me.uid === null) continue;
    const prev = rated.get(me.uid);
    if (!prev) throw new Error(`missing rated state for ${me.uid}`);
    const foe = summary.sides[side === 0 ? 1 : 0];
    if (summary.reason === "aborted" || summary.winner === null) {
      players.push({ uid: me.uid, side, outcome: "none", xp: 0, ratingDelta: 0, badge: badgeFor(prev.best), badgeUp: false, next: null });
      continue;
    }
    const won = summary.winner === side;
    // In PvP each player is rated against the other's rating before the match.
    const foeRating = foe.isGhost || foe.uid === null ? foe.ratingAtStart : (rated.get(foe.uid)?.rating ?? foe.ratingAtStart);
    const r = applyRated(prev, {
      opponentRating: foeRating,
      won,
      ghost: summary.mode === "ghost",
      level: me.level,
      nowMs: summary.endedAtMs,
      forfeited: summary.forfeitSide === side,
    });
    players.push({ uid: me.uid, side, outcome: won ? "win" : "lose", xp: r.xp, ratingDelta: r.ratingDelta, badge: r.badge, badgeUp: r.badgeUp, next: r.next });
  }
  return { players };
}
