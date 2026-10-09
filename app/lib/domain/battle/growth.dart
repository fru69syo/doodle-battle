/// Levelling, XP, パワーのたね and evolution (SPEC §4.2). Mirrors
/// `shared/battle_engine_ts/src/growth.ts`.
library;

import '../character.dart';
import '../stats.dart';
import 'battle_engine.dart';
import 'battle_spec.dart';

/// Stats at [level] with [seeds] allocated, from Lv1 [base] stats:
/// `floor(base * (100 + levelUpStatPct*(level-1) + seedStatPct*seeds) / 100)`,
/// minimum 1.
Stats statsAtLevel(
  BattleSpec spec,
  Stats base,
  int level,
  Map<StatKind, int> seeds,
) {
  int one(int b, StatKind k) {
    final pct =
        100 +
        spec.growth.levelUpStatPct * (level - 1) +
        spec.growth.seedStatPct * (seeds[k] ?? 0);
    final v = (b * pct) ~/ 100;
    return v < 1 ? 1 : v;
  }

  return Stats(
    hp: one(base.hp, StatKind.hp),
    atk: one(base.atk, StatKind.atk),
    def: one(base.def, StatKind.def),
    spd: one(base.spd, StatKind.spd),
  );
}

/// Current battle stats of [c] (level growth + seeds).
Stats currentStats(BattleSpec spec, Character c) =>
    statsAtLevel(spec, c.baseStats, c.level, c.seedAllocations);

/// Upper bound of each stat at [level] (all seeds in that stat). Used by the
/// server to reject tampered stats.
Stats maxStatsAtLevel(BattleSpec spec, Stats base, int level) {
  final seeds = (level - 1) * spec.growth.seedsPerLevel;
  return statsAtLevel(spec, base, level, {
    for (final k in StatKind.values) k: seeds,
  });
}

/// Battle setup for a character.
FighterSetup fighterSetupFor(BattleSpec spec, Character c) => FighterSetup(
  element: c.element,
  level: c.level,
  stats: currentStats(spec, c),
);

/// XP needed to go from [level] to level+1 (`50 + 25 * level`).
int xpToNext(BattleSpec spec, int level) =>
    spec.growth.xpToNextBase + spec.growth.xpToNextPerLevel * level;

/// Evolution stage at [level] according to the spec.
EvolutionStage stageAtLevel(BattleSpec spec, int level) {
  var stage = EvolutionStage.normal;
  for (final e in spec.growth.evolutions) {
    if (level >= e.level) stage = e.stage;
  }
  return stage;
}

/// XP earned by one battle:
/// `floor(base * stagePct * (100 + shoboBonusPct if shobo) * (adBoost ? m : 1) / 10000)`.
int xpForBattle(
  BattleSpec spec, {
  required bool won,
  required bool isShobo,
  int stageXpMultiplierPct = 100,
  bool adBoost = false,
}) {
  final base = won ? spec.xp.win : spec.xp.lose;
  final shoboPct = 100 + (isShobo ? spec.xp.shoboBonusPct : 0);
  final ad = adBoost ? spec.xp.adBoostMultiplier : 1;
  return (base * stageXpMultiplierPct * shoboPct * ad) ~/ 10000;
}

/// Outcome of adding XP.
class XpProgress {
  const XpProgress({
    required this.level,
    required this.xp,
    required this.levelsGained,
    required this.seedsGained,
    required this.evolutions,
  });

  final int level;

  /// XP towards the next level (always 0 at max level).
  final int xp;
  final int levelsGained;
  final int seedsGained;

  /// Evolution stages newly reached, in order.
  final List<EvolutionStage> evolutions;

  Map<String, Object?> toJson() => {
    'level': level,
    'xp': xp,
    'levelsGained': levelsGained,
    'seedsGained': seedsGained,
    'evolutions': [for (final e in evolutions) e.name],
  };
}

/// Adds [gained] XP to a character at [level] with [xp] carried over.
/// Multiple level-ups are applied; at max level the leftover is discarded.
XpProgress addXp(
  BattleSpec spec, {
  required int level,
  required int xp,
  required int gained,
}) {
  final max = spec.growth.maxLevel;
  var lv = level;
  var cur = lv >= max ? 0 : xp + gained;
  final evolutions = <EvolutionStage>[];
  while (lv < max && cur >= xpToNext(spec, lv)) {
    cur -= xpToNext(spec, lv);
    lv++;
    for (final e in spec.growth.evolutions) {
      if (e.level == lv) evolutions.add(e.stage);
    }
  }
  if (lv >= max) cur = 0;
  return XpProgress(
    level: lv,
    xp: cur,
    levelsGained: lv - level,
    seedsGained: (lv - level) * spec.growth.seedsPerLevel,
    evolutions: evolutions,
  );
}

/// Result of [applyXp].
class XpResult {
  const XpResult({
    required this.character,
    required this.xpGained,
    required this.progress,
    required this.reachedMaxLevel,
  });

  final Character character;
  final int xpGained;
  final XpProgress progress;

  int get levelsGained => progress.levelsGained;
  int get seedsGained => progress.seedsGained;
  List<EvolutionStage> get evolutions => progress.evolutions;

  /// True when this battle took the character to the max level.
  final bool reachedMaxLevel;
}

/// Awards XP for one battle to [c].
XpResult applyXp(
  BattleSpec spec,
  Character c, {
  required bool won,
  int stageXpMultiplierPct = 100,
  bool adBoost = false,
}) {
  final gained = xpForBattle(
    spec,
    won: won,
    isShobo: c.isShobo,
    stageXpMultiplierPct: stageXpMultiplierPct,
    adBoost: adBoost,
  );
  final p = addXp(spec, level: c.level, xp: c.xp, gained: gained);
  return XpResult(
    character: c.copyWith(level: p.level, xp: p.xp),
    xpGained: gained,
    progress: p,
    reachedMaxLevel: p.levelsGained > 0 && p.level == spec.growth.maxLevel,
  );
}

/// Unspent パワーのたね: `(level - 1) * seedsPerLevel - allocated`.
int seedsAvailable(BattleSpec spec, Character c) {
  final allocated = c.seedAllocations.values.fold<int>(0, (a, b) => a + b);
  return (c.level - 1) * spec.growth.seedsPerLevel - allocated;
}

/// Spends one パワーのたね on [stat]. Throws [StateError] if none is left.
Character allocateSeed(BattleSpec spec, Character c, StatKind stat) {
  if (seedsAvailable(spec, c) <= 0) {
    throw StateError('no パワーのたね available');
  }
  return c.copyWith(
    seedAllocations: {
      ...c.seedAllocations,
      stat: (c.seedAllocations[stat] ?? 0) + 1,
    },
  );
}
