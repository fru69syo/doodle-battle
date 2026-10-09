import 'package:flutter/material.dart';

import '../../domain/element_type.dart';
import '../theme/app_colors.dart';

IconData elementIcon(ElementType e) => switch (e) {
  ElementType.fire => Icons.local_fire_department,
  ElementType.water => Icons.water_drop,
  ElementType.leaf => Icons.eco,
  ElementType.thunder => Icons.bolt,
  ElementType.shadow => Icons.nightlight_round,
  ElementType.rainbow => Icons.auto_awesome,
};

/// Coloured pill with the element's hiragana label.
class ElementBadge extends StatelessWidget {
  const ElementBadge(this.element, {super.key, this.big = false});
  final ElementType element;
  final bool big;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: big ? 16 : 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.element(element),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(elementIcon(element), color: Colors.white, size: big ? 26 : 18),
        const SizedBox(width: 4),
        Text(
          element.label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: big ? 22 : 16,
          ),
        ),
      ],
    ),
  );
}

/// 「げいじゅつか」 title of しょぼキャラ (SPEC §1).
class ShoboBadge extends StatelessWidget {
  const ShoboBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.purple,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.palette, color: Colors.white, size: 18),
        SizedBox(width: 4),
        Text(
          'げいじゅつか',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
