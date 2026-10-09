import '../../domain/battle/battle.dart';
import '../../domain/character.dart';

/// A CPU doodle as a domain [Character] for display (name, picture,
/// element, level, move labels). Its battle stats come from
/// `cpuFighterSetup` (Battle team), not from this object.
Character cpuDisplayCharacter(CpuCharacter c, CpuStage stage) => Character(
  id: c.id,
  name: c.name,
  imagePath: c.asset,
  imageHash: '',
  element: c.element,
  baseStats: c.baseStats,
  energy: c.energy,
  skill: c.skill,
  features: const {},
  createdAt: DateTime.utc(2026),
  level: stage.level,
);
