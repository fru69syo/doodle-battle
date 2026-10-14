import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_state.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import 'new_moves.dart';

/// What the result screen shows after a single-player or online battle.
class BattleOutcome {
  const BattleOutcome({
    required this.characterId,
    required this.won,
    required this.xpGained,
    required this.levelBefore,
    required this.levelAfter,
    this.newSlots = const [],
    this.evolutions = const [],
    this.stage,
    this.stars = 0,
    this.adBonusXp = 0,
    this.online = false,
    this.badge,
    this.badgeUp = false,
    this.aborted = false,
  });

  final String characterId;
  final bool won;
  final int xpGained;
  final int levelBefore;
  final int levelAfter;

  /// Move slots (0-based) unlocked by this battle (Lv10 → 2, Lv50 → 3).
  final List<int> newSlots;

  /// Evolution ids reached (`kagayaki` … `oukan`).
  final List<String> evolutions;

  /// Single-player stage (null online / family).
  final int? stage;

  /// Stars of this battle (1–3 when won).
  final int stars;

  /// Extra XP a rewarded ad would give (single-player only).
  final int adBonusXp;
  final bool online;

  /// Online: best badge id (`egg` … `legend`) and whether it just went up.
  final String? badge;
  final bool badgeUp;

  /// Online match stopped by the server (no result).
  final bool aborted;

  bool get leveledUp => levelAfter > levelBefore;

  BattleOutcome copyWith({
    int? xpGained,
    int? levelAfter,
    List<int>? newSlots,
    List<String>? evolutions,
    int? adBonusXp,
  }) => BattleOutcome(
    characterId: characterId,
    won: won,
    xpGained: xpGained ?? this.xpGained,
    levelBefore: levelBefore,
    levelAfter: levelAfter ?? this.levelAfter,
    newSlots: newSlots ?? this.newSlots,
    evolutions: evolutions ?? this.evolutions,
    stage: stage,
    stars: stars,
    adBonusXp: adBonusXp ?? this.adBonusXp,
    online: online,
    badge: badge,
    badgeUp: badgeUp,
    aborted: aborted,
  );
}

/// Stars of a won stage (GAME_DESIGN_V2 §7): win, HP ≥ 50 % left, within
/// 60 s.
int stageStars({
  required bool won,
  required int hp,
  required int maxHp,
  required int ticks,
  int tickHz = 10,
}) {
  if (!won) return 0;
  var s = 1;
  if (hp * 2 >= maxHp) s++;
  if (ticks <= 60 * tickHz) s++;
  return s;
}

/// Applies battle rewards to the stored character and progress.
class BattleRewards {
  BattleRewards(this._ref);
  final Ref _ref;

  Future<(CharacterV2, BattleOutcome)> _grant(
    CharacterV2 player,
    int xp,
    BattleOutcome Function(CharacterV2 after, List<int>, List<String>) make,
  ) async {
    final (after, p) = player.gainXp(xp);
    await _ref.read(charactersProvider.notifier).save(after);
    // Lv10 / Lv50: the new move may get an AI-designed name (in the
    // background; the result screen updates when it arrives).
    if (p.namingSlots.isNotEmpty) {
      unawaited(
        _ref.read(newMoveNamerProvider).nameNewSlots(after, p.namingSlots),
      );
    }
    return (after, make(after, p.newSlots, p.evolutions));
  }

  /// Single-player battle finished (GAME_DESIGN_V2 §4.2, §7).
  Future<BattleOutcome> applyCpuResult({
    required CharacterV2 player,
    required int stage,
    required bool won,
    required int stars,
  }) async {
    final progress = await _ref.read(progressProvider.future);
    final firstClear = won && progress.starsOf(stage) == 0;
    final xp = singlePlayerXpFor(
      player,
      win: won,
      stage: stage,
      firstClear: firstClear,
    );
    final boosted = singlePlayerXpFor(
      player,
      win: won,
      stage: stage,
      firstClear: firstClear,
      adBoost: true,
    );
    final (_, outcome) = await _grant(
      player,
      xp,
      (after, slots, evo) => BattleOutcome(
        characterId: player.id,
        won: won,
        xpGained: xp,
        levelBefore: player.level,
        levelAfter: after.level,
        newSlots: slots,
        evolutions: evo,
        stage: stage,
        stars: stars,
        adBonusXp: boosted - xp,
      ),
    );
    if (won) {
      await _ref.read(progressProvider.notifier).recordStageWin(stage, stars);
    }
    return outcome;
  }

  /// Online match finished: the server decided the XP; applied once per
  /// [matchId] (a reconnect may deliver `end` twice). Null when already
  /// applied.
  Future<BattleOutcome?> applyOnlineResult({
    required CharacterV2 player,
    required String matchId,
    required int xp,
    required bool won,
    String? badge,
    bool badgeUp = false,
  }) async {
    final progress = _ref.read(progressProvider.notifier);
    if (!await progress.markMatchApplied(matchId)) return null;
    if (badge != null) await progress.setOnlineBadge(badge);
    final (_, outcome) = await _grant(
      player,
      xp,
      (after, slots, evo) => BattleOutcome(
        characterId: player.id,
        won: won,
        xpGained: xp,
        levelBefore: player.level,
        levelAfter: after.level,
        newSlots: slots,
        evolutions: evo,
        online: true,
        badge: badge,
        badgeUp: badgeUp,
      ),
    );
    return outcome;
  }

  /// Rewarded-ad bonus (Android, parent-approved, 3 a day).
  Future<BattleOutcome> applyAdBonus(BattleOutcome outcome) async {
    final c = _ref.read(characterByIdProvider(outcome.characterId));
    if (c == null || outcome.adBonusXp <= 0) return outcome;
    final (_, bonus) = await _grant(
      c,
      outcome.adBonusXp,
      (after, slots, evo) => outcome.copyWith(
        xpGained: outcome.xpGained + outcome.adBonusXp,
        levelAfter: after.level,
        newSlots: [...outcome.newSlots, ...slots],
        evolutions: [...outcome.evolutions, ...evo],
        adBonusXp: 0,
      ),
    );
    return bonus;
  }
}

final battleRewardsProvider = Provider<BattleRewards>(BattleRewards.new);
