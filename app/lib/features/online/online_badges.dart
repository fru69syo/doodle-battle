import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Rank badges of rated play (docs/REALTIME_PROTOCOL.md §4). The rating
/// number itself is never shown or sent; the badge never goes down.
const kBadgeIds = [
  'egg',
  'chick',
  'rabbit',
  'fox',
  'bear',
  'lion',
  'dragon',
  'legend',
];

String badgeLabel(String id) => switch (id) {
  'egg' => 'たまご',
  'chick' => 'ひよこ',
  'rabbit' => 'うさぎ',
  'fox' => 'きつね',
  'bear' => 'くま',
  'lion' => 'ライオン',
  'dragon' => 'ドラゴン',
  'legend' => 'でんせつ',
  _ => 'たまご',
};

IconData badgeIcon(String id) => switch (id) {
  'egg' => Icons.egg,
  'chick' => Icons.flutter_dash,
  'rabbit' => Icons.cruelty_free,
  'fox' => Icons.pets,
  'bear' => Icons.forest,
  'lion' => Icons.local_fire_department,
  'dragon' => Icons.whatshot,
  'legend' => Icons.workspace_premium,
  _ => Icons.egg,
};

/// Index of [id] in [kBadgeIds] (unknown → 0).
int badgeRank(String? id) {
  final i = kBadgeIds.indexOf(id ?? 'egg');
  return i < 0 ? 0 : i;
}

/// The badge as a round icon with its name.
class BadgeChip extends StatelessWidget {
  const BadgeChip({super.key, required this.badge, this.big = false});
  final String badge;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final rank = badgeRank(badge);
    final color = Color.lerp(
      AppColors.secondary,
      AppColors.gold,
      rank / (kBadgeIds.length - 1),
    )!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: big ? 18 : 12,
        vertical: big ? 10 : 6,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon(badge), color: Colors.white, size: big ? 36 : 24),
          const SizedBox(width: 6),
          Text(
            badgeLabel(badge),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: big ? 24 : 16,
            ),
          ),
        ],
      ),
    );
  }
}
