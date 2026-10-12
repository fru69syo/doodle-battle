/// What the UI may read from a [CharacterV2] (v2.0). Everything that needs
/// the hidden late-bloomer state (GAME_DESIGN_V2 §4.4) is answered here, in
/// the domain layer, so that `lib/features` never touches it
/// (`test/domain/hidden_state_guard_test.dart`).
library;

import 'battle_v3/battle_v3.dart';
import 'character.dart' show EvolutionStage;
import 'character_v2.dart';
import 'cosmetics.dart';
import 'element_type.dart';

export 'character.dart' show EvolutionStage;

/// The 10 stats as children read them (hiragana / katakana, no kanji).
String statLabelV2(Stat s) => switch (s) {
  Stat.hp => 'たいりょく',
  Stat.sp => 'わざパワー',
  Stat.str => 'ちから',
  Stat.vit => 'タフさ',
  Stat.def => 'かたさ',
  Stat.intl => 'まほう',
  Stat.res => 'まもりのちから',
  Stat.dex => 'きようさ',
  Stat.agi => 'すばやさ',
  Stat.luk => 'うん',
};

/// Short word for an attribute: 「グー（かたい）」 (GAME_DESIGN_V2 §3.3).
String attrLabel(Attr a) => switch (a) {
  Attr.gu => 'グー',
  Attr.choki => 'チョキ',
  Attr.pa => 'パー',
  Attr.none => 'むぞくせい',
};

String attrHint(Attr a) => switch (a) {
  Attr.gu => 'かたい',
  Attr.choki => 'するどい',
  Attr.pa => 'ひろがる',
  Attr.none => '',
};

/// Kid names of the evolution ids of [kEvolutions].
String evolutionLabel(String id) => switch (id) {
  'kagayaki' => 'かがやき',
  'kirakira' => 'きらきら',
  'densetsu' => 'でんせつ',
  'niji' => 'にじ',
  'oukan' => 'おうかん',
  _ => 'しんか',
};

ElementType _elementOfAttr(Attr a) => switch (a) {
  Attr.gu => ElementType.fire,
  Attr.choki => ElementType.thunder,
  Attr.pa => ElementType.leaf,
  Attr.none => ElementType.rainbow,
};

/// Display helpers (cosmetic only; no hidden state).
extension CharacterV2Display on CharacterV2 {
  /// Colour family used for frames, auras and effects (the v1 colour
  /// element when known, else one picked from the attribute).
  ElementType get element => legacyElement ?? _elementOfAttr(attribute());

  /// Frame tier: かがやき from Lv10, でんせつ (gold) from Lv50 — the same
  /// for every character.
  EvolutionStage get stage => level >= 50
      ? EvolutionStage.densetsu
      : level >= 10
      ? EvolutionStage.kagayaki
      : EvolutionStage.normal;

  /// Moves usable now (2–4).
  List<Move> get unlockedMoves => allMoves().sublist(0, unlockedSlotCount());

  /// Slot 1 (the character's own attribute move).
  String get elementMoveName => _nameOf(allMoves()[0]);

  /// Slot 4 (ひっさつ, unlocked at Lv50).
  String get specialMoveName => _nameOf(allMoves()[3]);
}

String _nameOf(Move m) => m.name.isEmpty ? m.template : m.name;

/// Display name of a move.
String moveDisplayName(Move m) => _nameOf(m);

/// Single-player XP for [c] (GAME_DESIGN_V2 §4.2). Includes the hidden
/// catch-up factor of a late bloomer below Lv50 without telling anyone.
int singlePlayerXpFor(
  CharacterV2 c, {
  required bool win,
  required int stage,
  bool firstClear = false,
  bool adBoost = false,
  V3Spec s = const V3Spec(),
}) {
  final g = c.genome(s);
  return xpSinglePlayer(
    win: win,
    stage: stage,
    level: c.level,
    firstClear: firstClear,
    adBoost: adBoost,
    hiddenBloomer: g.isBloomer && !g.rebornAt(c.level),
  );
}

/// Name of the move a drawn effect belongs to (ぞくせいわざ = slot 1,
/// ひっさつ = slot 4).
String drawnMoveLabel(CharacterV2 c, DrawnMove m) => switch (m) {
  DrawnMove.element => c.elementMoveName,
  DrawnMove.special => c.specialMoveName,
};

/// A new character from a birth: the analyser's output, the trust verdict
/// of the v2 admission (internal), and the cloud's AI move proposals when
/// the parent allowed cloud features (re-validated here against the slot
/// budgets; missing / rejected slots use `generateOfflineMoves`).
CharacterV2 newCharacterV2({
  required String id,
  required String name,
  required String imagePath,
  required String imageHash,
  required Map<String, num> rawFeatures,
  required double energy,
  required double skill,
  required DateTime createdAt,
  DrawingSource source = DrawingSource.photo,
  String? verdict,
  List<Map<String, Object?>?>? cloudMoves,
  Map<String, Object?>? rig,
  String? subject,
  ElementType? legacyElement,
  bool Function(String)? ngCheck,
  V3Spec s = const V3Spec(),
}) {
  final c = CharacterV2.create(
    id: id,
    name: name,
    imagePath: imagePath,
    imageHash: imageHash,
    rawFeatures: rawFeatures,
    energy: energy,
    skill: skill,
    createdAt: createdAt,
    source: source,
    verdict: verdict,
    rig: rig,
    subject: subject,
    legacyElement: legacyElement,
  );
  if (cloudMoves == null || cloudMoves.every((m) => m == null)) return c;
  final g = c.genome(s);
  return c.withAiMoves(
    validateAiMoveSet(
      s,
      {'moves': cloudMoves},
      own: g.attr,
      moveFactorPct: g.moveFactorPct(1),
      ngCheck: ngCheck,
    ),
  );
}
