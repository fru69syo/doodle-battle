import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/battle_v3/battle_v3.dart';
import '../../domain/character_v2.dart';

/// 「つぎの レベルまで」 bar.
class XpBar extends StatelessWidget {
  const XpBar({super.key, required this.character, this.spec = const V3Spec()});

  final CharacterV2 character;
  final V3Spec spec;

  @override
  Widget build(BuildContext context) {
    final maxed = character.level >= spec.maxLevel;
    final need = xpToNext(spec, character.level);
    final fraction = maxed ? 1.0 : character.xp / need;
    return Column(
      children: [
        Text(
          maxed ? 'さいこう レベル！' : 'つぎの レベルまで あと ${need - character.xp}',
          key: const Key('xp-text'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: fraction.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 800),
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 16,
              color: AppColors.secondary,
              backgroundColor: const Color(0xFFE6E0D4),
            ),
          ),
        ),
      ],
    );
  }
}
