/**
 * Levels, XP, rewarded-ad rule, rated play (Lv50 sync, Elo, badges),
 * family battles. Port of app/lib/domain/battle_v3/progression.dart.
 */
import { idiv, type V3Spec } from './spec';

export function xpToNext(s: V3Spec, level: number): number {
  return s.xpBase + s.xpPerLevel * level + idiv(s.xpQuadNum * level * level, s.xpQuadDen);
}

export function totalXpTo(s: V3Spec, level: number): number {
  let t = 0;
  for (let l = 1; l < level; l++) t += xpToNext(s, l);
  return t;
}

export const EVOLUTIONS: ReadonlyArray<readonly [number, string]> = [
  [10, 'kagayaki'],
  [25, 'kirakira'],
  [50, 'densetsu'],
  [75, 'niji'],
  [100, 'oukan'],
];

/** Single-player XP (see Dart `xpSinglePlayer`). */
export function xpSinglePlayer(o: {
  win: boolean;
  stage: number;
  level: number;
  firstClear?: boolean;
  adBoost?: boolean;
  hiddenBloomer?: boolean;
}): number {
  const base = o.win ? 100 : 40;
  const stagePct = 100 + 4 * (o.stage - 1);
  const gap = o.level - o.stage;
  const replayPct = o.hiddenBloomer || gap <= 10 ? 100 : gap <= 20 ? 50 : 20;
  let xp = idiv(base * stagePct * replayPct, 10000);
  if (o.firstClear && o.win) xp *= 2;
  if (o.hiddenBloomer) xp *= 2;
  if (o.adBoost) xp *= 2;
  return xp;
}

export const ONLINE_XP_BATTLES_PER_DAY = 20;
export const SAME_OPPONENT_COOLDOWN_MINUTES = 60;

/** Online XP (server-computed). `hiddenBloomerBonus` is INTERNAL. */
export function xpOnline(o: { win: boolean; level: number; eligible: boolean; hiddenBloomerBonus?: boolean }): number {
  if (!o.eligible) return 0;
  let xp = idiv((o.win ? 150 : 60) * (100 + 4 * (o.level - 1)), 100);
  if (o.hiddenBloomerBonus) xp = idiv(xp * 150, 100);
  return xp;
}

/** Whether an online (or ghost) battle earns XP. */
export function onlineXpEligible(o: {
  xpBattlesToday: number;
  minutesSinceSameOpponent: number | null;
  disconnectLoss: boolean;
}): boolean {
  return (
    o.xpBattlesToday < ONLINE_XP_BATTLES_PER_DAY &&
    (o.minutesSinceSameOpponent === null || o.minutesSinceSameOpponent >= SAME_OPPONENT_COOLDOWN_MINUTES) &&
    !o.disconnectLoss
  );
}

export const FAMILY_BATTLE_XP = 0;

export function familyBattleLevel(
  s: V3Spec,
  o: { ownLevel: number; otherLevel: number; sameLevel: boolean; boost?: number },
): number {
  const base = o.sameLevel && o.otherLevel > o.ownLevel ? o.otherLevel : o.ownLevel;
  const l = base + (o.boost ?? 0);
  return l > s.maxLevel ? s.maxLevel : l < 1 ? 1 : l;
}

export const AD_BOOSTS_PER_DAY = 3;
export type AppPlatform = 'android' | 'ios' | 'other';

export function adBoostAvailable(o: { platform: AppPlatform; parentAllowsAds: boolean; usedToday: number }): boolean {
  return o.platform === 'android' && o.parentAllowsAds && o.usedToday < AD_BOOSTS_PER_DAY;
}

export function unlockedSlots(s: V3Spec, level: number): number {
  return s.slotUnlockLevels.filter((l) => level >= l).length;
}

export interface LevelProgress {
  level: number;
  xp: number;
  fromLevel: number;
  newSlots: number[];
  evolutions: string[];
  /** INTERNAL — never surface. */
  rebirth: boolean;
}

