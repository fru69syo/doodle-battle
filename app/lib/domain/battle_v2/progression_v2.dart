/// PROTOTYPE — v2 levels / XP, single-player stage table, rated play
/// (Elo with provisional K, kid-friendly badges, level sync).
/// docs/GAME_DESIGN_V2.md §4, §7, §8.
library;

import 'v2_spec.dart';

/// XP needed to go from [level] to level+1.
int xpToNext(V2Spec s, int level) =>
    s.xpBase +
    s.xpPerLevel * level +
    s.xpQuadNum * level * level ~/ s.xpQuadDen;

/// Total XP from Lv1 to [level].
int totalXpTo(V2Spec s, int level) {
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

// --- Stages -------------------------------------------------------------------

class StageV2 {
  const StageV2(
    this.stage,
    this.world,
    this.recommendedLevel,
    this.cpuLevel,
    this.tier, {
    this.boss = false,
    this.cpuPowerPct = 100,
  });
  final int stage;
  final int world;
  final int recommendedLevel;
  final int cpuLevel;

  /// 0 weak, 1 normal, 2 strong.
  final int tier;
  final bool boss;

  /// CPU stats are scaled by this % (difficulty within a world).
  final int cpuPowerPct;
  Map<String, Object?> toJson() => {
    'stage': stage,
    'world': world,
    'recommendedLevel': recommendedLevel,
    'cpuLevel': cpuLevel,
    'aiTier': ['weak', 'normal', 'strong'][tier],
    'boss': boss,
    'cpuPowerPct': cpuPowerPct,
  };
}

/// CPU stat scale (%) by position in a world (1..10; 10 = boss). Tuned in
/// v2_sim so a kid at the recommended level wins ≈85 % → 60 %, boss ≈50 %.
const List<int> kStagePowerPct = [88, 89, 90, 91, 92, 93, 94, 95, 96, 98];

const List<String> kWorldNames = [
  'らくがき のはら',
  'クレヨン もり',
  'えのぐ うみ',
  'いろえんぴつ やま',
  'ペンギン こおり',
  'マーカー まち',
  'ねんど さばく',
  'はさみ おしろ',
  'にじいろ そら',
  'まっしろ ノート',
];

/// 100 stages, 10 worlds × 10; stage n recommends Lv n; the CPU is Lv n
/// with [kStagePowerPct] of its stats.
List<StageV2> stageTable() => [
  for (var n = 1; n <= 100; n++)
    StageV2(
      n,
      (n - 1) ~/ 10 + 1,
      n,
      n,
      n <= 20 ? 0 : (n <= 60 ? 1 : 2),
      boss: n % 10 == 0,
      cpuPowerPct: kStagePowerPct[(n - 1) % 10],
    ),
];

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
