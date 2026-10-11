/// Levels, XP, growth events, rewarded-ad rule, rated play (Lv50 sync,
/// Elo with provisional K, kid-friendly badges) and family battles.
/// docs/GAME_DESIGN_V2.md §4, §7, §8. Pure functions, integer maths.
library;

import 'spec.dart';

/// XP needed to go from [level] to level+1.
int xpToNext(V3Spec s, int level) =>
    s.xpBase +
    s.xpPerLevel * level +
    s.xpQuadNum * level * level ~/ s.xpQuadDen;

/// Total XP from Lv1 to [level].
int totalXpTo(V3Spec s, int level) {
  var t = 0;
  for (var l = 1; l < level; l++) {
    t += xpToNext(s, l);
  }
  return t;
}

/// Evolution milestones (visual only; no stat bonus).
const Map<int, String> kEvolutions = {
  10: 'kagayaki',
  25: 'kirakira',
  50: 'densetsu',
  75: 'niji',
  100: 'oukan',
};

// --- XP per battle ---------------------------------------------------------

/// Single-player XP. [stage] 1..100, [level] = player's level.
/// replay factor: stage ≥ level−10 → 100 %, ≥ level−20 → 50 %, else 20 %.
/// [firstClear] ×2, [adBoost] ×2 (3/day, counted by the caller).
/// [hiddenBloomer] (bloomers below Lv50 only; never shown): ×2 and no replay
/// reduction — they are weaker than their level, so they can only win low
/// stages; without this they could not reach the Lv50 rebirth.
int xpSinglePlayer({
  required bool win,
  required int stage,
  required int level,
  bool firstClear = false,
  bool adBoost = false,
  bool hiddenBloomer = false,
}) {
  final base = win ? 100 : 40;
  final stagePct = 100 + 4 * (stage - 1);
  final gap = level - stage;
  final replayPct = hiddenBloomer || gap <= 10 ? 100 : (gap <= 20 ? 50 : 20);
  var xp = base * stagePct * replayPct ~/ 10000;
  if (firstClear && win) xp *= 2;
  if (hiddenBloomer) xp *= 2;
  if (adBoost) xp *= 2;
  return xp;
}

/// Online XP (server-computed): win 150 / lose 60 scaled by level like a
/// stage at the player's level, only for the first [kOnlineXpBattlesPerDay]
/// rated battles of the day, never for the same opponent twice within an
/// hour, never for forfeits/disconnect losses. No ad boost online.
const int kOnlineXpBattlesPerDay = 20;
int xpOnline({
  required bool win,
  required int level,
  required bool eligible,
  bool hiddenBloomerBonus = false,
}) {
  if (!eligible) return 0;
  var xp = (win ? 150 : 60) * (100 + 4 * (level - 1)) ~/ 100;
  if (hiddenBloomerBonus) xp = xp * 150 ~/ 100;
  return xp;
}

// --- Rated play ----------------------------------------------------------------

/// Rated battles are fought at this level (stats re-computed at the sync
/// level with the character's own growth; moves = those actually unlocked).
const int kRatedSyncLevel = 50;
const int kRatedUnlockLevel = 5;
const int kRatingStart = 1000;
const int kRatingFloor = 600;

/// K-factor: provisional 48 for the first 20 rated games, then 24; ghost
/// matches use half.
int eloK(int gamesPlayed, {bool ghost = false}) {
  final k = gamesPlayed < 20 ? 48 : 24;
  return ghost ? k ~/ 2 : k;
}

/// Expected score ×1000 via a 33-entry logistic table (integer, portable):
/// E = 1/(1+10^(-d/400)) sampled every 50 points for d in [-800, 800],
/// linear in between.
const List<int> _eloTable = [
  10, 13, 17, 23, 31, 40, 53, 70, 91, 118, 151, 192, 240, 297, 360, //
  429, 500, 571, 640, 703, 760, 808, 849, 882, 909, 930, 947, 960, 969, //
  977, 983, 987, 990,
];
int eloExpectedMille(int ratingA, int ratingB) {
  var d = ratingA - ratingB;
  if (d < -800) d = -800;
  if (d > 800) d = 800;
  final x = d + 800;
  final i = x ~/ 50;
  final r = x % 50;
  if (i >= 32) return _eloTable[32];
  return _eloTable[i] + (_eloTable[i + 1] - _eloTable[i]) * r ~/ 50;
}

/// Rating change for A (positive = gain). Result clamped so A stays ≥ floor.
int eloDelta(int ratingA, int ratingB, bool aWon, int k) {
  final e = eloExpectedMille(ratingA, ratingB);
  final sc = aWon ? 1000 : 0;
  final num = k * (sc - e);
  // round half away from zero, portable
  var d = num >= 0 ? (num + 500) ~/ 1000 : -((-num + 500) ~/ 1000);
  if (ratingA + d < kRatingFloor) d = kRatingFloor - ratingA;
  return d;
}

/// Badges (hidden rating → visible badge). The shown badge is the best ever
/// reached: it never goes down.
const List<(int, String)> kBadges = [
  (0, 'たまご'),
  (1050, 'ひよこ'),
  (1150, 'うさぎ'),
  (1250, 'きつね'),
  (1350, 'くま'),
  (1450, 'ライオン'),
  (1600, 'ドラゴン'),
  (1800, 'でんせつ'),
];

