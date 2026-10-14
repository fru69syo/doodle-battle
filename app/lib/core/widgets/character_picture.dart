import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_state.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../../features/drawing_loop/display_image.dart';
import '../../features/monetization/card_frames.dart';
import '../../features/monetization/monetization_service.dart';
import '../theme/app_colors.dart';

/// Picture of a character with its evolution frame: かがやき = coloured aura,
/// でんせつ = gold frame (SPEC §4.2), plus the chosen フレームパック frame.
class CharacterPicture extends ConsumerWidget {
  const CharacterPicture({
    super.key,
    required this.character,
    this.size = 160,
    this.bytes,
  });

  final CharacterV2 character;
  final double size;

  /// Explicit image bytes (e.g. online opponent); otherwise bundled asset
  /// for CPU characters or the stored cut-out.
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget image;
    if (bytes != null) {
      image = Image.memory(bytes!, fit: BoxFit.contain, gaplessPlayback: true);
    } else if (character.imagePath.startsWith('assets/')) {
      image = Image.asset(character.imagePath, fit: BoxFit.contain);
    } else {
      // Base drawing + drawn parts (docs/LOOP.md); the plain cut-out while
      // the composite loads.
      final data =
          ref
              .watch(characterDisplayImageProvider(displayKeyOf(character)))
              .value ??
          ref.watch(characterImageProvider(character.id)).value;
      image = data == null
          ? const Icon(Icons.brush, size: 64, color: AppColors.disabled)
          : Image.memory(data, fit: BoxFit.contain, gaplessPlayback: true);
    }
    // フレームパック: only while the pack is owned (a refund removes it).
    final frame = CardFrame.byId(character.cardFrame);
    final owned = ref
        .watch(ownedProductsProvider)
        .contains(Product.framePack.id);
    if (frame != null && owned) {
      return CardFrameBorder(
        frame: frame,
        size: size,
        child: EvolutionFrame(
          stage: character.stage,
          color: AppColors.element(character.element),
          size: CardFrameBorder.innerSizeOf(size),
          child: image,
        ),
      );
    }
    return EvolutionFrame(
      stage: character.stage,
      color: AppColors.element(character.element),
      size: size,
      child: image,
    );
  }
}

class EvolutionFrame extends StatelessWidget {
  const EvolutionFrame({
    super.key,
    required this.stage,
    required this.color,
    required this.size,
    required this.child,
  });

  final EvolutionStage stage;
  final Color color;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final decoration = switch (stage) {
      EvolutionStage.normal => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 3),
      ),
      EvolutionStage.kagayaki => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 4),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.7),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      EvolutionStage.densetsu => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold, width: 8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.7),
            blurRadius: 28,
            spreadRadius: 6,
          ),
        ],
      ),
    };
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: decoration,
      child: child,
    );
  }
}

String stageLabel(EvolutionStage s) => switch (s) {
  EvolutionStage.normal => 'ふつう',
  EvolutionStage.kagayaki => 'かがやき',
  EvolutionStage.densetsu => 'でんせつ',
};
