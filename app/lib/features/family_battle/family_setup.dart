/// かぞくで たいせん (SPEC §11.2-2): same-device battles between family
/// members. Pure logic: players, handicap and the engine setups they map to.
/// See docs/FAMILY.md.
library;

import '../../domain/battle_v3/battle_v3.dart';
import '../../domain/character_v2.dart';

/// The two players: あか (a, bottom, side 0) and あお (b, top, side 1).
enum FamilySide {
  a,
  b;

  FamilySide get other => this == a ? b : a;
}

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
String familySideColour(FamilySide side) => side == FamilySide.a ? 'あか' : 'あお';

/// One of the two players sharing the device.
class FamilyPlayer {
  const FamilyPlayer({
    required this.label,
    required this.character,
    this.boost = 0,
  });

  /// Preset name from [familyPlayerLabels].
  final String label;
  final CharacterV2 character;

  /// ハンデ: extra levels for this battle only (never saved).
  final int boost;

  FamilyPlayer copyWith({String? label, CharacterV2? character, int? boost}) =>
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

  FamilyPlayer player(FamilySide side) => side == FamilySide.a ? a : b;

  FamilyBattleConfig copyWith({
    FamilyPlayer? a,
    FamilyPlayer? b,
    bool? sameLevel,
  }) => FamilyBattleConfig(
    a: a ?? this.a,
    b: b ?? this.b,
    sameLevel: sameLevel ?? this.sameLevel,
  );

  /// Level [side] fights at ([familyBattleLevel]: its own level, or the
  /// higher of the two with [sameLevel], plus its boost, ≤ Lv100).
  int battleLevel(FamilySide side, {V3Spec spec = const V3Spec()}) =>
      familyBattleLevel(
        spec,
        ownLevel: player(side).character.level,
        otherLevel: player(side.other).character.level,
        sameLevel: sameLevel,
        boost: player(side).boost,
      );

  /// Engine setup of [side]: the character at its battle level
  /// (`CharacterV2.familyBattleSetup`). Family battles give no XP.
  FighterSetup setup(FamilySide side) =>
      player(side).character.familyBattleSetup(battleLevel(side));

  /// Name shown in battle messages. In a mirror match (same name on both
  /// sides) the team colour is appended so 「ねこまるの たいあたり！」 stays
  /// unambiguous.
  String fighterName(FamilySide side) {
    final name = player(side).character.name;
    if (a.character.name != b.character.name) return name;
    return '$name（${familySideColour(side)}）';
  }
}