String badgeFor(int bestRating) {
  var b = kBadges.first.$2;
  for (final (min, name) in kBadges) {
    if (bestRating >= min) b = name;
  }
  return b;
}

/// Matchmaking band (± rating) after waiting [seconds]; ghost at 20 s.
int matchBand(int seconds) {
  final b = 100 + 50 * (seconds ~/ 5);
  return b > 400 ? 400 : b;
}

const int kGhostAfterSeconds = 20;

// --- Family battles ------------------------------------------------------------

/// Family battles give no XP (docs/FAMILY.md: practice battles).
const int kFamilyBattleXp = 0;

/// Level a family-battle side fights at: the higher of both levels when
/// [sameLevel], else its own, plus its handicap boost, within 1..maxLevel.
int familyBattleLevel(
  V3Spec s, {
  required int ownLevel,
  required int otherLevel,
  required bool sameLevel,
  int boost = 0,
}) {
  final base = sameLevel && otherLevel > ownLevel ? otherLevel : ownLevel;
  final l = base + boost;
  return l > s.maxLevel ? s.maxLevel : (l < 1 ? 1 : l);
}

// --- Rewarded ad (×2 XP) -------------------------------------------------------

/// Rewarded ads per day (SPEC §12.1) — Android only (SPEC §12.6: no ads on
/// iPhone), parent-approved, single-player battles only.
const int kAdBoostsPerDay = 3;

enum AppPlatform { android, ios, other }

/// Whether the ×2 rewarded-ad offer may be shown after a single-player
/// battle.
bool adBoostAvailable({
  required AppPlatform platform,
  required bool parentAllowsAds,
  required int usedToday,
}) =>
    platform == AppPlatform.android &&
    parentAllowsAds &&
    usedToday < kAdBoostsPerDay;

// --- Levelling -------------------------------------------------------------------

/// Move slots unlocked at [level] (2, 3 at Lv10, 4 at Lv50).
int unlockedSlots(V3Spec s, int level) =>
    s.slotUnlockLevels.where((l) => level >= l).length;

/// Result of [applyXp]. [rebirth] is INTERNAL (hidden late bloomer reached
/// its rebirth level): callers regenerate the move set and must not show
/// anything different from a normal Lv50 evolution.
class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.xp,
    required this.fromLevel,
    required this.newSlots,
    required this.evolutions,
    required this.rebirth,
  });

  final int level;

  /// XP towards the next level (0 at the max level).
  final int xp;
  final int fromLevel;

  /// Slot indices (0-based) unlocked by this gain.
  final List<int> newSlots;

  /// Evolution ids reached ([kEvolutions]).
  final List<String> evolutions;

  /// INTERNAL — never surface.
  final bool rebirth;

  bool get levelledUp => level > fromLevel;
}

/// Adds [gained] XP to a character at [level] with [xp] towards the next
/// level. [isBloomer] is INTERNAL (only used to report [LevelProgress.rebirth]).
LevelProgress applyXp(
  V3Spec s, {
  required int level,
  required int xp,
  required int gained,
  bool isBloomer = false,
}) {
  var l = level.clamp(1, s.maxLevel);
  var x = xp < 0 ? 0 : xp;
  if (gained > 0) x += gained;
  while (l < s.maxLevel && x >= xpToNext(s, l)) {
    x -= xpToNext(s, l);
    l++;
  }
  if (l >= s.maxLevel) x = 0;
  final slots = [
    for (var i = 0; i < s.slotUnlockLevels.length; i++)
      if (s.slotUnlockLevels[i] > level && s.slotUnlockLevels[i] <= l) i,
  ];
  final evo = [
    for (final e in kEvolutions.entries)
      if (e.key > level && e.key <= l) e.value,
  ];
  return LevelProgress(
    level: l,
    xp: x,
    fromLevel: level,
    newSlots: slots,
    evolutions: evo,
    rebirth: isBloomer && level < s.rebirthLevel && l >= s.rebirthLevel,
  );
}

// --- Rated sync (pure rule) -------------------------------------------------------

/// How a character is fielded in rated play (§8): stats at [syncLevel] with
/// its own growth (a bloomer below its rebirth level keeps its pre-rebirth
/// form), moves = the slots unlocked at its actual level, move budget of the
/// sync level (or the pre-rebirth factor).
class RatedSync {
  const RatedSync({
    required this.statLevel,
    required this.preForm,
    required this.slotCount,
    required this.moveStream,
  });

  final int statLevel;

  /// INTERNAL — bloomer fielded in its pre-rebirth form.
  final bool preForm;
  final int slotCount;

  /// Offline move stream (12, or 14 after the rebirth).
  final int moveStream;
}

RatedSync ratedSync(
  V3Spec s, {
  required int actualLevel,
  required bool isBloomer,
  int syncLevel = kRatedSyncLevel,
}) {
  final pre = isBloomer && actualLevel < s.rebirthLevel;
  final reborn = isBloomer && actualLevel >= s.rebirthLevel;
  return RatedSync(
    statLevel: syncLevel,
    preForm: pre,
    slotCount: unlockedSlots(s, actualLevel),
    moveStream: reborn ? 14 : 12,
  );
}