export function applyXp(s: V3Spec, o: { level: number; xp: number; gained: number; isBloomer?: boolean }): LevelProgress {
  let l = o.level < 1 ? 1 : o.level > s.maxLevel ? s.maxLevel : o.level;
  let x = o.xp < 0 ? 0 : o.xp;
  if (o.gained > 0) x += o.gained;
  while (l < s.maxLevel && x >= xpToNext(s, l)) {
    x -= xpToNext(s, l);
    l++;
  }
  if (l >= s.maxLevel) x = 0;
  const newSlots: number[] = [];
  s.slotUnlockLevels.forEach((u, i) => {
    if (u > o.level && u <= l) newSlots.push(i);
  });
  return {
    level: l,
    xp: x,
    fromLevel: o.level,
    newSlots,
    evolutions: EVOLUTIONS.filter(([lv]) => lv > o.level && lv <= l).map(([, n]) => n),
    rebirth: (o.isBloomer ?? false) && o.level < s.rebirthLevel && l >= s.rebirthLevel,
  };
}

// --- Rated play -----------------------------------------------------------

export const RATED_SYNC_LEVEL = 50;
export const RATED_UNLOCK_LEVEL = 5;
export const RATING_START = 1000;
export const RATING_FLOOR = 600;

export interface RatedSync {
  statLevel: number;
  /** INTERNAL. */
  preForm: boolean;
  slotCount: number;
  moveStream: number;
}

export function ratedSync(s: V3Spec, o: { actualLevel: number; isBloomer: boolean; syncLevel?: number }): RatedSync {
  const pre = o.isBloomer && o.actualLevel < s.rebirthLevel;
  const reborn = o.isBloomer && o.actualLevel >= s.rebirthLevel;
  return {
    statLevel: o.syncLevel ?? RATED_SYNC_LEVEL,
    preForm: pre,
    slotCount: unlockedSlots(s, o.actualLevel),
    moveStream: reborn ? 14 : 12,
  };
}

export function eloK(gamesPlayed: number, ghost = false): number {
  const k = gamesPlayed < 20 ? 48 : 24;
  return ghost ? idiv(k, 2) : k;
}

const ELO_TABLE = [
  10, 13, 17, 23, 31, 40, 53, 70, 91, 118, 151, 192, 240, 297, 360, 429, 500, 571, 640, 703, 760, 808, 849, 882, 909,
  930, 947, 960, 969, 977, 983, 987, 990,
] as const;

export function eloExpectedMille(ratingA: number, ratingB: number): number {
  let d = ratingA - ratingB;
  if (d < -800) d = -800;
  if (d > 800) d = 800;
  const x = d + 800;
  const i = idiv(x, 50);
  const r = x % 50;
  if (i >= 32) return ELO_TABLE[32];
  return ELO_TABLE[i]! + idiv((ELO_TABLE[i + 1]! - ELO_TABLE[i]!) * r, 50);
}

export function eloDelta(ratingA: number, ratingB: number, aWon: boolean, k: number): number {
  const e = eloExpectedMille(ratingA, ratingB);
  const num = k * ((aWon ? 1000 : 0) - e);
  let d = num >= 0 ? idiv(num + 500, 1000) : -idiv(-num + 500, 1000);
  if (ratingA + d < RATING_FLOOR) d = RATING_FLOOR - ratingA;
  return d;
}

export const BADGES: ReadonlyArray<readonly [number, string]> = [
  [0, 'たまご'],
  [1050, 'ひよこ'],
  [1150, 'うさぎ'],
  [1250, 'きつね'],
  [1350, 'くま'],
  [1450, 'ライオン'],
  [1600, 'ドラゴン'],
  [1800, 'でんせつ'],
];

/** Shown badge for the best rating ever reached (never goes down). */
export function badgeFor(bestRating: number): string {
  let b = BADGES[0]![1];
  for (const [min, name] of BADGES) if (bestRating >= min) b = name;
  return b;
}

export function matchBand(seconds: number): number {
  const b = 100 + 50 * idiv(seconds, 5);
  return b > 400 ? 400 : b;
}

export const GHOST_AFTER_SECONDS = 20;
