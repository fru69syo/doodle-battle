/// Bundled CPU doodles (`app/assets/cpu/manifest.json`, produced by Vision)
/// and how a CPU stage turns one into a fighter.
library;

import '../element_type.dart';
import '../stats.dart';
import 'battle_engine.dart';
import 'battle_spec.dart';
import 'growth.dart';

/// One entry of the CPU manifest (Lv1 stats from the on-device analyzer).
class CpuCharacter {
  const CpuCharacter({
    required this.id,
    required this.name,
    required this.asset,
    required this.element,
    required this.energy,
    required this.skill,
    required this.isShobo,
    required this.baseStats,
  });

  final String id;
  final String name;

  /// Asset key of the cut-out PNG.
  final String asset;
  final ElementType element;
  final double energy;
  final double skill;
  final bool isShobo;

  /// Lv1 stats.
  final Stats baseStats;

  factory CpuCharacter.fromJson(Map<String, Object?> j) => CpuCharacter(
    id: j['id']! as String,
    name: j['name']! as String,
    asset: j['asset']! as String,
    element: ElementType.fromName(j['element']! as String),
    energy: (j['energy']! as num).toDouble(),
    skill: (j['skill']! as num).toDouble(),
    isShobo: j['isShobo']! as bool,
    baseStats: Stats.fromJson((j['baseStats']! as Map).cast<String, Object?>()),
  );
}

/// All bundled CPU characters, by id.
class CpuRoster {
  CpuRoster(Iterable<CpuCharacter> characters)
    : byId = {for (final c in characters) c.id: c};

  final Map<String, CpuCharacter> byId;

  factory CpuRoster.fromManifestJson(Map<String, Object?> manifest) =>
      CpuRoster([
        for (final c in manifest['characters']! as List)
          CpuCharacter.fromJson((c as Map).cast<String, Object?>()),
      ]);

  CpuCharacter operator [](String id) =>
      byId[id] ?? (throw ArgumentError.value(id, 'id', 'unknown CPU id'));
}

/// The CPU fighter of [stage]: its doodle's Lv1 stats grown to the stage
/// level with the normal growth rules (no パワーのたね).
FighterSetup cpuFighterSetup(
  BattleSpec spec,
  CpuStage stage,
  CpuRoster roster,
) {
  final c = roster[stage.cpuId];
  return FighterSetup(
    element: c.element,
    level: stage.level,
    stats: statsAtLevel(
      spec,
      c.baseStats,
      stage.level,
      const {},
      isShobo: c.isShobo,
    ),
  );
}
