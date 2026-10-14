/// The battle part of the Before/After video (docs/VIDEO.md §3): a short,
/// scripted fight against a CPU doodle, played with the real battle engine
/// v3 so damage, effectiveness and HP are exactly what the game would show.
library;

import '../../domain/battle_v3/battle_v3.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../../domain/cosmetics.dart';
import '../../domain/cpu_roster_v2.dart';

/// One attack shown in the video.
class HighlightHit {
  const HighlightHit({
    required this.move,
    required this.moveLabel,
    required this.damage,
    required this.targetHpBefore,
    required this.targetHpAfter,
    required this.attackerHp,
    required this.superEffective,
    required this.crit,
    required this.faint,
  });

  /// Which drawn effect (if any) this move flies (slot 1 = ぞくせいわざ).
  final DrawnMove move;
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

  final CpuCharacterV2 cpu;
  final int cpuLevel;
  final int playerMaxHp;
  final int cpuMaxHp;

  /// Player hits in order (at least one; the last may be the KO).
  final List<HighlightHit> hits;

  /// 「こうかは ばつぐんだ！」.
  final String superText;

  /// Battle seed that produced this script (for reproducibility).
  final int seed;

  bool get endsWithKo => hits.isNotEmpty && hits.last.faint;
}

/// Seeds tried when looking for a good-looking fight.
const int kHighlightSeedTries = 24;

/// CPU stats in the video (a little weaker so the child's drawing shines).
const int kHighlightCpuPowerPct = 85;

/// Picks a CPU doodle the player's attribute beats (deterministic per
/// character) and plays battles with engine v3 until one shows a
/// super-effective slot-1 hit, ideally ending in a KO by the player. The
/// player always uses slot 1 (its own attribute, always usable); the CPU
/// uses its slot 1 too. Null only when the player never landed a hit.
BattleHighlight? scriptBattleHighlight({
  required CpuRosterV2 roster,
  required CharacterV2 player,
  V3Spec spec = const V3Spec(),
}) {
  final cpu = pickHighlightOpponent(roster, player, spec: spec);
  if (cpu == null) return null;
  final level = player.level;
  final a = player.battleSetup(s: spec);
  final b = setupAt(
    spec,
    cpu.genome(spec),
    level,
    powerPct: kHighlightCpuPowerPct,
    label: cpu.name,
  );
  final label = moveDisplayName(a.moves[0]);
  BattleHighlight? fallback;
  BattleHighlight? best;
  var bestTicks = 1 << 30;
  for (var seed = 1; seed <= kHighlightSeedTries; seed++) {
    final battle = Battle(spec, a, b, seed: seed);
    int? slot0(Battle _, int _) => 0;
    while (!battle.finished) {
      battle.step(a: slot0, b: slot0);
    }
    final hits = _playerHits(battle, label);
    if (hits.isEmpty) continue;
    final ko = battle.winner == 0 && battle.endReason == 'ko';
    final first = hits.first;
    final h = BattleHighlight(
      cpu: cpu,
      cpuLevel: level,
      playerMaxHp: battle.fighters[0].maxHp,
      cpuMaxHp: battle.fighters[1].maxHp,
      hits: ko && !first.faint ? [first, hits.last] : [first],
      superText: 'こうかは ばつぐんだ！',
      seed: seed,
    );
    if (!first.superEffective || !ko) {
      fallback ??= h;
      continue;
    }
    if (battle.tick < bestTicks) {
      best = h;
      bestTicks = battle.tick;
    }
  }
  return best ?? fallback;
}

/// The CPU used in the video: one whose attribute the player's attribute
/// beats, chosen deterministically from the character id.
CpuCharacterV2? pickHighlightOpponent(
  CpuRosterV2 roster,
  CharacterV2 player, {
  V3Spec spec = const V3Spec(),
}) {
  final all = roster.byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  if (all.isEmpty) return null;
  final beats = player.attribute(spec).beats;
  final weak = [
    for (final c in all)
      if (c.genome(spec).attr == beats) c,
  ];
  final pool = weak.isEmpty ? all : weak;
  var h = 0;
  for (final u in player.id.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return pool[h % pool.length];
}

/// Hits landed by side 0, from the battle's event log.
List<HighlightHit> _playerHits(Battle battle, String label) {
  final out = <HighlightHit>[];
  var cpuHp = battle.fighters[1].maxHp;
  var playerHp = battle.fighters[0].maxHp;
  for (final e in battle.events) {
    if (e.type != 'hit') continue;
    final hp = e.i('hp') ?? 0;
    if (e.i('target') == 0) {
      playerHp = hp;
      continue;
    }
    out.add(
      HighlightHit(
        move: DrawnMove.element,
        moveLabel: label,
        damage: e.i('amount') ?? 0,
        targetHpBefore: cpuHp,
        targetHpAfter: hp,
        attackerHp: playerHp,
        superEffective: (e.i('pct') ?? 100) > 100,
        crit: e.i('crit') == 1,
        faint: hp <= 0,
      ),
    );
    cpuHp = hp;
  }
  return out;
}
