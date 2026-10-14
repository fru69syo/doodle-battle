import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../../domain/element_type.dart';

/// Visual effects shown around a character in AR, derived from its
/// evolution stage (SPEC §6: "進化の段階に応じたエフェクト（オーラ・きらきら）").
///
/// - [EvolutionStage.normal]   (Lv1–9):  none
/// - [EvolutionStage.kagayaki] (Lv10–49): aura
/// - [EvolutionStage.densetsu] (Lv50+):   aura + sparkles
class ArEffects {
  const ArEffects({
    this.aura = false,
    this.sparkles = false,
    this.auraColor = const ArColor(0xFF, 0xD5, 0x4F),
    this.rainbowAura = false,
  });

  factory ArEffects.forCharacter(CharacterV2 character) =>
      ArEffects.forStage(character.stage, character.element);

  factory ArEffects.forStage(EvolutionStage stage, ElementType element) {
    final aura = stage != EvolutionStage.normal;
    return ArEffects(
      aura: aura,
      sparkles: stage == EvolutionStage.densetsu,
      auraColor: elementAuraColor(element),
      rainbowAura: element == ElementType.rainbow,
    );
  }

  static const none = ArEffects();

  final bool aura;
  final bool sparkles;

  /// Base aura colour (ignored when [rainbowAura] is set).
  final ArColor auraColor;

  /// Rainbow element: aura hue cycles bottom-to-top.
  final bool rainbowAura;

  @override
  bool operator ==(Object other) =>
      other is ArEffects &&
      other.aura == aura &&
      other.sparkles == sparkles &&
      other.auraColor == auraColor &&
      other.rainbowAura == rainbowAura;

  @override
  int get hashCode => Object.hash(aura, sparkles, auraColor, rainbowAura);
}

/// Minimal colour value that is usable from pure Dart (isolates, tests)
/// without depending on `dart:ui`.
class ArColor {
  const ArColor(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  int get argb => 0xFF000000 | (r << 16) | (g << 8) | b;

  @override
  bool operator ==(Object other) =>
      other is ArColor && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);
}

/// Aura colour per element.
ArColor elementAuraColor(ElementType element) => switch (element) {
  ElementType.fire => const ArColor(0xFF, 0x70, 0x3A),
  ElementType.water => const ArColor(0x3F, 0xA9, 0xFF),
  ElementType.leaf => const ArColor(0x5C, 0xDB, 0x5C),
  ElementType.thunder => const ArColor(0xFF, 0xD8, 0x1F),
  ElementType.shadow => const ArColor(0xA2, 0x6B, 0xFF),
  ElementType.rainbow => const ArColor(0xFF, 0x8A, 0xD8),
};
