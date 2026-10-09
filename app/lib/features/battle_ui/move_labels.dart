import '../../domain/battle/battle.dart';
import '../../domain/character.dart';
import '../../domain/element_type.dart';

/// Default ぞくせいわざ name when the cloud judge did not name it.
String defaultElementMoveName(ElementType e) => switch (e) {
  ElementType.fire => 'めらめらパンチ',
  ElementType.water => 'ざぶーんアタック',
  ElementType.leaf => 'はっぱシュート',
  ElementType.thunder => 'びりびりキック',
  ElementType.shadow => 'もやもやタッチ',
  ElementType.rainbow => 'にじいろビーム',
};

const defaultSpecialMoveName = 'ひっさつわざ';

/// Label of [action] for a fighter (uses the character's own move names).
String moveLabel(
  BattleAction action, {
  required ElementType element,
  String? elementMoveName,
  String? specialMoveName,
}) => switch (action) {
  BattleAction.tackle => 'たいあたり',
  BattleAction.element => elementMoveName ?? defaultElementMoveName(element),
  BattleAction.guard => 'まもる',
  BattleAction.special => specialMoveName ?? defaultSpecialMoveName,
  BattleAction.timeout => 'たいあたり',
};

String characterMoveLabel(Character c, BattleAction a) => moveLabel(
  a,
  element: c.element,
  elementMoveName: c.elementMoveName,
  specialMoveName: c.specialMoveName,
);
