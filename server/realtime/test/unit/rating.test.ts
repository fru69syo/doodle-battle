import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  BADGES,
  applyRated,
  badgeFor,
  eloDelta,
  eloExpectedMille,
  eloK,
  initialRated,
  jstDayKey,
  matchBand,
  onlineXp,
  parseRated,
  RATING_FLOOR,
} from "../../src/rating";

interface EloVector {
  ratingA: number;
  ratingB: number;
  aWon: boolean;
  k: number;
  expectedMille: number;
  delta: number;
}

const golden = JSON.parse(readFileSync(resolve(process.cwd(), "../../shared/battle_spec_v3/golden_vectors.json"), "utf8")) as { elo: EloVector[] };
const spec = JSON.parse(readFileSync(resolve(process.cwd(), "../../shared/battle_spec_v3/battle_spec_v3.json"), "utf8")) as {
  progression: { rated: { badges: { min: number; name: string }[]; ratingStart: number; ratingFloor: number; ghostAfterSeconds: number } };
};

describe("Elo (bit-exact with the Dart prototype)", () => {
  it.each(golden.elo)("golden vector %#", (v) => {
    expect(eloExpectedMille(v.ratingA, v.ratingB)).toBe(v.expectedMille);
    expect(eloDelta(v.ratingA, v.ratingB, v.aWon, v.k)).toBe(v.delta);
  });

  it("K is 48 for the first 20 games, then 24, halved against ghosts", () => {
    expect(eloK(0)).toBe(48);
    expect(eloK(19)).toBe(48);
    expect(eloK(20)).toBe(24);
    expect(eloK(5, true)).toBe(24);
    expect(eloK(100, true)).toBe(12);
  });

  it("expected score is symmetric and clamped at ±800", () => {
    for (const d of [0, 25, 50, 333, 799, 800, 2000]) {
      expect(eloExpectedMille(1000 + d, 1000) + eloExpectedMille(1000, 1000 + d)).toBeGreaterThanOrEqual(999);
      expect(eloExpectedMille(1000 + d, 1000) + eloExpectedMille(1000, 1000 + d)).toBeLessThanOrEqual(1001);
    }
    expect(eloExpectedMille(3000, 0)).toBe(990);
  });

  it("never drops below the floor", () => {
    expect(RATING_FLOOR).toBe(spec.progression.rated.ratingFloor);
    expect(610 + eloDelta(610, 900, false, 48)).toBe(602);
    expect(605 + eloDelta(605, 600, false, 48)).toBe(RATING_FLOOR);
    expect(600 + eloDelta(600, 600, false, 48)).toBe(RATING_FLOOR);
  });
});

describe("badges", () => {
  it("match the spec table", () => {
    expect(BADGES.map((b) => ({ min: b.min, name: b.name }))).toEqual(spec.progression.rated.badges);
    expect(initialRated().rating).toBe(spec.progression.rated.ratingStart);
  });

  it("are computed from the best rating, so they never go down", () => {
    let st = { ...initialRated(), rating: 1140, best: 1140, games: 30 };
    let r = applyRated(st, { opponentRating: 1300, won: true, ghost: false, level: 10, nowMs: 0, forfeited: false });
    expect(r.next.rating).toBeGreaterThanOrEqual(1150);
    expect(r.badge).toBe("rabbit");
    expect(r.badgeUp).toBe(true);
    st = r.next;
    for (let i = 0; i < 10; i++) {
      r = applyRated(st, { opponentRating: 1000, won: false, ghost: false, level: 10, nowMs: 0, forfeited: false });
      st = r.next;
      expect(r.badge).toBe("rabbit");
      expect(r.badgeUp).toBe(false);
    }
    expect(st.rating).toBeLessThan(1150);
    expect(badgeFor(st.best)).toBe("rabbit");
  });

  it("thresholds", () => {
    expect(badgeFor(0)).toBe("egg");
    expect(badgeFor(1049)).toBe("egg");
    expect(badgeFor(1050)).toBe("chick");
    expect(badgeFor(1799)).toBe("dragon");
    expect(badgeFor(1800)).toBe("legend");
  });
});

describe("match band", () => {
  it("starts at ±100, widens 50 every 5 s, caps at ±400", () => {
    expect(matchBand(0)).toBe(100);
    expect(matchBand(4.9)).toBe(100);
    expect(matchBand(5)).toBe(150);
    expect(matchBand(15)).toBe(250);
    expect(matchBand(30)).toBe(400);
    expect(matchBand(600)).toBe(400);
  });
  it("ghost fallback default matches the spec", () => {
    expect(spec.progression.rated.ghostAfterSeconds).toBe(20);
  });
});

describe("XP and daily cap", () => {
  it("online XP scales with the real level", () => {
    expect(onlineXp(true, 1)).toBe(150);
    expect(onlineXp(false, 1)).toBe(60);
    expect(onlineXp(true, 50)).toBe(Math.floor((150 * 296) / 100));
  });

  it("gives XP for 20 rated matches per JST day, then 0 (rating still moves)", () => {
    const day1 = Date.UTC(2026, 9, 11, 3, 0, 0); // 12:00 JST
    let st = initialRated();
    let xp = 0;
    for (let i = 0; i < 22; i++) {
      const r = applyRated(st, { opponentRating: st.rating, won: i % 2 === 0, ghost: true, level: 1, nowMs: day1, forfeited: false });
      xp += r.xp > 0 ? 1 : 0;
      st = r.next;
    }
    expect(xp).toBe(20);
    expect(st.dayMatches).toBe(22);
    const nextDay = Date.UTC(2026, 9, 11, 15, 0, 0); // 00:00 JST on the 12th
    expect(jstDayKey(nextDay)).toBe("2026-10-12");
    expect(applyRated(st, { opponentRating: 1000, won: true, ghost: true, level: 1, nowMs: nextDay, forfeited: false }).xp).toBe(150);
  });

  it("forfeit (disconnected 30 s) gives no XP", () => {
    const r = applyRated(initialRated(), { opponentRating: 1000, won: false, ghost: false, level: 30, nowMs: 0, forfeited: true });
    expect(r.xp).toBe(0);
    expect(r.ratingDelta).toBe(-24);
  });
});

describe("parseRated", () => {
  it("defaults garbage and keeps best >= rating", () => {
    expect(parseRated(undefined)).toEqual(initialRated());
    expect(parseRated({ rating: 1200, best: 1100, games: -3 })).toMatchObject({ rating: 1200, best: 1200, games: 0 });
    expect(parseRated({ rating: 10 }).rating).toBe(RATING_FLOOR);
  });
});
