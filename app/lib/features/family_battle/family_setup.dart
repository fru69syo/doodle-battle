/// かぞくで たいせん (SPEC §11.2-2): same-device battles between family
/// members. Pure logic: players, handicap and the engine setups they map to.
/// See docs/FAMILY.md.
library;

import '../../domain/battle/battle.dart';
import '../../domain/character.dart';

/// Preset player names (no free text: nothing typed by a child is shown, so
/// no NG check is needed). The first two are the defaults of the slots.
const familyPlayerLabels = [
  'あか チーム',
  'あお チーム',
  'おとうさん',
  'おかあさん',
  'おにいちゃん',
  'おねえちゃん',
  'おとうと',
  'いもうと',
  'おじいちゃん',
  'おばあちゃん',
  'ぼく',
  'わたし',
];

/// Level boosts a player may be given as ハンデ (0 = none).
const familyBoostChoices = [0, 3, 5, 10];

/// Short colour word of a side, used to tell a mirror match apart.
String familySideColour(Side side) => side == Side.a ? 'あか' : 'あお';

/// One of the two players sharing the device.
class FamilyPlayer {
  const FamilyPlayer({
    required this.label,
    required this.character,
    this.boost = 0,
  });

  /// Preset name from [familyPlayerLabels].
  final String label;
  final Character character;

  /// ハンデ: extra levels for this battle only (never saved).
  final int boost;

  FamilyPlayer copyWith({String? label, Character? character, int? boost}) =>
      FamilyPlayer(
        label: label ?? this.label,
        character: character ?? this.character,
        boost: boost ?? this.boost,
      );
}

/// Everything a family battle needs: two players (side a = あか, side b =
/// あお) and the handicap options.
class FamilyBattleConfig {
  const FamilyBattleConfig({
    required this.a,
    required this.b,
    this.sameLevel = true,
  });

  final FamilyPlayer a;
  final FamilyPlayer b;

  /// 「おなじ レベルで たたかう」: the lower-level character fights at the
  /// higher one's level (on by default).
  final bool sameLevel;

  FamilyPlayer player(Side side) => side == Side.a ? a : b;

  FamilyBattleConfig copyWith({
    FamilyPlayer? a,
    FamilyPlayer? b,
    bool? sameLevel,
  }) => FamilyBattleConfig(
    a: a ?? this.a,
    b: b ?? this.b,
    sameLevel: sameLevel ?? this.sameLevel,
  );

  /// Level [side] fights at: its own level (or the higher of the two with
  /// [sameLevel]) plus its boost, capped at the spec's max level.
  int battleLevel(BattleSpec spec, Side side) {
    final own = player(side).character.level;
    final base = sameLevel
        ? (a.character.level > b.character.level
              ? a.character.level
              : b.character.level)
        : own;
    final l = base + player(side).boost;
    final max = spec.growth.maxLevel;
    return l > max ? max : (l < 1 ? 1 : l);
  }

  /// Engine setup of [side] (see [familyFighterSetup]).
  FighterSetup setup(BattleSpec spec, Side side) =>
      familyFighterSetup(spec, player(side).character, battleLevel(spec, side));

  /// Name shown in battle messages. In a mirror match (same name on both
  /// sides) the team colour is appended so 「ねこまるの たいあたり！」 stays
  /// unambiguous.
  String fighterName(Side side) {
    final name = player(side).character.name;
    if (a.character.name != b.character.name) return name;
    return '$name（${familySideColour(side)}）';
  }
}

/// [c] as it would be at [level], using the normal growth rules
/// (`statsAtLevel`, same growth rate and spent パワーのたね as the character
/// itself), so the engine sees an ordinary, valid setup. Only levels are
/// changed by a handicap; nothing is saved.
FighterSetup familyFighterSetup(BattleSpec spec, Character c, int level) =>
    FighterSetup(
      element: c.element,
      level: level,
      stats: statsAtLevel(
        spec,
        c.baseStats,
        level,
        c.seedAllocations,
        isShobo: isShoboSkill(spec, c.skill),
      ),
    );
