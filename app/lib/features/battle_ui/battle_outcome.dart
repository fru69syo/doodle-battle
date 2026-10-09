import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_state.dart';
import '../../domain/battle/battle.dart';
import '../../domain/character.dart';

/// What the result screen shows after a CPU (or online) battle.
class BattleOutcome {
  const BattleOutcome({
    required this.characterId,
    required this.won,
    required this.xpGained,
    required this.levelBefore,
    required this.levelAfter,
    required this.seedsGained,
    required this.evolutions,
    this.stage,
    this.draw = false,
    this.stageXpMultiplierPct = 100,
    this.online = false,
  });

  final String characterId;
  final bool won;
  final bool draw;
  final int xpGained;
  final int levelBefore;
  final int levelAfter;
  final int seedsGained;
  final List<EvolutionStage> evolutions;

  /// CPU stage (null for online).
  final int? stage;
  final int stageXpMultiplierPct;
  final bool online;

  bool get leveledUp => levelAfter > levelBefore;

  /// Adds an XP bonus (rewarded ad) on top of this outcome.
  BattleOutcome plusBonus(XpProgress p, int bonusXp) => BattleOutcome(
    characterId: characterId,
    won: won,
    draw: draw,
    xpGained: xpGained + bonusXp,
    levelBefore: levelBefore,
    levelAfter: p.level,
    seedsGained: seedsGained + p.seedsGained,
    evolutions: [...evolutions, ...p.evolutions],
    stage: stage,
    stageXpMultiplierPct: stageXpMultiplierPct,
    online: online,
  );
}

/// Applies battle rewards to the stored character and progress.
class BattleRewards {
  BattleRewards(this._ref);
  final Ref _ref;

  /// CPU battle finished: XP (SPEC §4.2), stage progress.
  Future<BattleOutcome> applyCpuResult({
    required BattleSpec spec,
    required Character player,
    required CpuStage stage,
    required bool won,
  }) async {
    final r = applyXp(
      spec,
      player,
      won: won,
      stageXpMultiplierPct: stage.xpMultiplierPct,
    );
    await _ref.read(charactersProvider.notifier).save(r.character);
    if (won) {
      await _ref.read(progressProvider.notifier).markStageCleared(stage.stage);
    }
    return BattleOutcome(
      characterId: player.id,
      won: won,
      xpGained: r.xpGained,
      levelBefore: player.level,
      levelAfter: r.character.level,
      seedsGained: r.seedsGained,
      evolutions: r.evolutions,
      stage: stage.stage,
      stageXpMultiplierPct: stage.xpMultiplierPct,
    );
  }

  /// Online match finished: the server decides the XP; applied once per
  /// [matchId]. Returns null when it was already applied.
  Future<BattleOutcome?> applyOnlineResult({
    required BattleSpec spec,
    required Character player,
    required String matchId,
    required int xp,
    required String outcome,
  }) async {
    final progress = _ref.read(progressProvider.notifier);
    if (!await progress.markMatchApplied(matchId)) return null;
    final p = addXp(spec, level: player.level, xp: player.xp, gained: xp);
    await _ref
        .read(charactersProvider.notifier)
        .save(player.copyWith(level: p.level, xp: p.xp));
    return BattleOutcome(
      characterId: player.id,
      won: outcome == 'win',
      draw: outcome == 'draw',
      xpGained: xp,
      levelBefore: player.level,
      levelAfter: p.level,
      seedsGained: p.seedsGained,
      evolutions: p.evolutions,
      online: true,
    );
  }

  /// Rewarded-ad bonus: the boosted XP minus what was already given.
  Future<BattleOutcome> applyAdBonus({
    required BattleSpec spec,
    required BattleOutcome outcome,
  }) async {
    final c = _ref.read(characterByIdProvider(outcome.characterId));
    if (c == null) return outcome;
    final base = outcome.online
        ? outcome.xpGained
        : xpForBattle(
            spec,
            won: outcome.won,
            isShobo: c.isShobo,
            stageXpMultiplierPct: outcome.stageXpMultiplierPct,
          );
    final bonus = base * spec.xp.adBoostMultiplier - base;
    final p = addXp(spec, level: c.level, xp: c.xp, gained: bonus);
    await _ref
        .read(charactersProvider.notifier)
        .save(c.copyWith(level: p.level, xp: p.xp));
    return outcome.plusBonus(p, bonus);
  }
}

final battleRewardsProvider = Provider<BattleRewards>(BattleRewards.new);
