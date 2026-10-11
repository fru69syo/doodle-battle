/**
 * Rated play: Elo with a provisional K, a rating floor and kid-friendly badges that never go
 * down. Integer maths, bit-identical with app/lib/domain/battle_v2/progression_v2.dart and the
 * `elo` golden vectors in shared/battle_spec_v3/golden_vectors.json (GAME_DESIGN_V2 §8).
 */
export const RATING_START = 1000;
export const RATING_FLOOR = 600;
export const RATED_SYNC_LEVEL = 50;
export const RATED_UNLOCK_LEVEL = 5;
export const PROVISIONAL_GAMES = 20;

/** K-factor: 48 for the first 20 rated games, then 24; ghost matches use half. */
export function eloK(gamesPlayed: number, ghost = false): number {
  const k = gamesPlayed < PROVISIONAL_GAMES ? 48 : 24;
  return ghost ? Math.trunc(k / 2) : k;
}

/** E = 1/(1+10^(-d/400)) ×1000, sampled every 50 points for d in [-800, 800]. */
const ELO_TABLE = [
  10, 13, 17, 23, 31, 40, 53, 70, 91, 118, 151, 192, 240, 297, 360, 429, 500, 571, 640, 703, 760, 808, 849,
  882, 909, 930, 947, 960, 969, 977, 983, 987, 990,
] as const;

function table(i: number): number {
  const v = ELO_TABLE[i];
  if (v === undefined) throw new RangeError(`elo table index ${i}`);
  return v;
}

/** Expected score of A against B, ×1000 (integer, linear between table points). */
export function eloExpectedMille(ratingA: number, ratingB: number): number {
  const d = Math.min(800, Math.max(-800, ratingA - ratingB));
  const x = d + 800;
  const i = Math.floor(x / 50);
  const r = x % 50;
  if (i >= 32) return table(32);
  return table(i) + Math.floor(((table(i + 1) - table(i)) * r) / 50);
}

/** Rating change for A (positive = gain), rounded half away from zero, never below the floor. */
export function eloDelta(ratingA: number, ratingB: number, aWon: boolean, k: number): number {
  const e = eloExpectedMille(ratingA, ratingB);
  const num = k * ((aWon ? 1000 : 0) - e);
  let d = num >= 0 ? Math.floor((num + 500) / 1000) : -Math.floor((-num + 500) / 1000);
  if (ratingA + d < RATING_FLOOR) d = RATING_FLOOR - ratingA;
  return d;
}

/** Badges in order. The badge a child sees is computed from their BEST rating ever. */
export const BADGES = [
  { min: 0, id: "egg", name: "たまご" },
  { min: 1050, id: "chick", name: "ひよこ" },
  { min: 1150, id: "rabbit", name: "うさぎ" },
  { min: 1250, id: "fox", name: "きつね" },
  { min: 1350, id: "bear", name: "くま" },
  { min: 1450, id: "lion", name: "ライオン" },
  { min: 1600, id: "dragon", name: "ドラゴン" },
  { min: 1800, id: "legend", name: "でんせつ" },
] as const;

export type BadgeId = (typeof BADGES)[number]["id"];

export function badgeFor(bestRating: number): BadgeId {
  let id: BadgeId = "egg";
  for (const b of BADGES) if (bestRating >= b.min) id = b.id;
  return id;
}

/** Matchmaking band (± rating) after waiting `seconds`: 100, +50 every 5 s, max 400. */
export function matchBand(waitSeconds: number): number {
  return Math.min(400, 100 + 50 * Math.floor(Math.max(0, waitSeconds) / 5));
}

/** XP for an online match (spec progression.xpOnline). Character level = real level, not 50. */
export function onlineXp(won: boolean, level: number): number {
  const base = won ? 150 : 60;
  return Math.floor((base * (100 + 4 * (Math.max(1, level) - 1))) / 100);
}

export const ONLINE_XP_MATCHES_PER_DAY = 20;

/** The rated part of users/{uid}: { rated: RatedState }. */
export interface RatedState {
  rating: number;
  games: number;
  best: number;
  /** Day (Asia/Tokyo, YYYY-MM-DD) that dayMatches counts. */
  dayKey: string;
  dayMatches: number;
}

export function initialRated(): RatedState {
  return { rating: RATING_START, games: 0, best: RATING_START, dayKey: "", dayMatches: 0 };
}

/** YYYY-MM-DD in Japan time (children's "day" resets at midnight JST). */
export function jstDayKey(ms: number): string {
  return new Date(ms + 9 * 3_600_000).toISOString().slice(0, 10);
}

export interface RatedOutcome {
  next: RatedState;
  ratingDelta: number;
  xp: number;
  badge: BadgeId;
  badgeUp: boolean;
}

/**
 * Applies one finished rated match to a player's state.
 * @param opponentRating Elo of the opponent (ghost: rating stored with the ghost snapshot)
 * @param counted false for aborted matches (no change at all)
 */
export function applyRated(
  prev: RatedState,
  args: { opponentRating: number; won: boolean; ghost: boolean; level: number; nowMs: number; forfeited: boolean },
): RatedOutcome {
  const day = jstDayKey(args.nowMs);
  const dayMatches = prev.dayKey === day ? prev.dayMatches : 0;
  const k = eloK(prev.games, args.ghost);
  const delta = eloDelta(prev.rating, args.opponentRating, args.won, k);
  const rating = prev.rating + delta;
  const best = Math.max(prev.best, rating);
  const xpAllowed = dayMatches < ONLINE_XP_MATCHES_PER_DAY && !args.forfeited;
  const next: RatedState = { rating, games: prev.games + 1, best, dayKey: day, dayMatches: dayMatches + 1 };
  const before = badgeFor(prev.best);
  const after = badgeFor(best);
  return {
    next,
    ratingDelta: delta,
    xp: xpAllowed ? onlineXp(args.won, args.level) : 0,
    badge: after,
    badgeUp: before !== after,
  };
}

/** Defensive parse of a Firestore value into RatedState. */
export function parseRated(v: unknown): RatedState {
  const d = initialRated();
  if (typeof v !== "object" || v === null) return d;
  const o = v as Record<string, unknown>;
  const int = (x: unknown, def: number) => (typeof x === "number" && Number.isFinite(x) ? Math.trunc(x) : def);
  const rating = Math.max(RATING_FLOOR, int(o.rating, d.rating));
  return {
    rating,
    games: Math.max(0, int(o.games, 0)),
    best: Math.max(rating, int(o.best, rating)),
    dayKey: typeof o.dayKey === "string" ? o.dayKey : "",
    dayMatches: Math.max(0, int(o.dayMatches, 0)),
  };
}
