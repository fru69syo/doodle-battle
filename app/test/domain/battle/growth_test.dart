import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:flutter_test/flutter_test.dart';

import '_support.dart';

Character ch({
  int level = 1,
  int xp = 0,
  double skill = 20,
  Map<StatKind, int> seeds = const {},
}) => Character(
  id: 'c',
  name: 'もこ',
  imagePath: '/x.png',
  imageHash: 'h',
  element: ElementType.fire,
  baseStats: const Stats(hp: 100, atk: 50, def: 75, spd: 20),
  energy: 80,
  skill: skill,
  features: const {},
  createdAt: DateTime.utc(2026),
  level: level,
  xp: xp,
  seedAllocations: seeds,
);

void main() {
  final spec = loadSpecFromFile();

  test('xpToNext = 50 + 25L', () {
    expect(xpToNext(spec, 1), 75);
    expect(xpToNext(spec, 10), 300);
  });

  test('currentStats: +4% per level and +3% per seed from Lv1 stats', () {
    expect(
      currentStats(spec, ch()),
      const Stats(hp: 100, atk: 50, def: 75, spd: 20),
    );
    expect(
      currentStats(spec, ch(level: 11, seeds: {StatKind.atk: 2})),
      const Stats(hp: 140, atk: 73, def: 105, spd: 28),
    );
  });

  test('xp rewards: win/lose, shobo +50%, ad boost x2, stage multiplier', () {
    expect(xpForBattle(spec, won: true, isShobo: false), 100);
    expect(xpForBattle(spec, won: false, isShobo: false), 40);
    expect(xpForBattle(spec, won: true, isShobo: true), 150);
    expect(xpForBattle(spec, won: false, isShobo: true, adBoost: true), 120);
    expect(
      xpForBattle(spec, won: true, isShobo: false, stageXpMultiplierPct: 245),
      245,
    );
  });

  test('applyXp levels up multiple times and reports seeds and evolution', () {
    final r = applyXp(
      spec,
      ch(level: 9, xp: 200),
      won: true,
      stageXpMultiplierPct: 245,
      adBoost: true,
    );
    expect(r.xpGained, 490);
    // Lv9 needs 275 -> Lv10 (415 left), Lv10 needs 300 -> Lv11 (115 left).
    expect(r.character.level, 11);
    expect(r.character.xp, 115);
    expect(r.levelsGained, 2);
    expect(r.seedsGained, 2);
    expect(r.evolutions, [EvolutionStage.kagayaki]);
    expect(r.character.stage, EvolutionStage.kagayaki);
    expect(r.reachedMaxLevel, isFalse);
  });

  test('shobo character gets +50% XP through applyXp', () {
    final r = applyXp(spec, ch(skill: 90), won: true);
    expect(r.character.isShobo, isTrue);
    expect(r.xpGained, 150);
    expect(r.character.level, 2);
    expect(r.character.xp, 75);
  });

  test('max level: leftover XP discarded, no further gain', () {
    final r = applyXp(
      spec,
      ch(level: 29, xp: 700),
      won: true,
      stageXpMultiplierPct: 245,
      adBoost: true,
    );
    expect(r.character.level, 30);
    expect(r.character.xp, 0);
    expect(r.reachedMaxLevel, isTrue);
    final again = applyXp(spec, r.character, won: true);
    expect(again.character.level, 30);
    expect(again.character.xp, 0);
    expect(again.levelsGained, 0);
    expect(again.reachedMaxLevel, isFalse);
  });

  test('seeds: available = level-1 minus allocated; allocate spends one', () {
    var c = ch(level: 3);
    expect(seedsAvailable(spec, c), 2);
    c = allocateSeed(spec, c, StatKind.spd);
    c = allocateSeed(spec, c, StatKind.spd);
    expect(c.seedAllocations[StatKind.spd], 2);
    expect(seedsAvailable(spec, c), 0);
    expect(() => allocateSeed(spec, c, StatKind.hp), throwsStateError);
  });

  test('maxStatsAtLevel bounds any legal allocation', () {
    final c = ch(level: 30, seeds: {StatKind.atk: 29});
    final cur = currentStats(spec, c);
    final max = maxStatsAtLevel(spec, c.baseStats, 30);
    expect(cur.atk, max.atk);
    expect(cur.hp, lessThan(max.hp));
  });

  test('fighterSetupFor uses current stats and evolution', () {
    final c = ch(level: 20);
    final s = initBattle(
      spec,
      fighterSetupFor(spec, c),
      fighterSetupFor(spec, c),
    );
    expect(s.a.maxHp, currentStats(spec, c).hp * spec.hpMultiplier);
    expect(s.a.specialPower, 140);
    expect(stageAtLevel(spec, 20), EvolutionStage.densetsu);
    expect(stageAtLevel(spec, 10), EvolutionStage.kagayaki);
    expect(stageAtLevel(spec, 9), EvolutionStage.normal);
  });
}
