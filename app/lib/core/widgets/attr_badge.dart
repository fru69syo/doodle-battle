import 'package:flutter/material.dart';

import '../../domain/battle_v3/battle_v3.dart';
import '../../domain/character_v2_view.dart';

IconData attrIcon(Attr a) => switch (a) {
  Attr.gu => Icons.back_hand,
  Attr.choki => Icons.content_cut,
  Attr.pa => Icons.pan_tool,
  Attr.none => Icons.circle_outlined,
};

Color attrColor(Attr a) => switch (a) {
  Attr.gu => const Color(0xFFD7263D),
  Attr.choki => const Color(0xFF1E88E5),
  Attr.pa => const Color(0xFF2E9E44),
  Attr.none => const Color(0xFF7B3FE4),
};

/// グー / チョキ / パー pill (icon first: readable without reading).
class AttrBadge extends StatelessWidget {
  const AttrBadge(this.attr, {super.key, this.big = false});
  final Attr attr;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final hint = attrHint(attr);
    return Container(
      key: Key('attr-${attr.name}'),
      padding: EdgeInsets.symmetric(
        horizontal: big ? 14 : 10,
        vertical: big ? 6 : 3,
      ),
      decoration: BoxDecoration(
        color: attrColor(attr),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(attrIcon(attr), color: Colors.white, size: big ? 24 : 18),
          const SizedBox(width: 4),
          Text(
            hint.isEmpty ? attrLabel(attr) : '${attrLabel(attr)}（$hint）',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: big ? 18 : 14,
            ),
          ),
        ],
      ),
    );
  }
}
