/// What a printed キャラカード shows (SPEC §11.2-4, docs/FAMILY.md). Pure
/// Dart so the PDF builder and its tests need no Flutter.
library;

import 'dart:typed_data';

import '../../domain/battle/battle.dart';
import '../../domain/character.dart';
import '../../domain/element_type.dart';
import '../../domain/stats.dart';

/// Stars per stat on a card (1–5).
const cardMaxStars = 5;

/// Card size in millimetres (trading-card size).
const cardWidthMm = 63.0;
const cardHeightMm = 88.0;

/// Cards on one A4 sheet (3 × 3).
const cardsPerSheet = 9;

/// Kid label of each stat (same words as the app).
String cardStatLabel(StatKind k) => switch (k) {
  StatKind.hp => 'たいりょく',
  StatKind.atk => 'こうげき',
  StatKind.def => 'ぼうぎょ',
  StatKind.spd => 'すばやさ',
};

/// Stars for each stat, **relative to the character's own best stat**: the
/// best stat always has [cardMaxStars] and the others are scaled to it
/// (rounded, at least 1). The stars show the character's shape (what it is
/// good at), never how strong or how "good" the drawing is, so no internal
/// number (stats, skill, energy) can be read back from a card.
Map<StatKind, int> cardStars(Stats s) {
  final values = {
    StatKind.hp: s.hp,
    StatKind.atk: s.atk,
    StatKind.def: s.def,
    StatKind.spd: s.spd,
  };
  final best = values.values.fold<int>(1, (a, b) => b > a ? b : a);
  return {
    for (final e in values.entries)
      e.key: ((e.value * cardMaxStars + best ~/ 2) ~/ best).clamp(
        1,
        cardMaxStars,
      ),
  };
}

/// Optional decorative background (the フレームパック frame when owned).
enum CardBackground { plain, hoshi, hana, niji }

/// Everything drawn on one card.
class CardContent {
  const CardContent({
    required this.name,
    required this.level,
    required this.element,
    required this.stage,
    required this.stars,
    required this.moves,
    required this.date,
    required this.image,
    this.background = CardBackground.plain,
  });

  final String name;
  final int level;
  final ElementType element;
  final EvolutionStage stage;
  final Map<StatKind, int> stars;

  /// たいあたり, ぞくせいわざ, まもる, ひっさつ names.
  final List<String> moves;

  /// うまれた ひ (when the drawing became a character).
  final DateTime date;

  /// Cut-out PNG of the original drawing (null: element icon instead).
  final Uint8List? image;
  final CardBackground background;
}

/// Builds a card for [c]. [moveLabel] gives a move's display name (the app
/// passes `characterMoveLabel`).
CardContent cardContentFor(
  BattleSpec spec,
  Character c, {
  required Uint8List? image,
  required String Function(Character c, BattleAction a) moveLabel,
  CardBackground background = CardBackground.plain,
}) => CardContent(
  name: c.name,
  level: c.level,
  element: c.element,
  stage: stageAtLevel(spec, c.level),
  stars: cardStars(currentStats(spec, c)),
  moves: [
    for (final a in const [
      BattleAction.tackle,
      BattleAction.element,
      BattleAction.guard,
      BattleAction.special,
    ])
      moveLabel(c, a),
  ],
  date: c.createdAt.toLocal(),
  image: image,
  background: background,
);

String cardStageLabel(EvolutionStage s) => switch (s) {
  EvolutionStage.normal => '',
  EvolutionStage.kagayaki => 'かがやき',
  EvolutionStage.densetsu => 'でんせつ',
};

/// 「2026.10.1」
String cardDateLabel(DateTime d) => '${d.year}.${d.month}.${d.day}';
