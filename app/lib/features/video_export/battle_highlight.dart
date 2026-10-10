/// The battle part of the Before/After video (docs/VIDEO.md §3): a short,
/// scripted fight against a CPU doodle, played with the real battle engine
/// so damage, effectiveness and HP are exactly what the game would show.
library;

import '../../domain/battle/battle.dart';
import '../../domain/character.dart';
import '../battle_ui/move_labels.dart';

/// One attack shown in the video.
class HighlightHit {
  const HighlightHit({
    required this.action,
    required this.moveLabel,
    required this.damage,
    required this.targetHpBefore,
    required this.targetHpAfter,
    required this.attackerHp,
    required this.superEffective,
    required this.crit,
    required this.faint,
  });

  final BattleAction action;
  final String moveLabel;
  final int damage;
  final int targetHpBefore;
  final int targetHpAfter;

  /// The player's HP when the hit happens (for its HP bar).
  final int attackerHp;
  final bool superEffective;
  final bool crit;

  /// The CPU faints from this hit.
  final bool faint;
}

/// Script of the battle scene: 1–2 hits by the player.
class BattleHighlight {
  const BattleHighlight({
    required this.cpu,
    required this.cpuLevel,
    required this.playerMaxHp,
    required this.cpuMaxHp,
    required this.hits,
    required this.superText,
    required this.seed,
  });

  final CpuCharacter cpu;
  final int cpuLevel;
  final int playerMaxHp;
  final int cpuMaxHp;

  /// Player hits in order (at least one; the last may be the KO).
  final List<HighlightHit> hits;

  /// 「こうかは ばつぐんだ！」 from the battle spec.
  final String superText;

  /// Battle seed that produced this script (for reproducibility).
  final int seed;

  bool get endsWithKo => hits.isNotEmpty && hits.last.faint;
}

/// Seeds tried when looking for a good-looking fight.
const int kHighlightSeedTries = 48;

/// Picks a CPU doodle the player's element beats (deterministic per
/// character) and plays battles with the real engine until one shows a
/// super-effective element hit — ideally ending in a KO by the player.
///
/// The player uses its element move (ひっさつ when the gauge is full); the
/// CPU uses たいあたり. Returns null only when no battle produced a hit by
/// the player (practically impossible: element moves rarely miss).
BattleHighlight? scriptBattleHighlight({
  required BattleSpec spec,
  required CpuRoster roster,
  required Character player,
}) {
  final cpu = pickHighlightOpponent(spec, roster, player);
  if (cpu == null) return null;
  final level = player.level;
  final playerSetup = fighterSetupFor(spec, player);
  final cpuSetup = FighterSetup(
    element: cpu.element,
    level: level,
    stats: statsAtLevel(
      spec,
      cpu.baseStats,
      level,
      const {},
      isShobo: cpu.isShobo,
    ),
  );
  final initial = initBattle(spec, playerSetup, cpuSetup);
  BattleHighlight? fallback;
  BattleHighlight? best;
  var bestTurns = 1 << 30;
  for (var seed = 1; seed <= kHighlightSeedTries; seed++) {
    final run = _play(spec, playerSetup, cpuSetup, seed, player);
    if (run == null) continue;
    final (hits, turns, koByPlayer) = run;
    final first = hits.first;
    final h = BattleHighlight(
      cpu: cpu,
      cpuLevel: level,
      playerMaxHp: initial.a.maxHp,
      cpuMaxHp: initial.b.maxHp,
      hits: koByPlayer && !first.faint ? [first, hits.last] : [first],
      superText: spec.texts['super'] ?? 'こうかは ばつぐんだ！',
      seed: seed,
    );
    if (!first.superEffective) {
      fallback ??= h;
      continue;
    }
    if (!koByPlayer) {
      fallback = fallback == null || !fallback.hits.first.superEffective
          ? h
          : fallback;
      continue;
    }
    if (turns < bestTurns) {
      best = h;
      bestTurns = turns;
    }
  }
  return best ?? fallback;
}

/// The CPU used in the video: one whose element the player's element move
/// is strong against, chosen deterministically from the character id.
CpuCharacter? pickHighlightOpponent(
  BattleSpec spec,
  CpuRoster roster,
  Character player,
) {
  final all = roster.byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  if (all.isEmpty) return null;
  final weak = [
    for (final c in all)
      if (typeMultiplierPct(
            spec,
            BattleAction.element,
            player.element,
            c.element,
          ) >
          spec.typeChart.neutralPct)
        c,
  ];
  final pool = weak.isEmpty ? all : weak;
  var h = 0;
  for (final u in player.id.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return pool[h % pool.length];
}

/// Plays one battle; returns the player's landed hits, the number of turns
/// and whether the player won by KO. Null when the player never hit.
(List<HighlightHit>, int, bool)? _play(
  BattleSpec spec,
  FighterSetup a,
  FighterSetup b,
  int seed,
  Character player,
) {
  var state = initBattle(spec, a, b);
  final rng = Mulberry32(deriveSeed(seed, 0));
  final hits = <HighlightHit>[];
  while (!state.isOver) {
    final ready = state.a.gauge >= spec.gauge.max;
    final action = ready ? BattleAction.special : BattleAction.element;
    final before = state;
    final r = resolveTurn(spec, state, action, BattleAction.tackle, rng);
    state = r.state;
    hits.addAll(_playerHits(spec, r.events, before, player));
  }
  if (hits.isEmpty) return null;
  final ko = state.winner == Side.a && state.endReason == EndReason.ko;
  return (hits, state.turn, ko);
}

/// Hits landed by side a in one turn's [events].
List<HighlightHit> _playerHits(
  BattleSpec spec,
  List<BattleEvent> events,
  BattleState before,
  Character player,
) {
  final out = <HighlightHit>[];
  var cpuHp = before.b.hp;
  var playerHp = before.a.hp;
  BattleAction? move;
  var crit = false;
  var superHit = false;
  for (final e in events) {
    switch (e) {
      case MoveEvent(:final side, move: final m):
        move = side == Side.a ? m : null;
        crit = false;
        superHit = false;
      case CritEvent(:final side) when side == Side.a:
        crit = true;
      case EffectivenessEvent(:final side, :final multiplierPct)
          when side == Side.a:
        superHit = multiplierPct > spec.typeChart.neutralPct;
      case DamageEvent(:final target, :final amount, :final hp):
        if (target == Side.a) {
          playerHp = hp;
        } else if (move != null) {
          out.add(
            HighlightHit(
              action: move,
              moveLabel: characterMoveLabel(player, move),
              damage: amount,
              targetHpBefore: cpuHp,
              targetHpAfter: hp,
              attackerHp: playerHp,
              superEffective: superHit,
              crit: crit,
              faint: hp <= 0,
            ),
          );
          cpuHp = hp;
        }
      default:
        break;
    }
  }
  return out;
}
