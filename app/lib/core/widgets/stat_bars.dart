import 'package:flutter/material.dart';

import '../../domain/battle_v3/battle_v3.dart';
import '../../domain/character_v2_view.dart';
import '../../domain/stats.dart';
import '../theme/app_colors.dart';

String statLabel(StatKind k) => switch (k) {
  StatKind.hp => 'たいりょく',
  StatKind.atk => 'こうげき',
  StatKind.def => 'ぼうぎょ',
  StatKind.spd => 'すばやさ',
};

Color statColor(StatKind k) => switch (k) {
  StatKind.hp => AppColors.hpHigh,
  StatKind.atk => AppColors.danger,
  StatKind.def => AppColors.secondary,
  StatKind.spd => AppColors.gold,
};

int statValue(Stats s, StatKind k) => switch (k) {
  StatKind.hp => s.hp,
  StatKind.atk => s.atk,
  StatKind.def => s.def,
  StatKind.spd => s.spd,
};

/// Four horizontal bars. HP is displayed multiplied by [hpMultiplier]
/// (battle HP, SPEC §3.2). [visible] counts how many bars are revealed (for
/// the birth animation).
class StatBars extends StatelessWidget {
  const StatBars({
    super.key,
    required this.stats,
    required this.hpMultiplier,
    this.visible = 4,
    this.trailing,
  });

  final Stats stats;
  final int hpMultiplier;
  final int visible;

  /// Optional widget per stat (e.g. パワーのたね + button).
  final Widget Function(StatKind kind)? trailing;

  @override
  Widget build(BuildContext context) {
    final scale = [
      160,
      stats.hp,
      stats.atk,
      stats.def,
      stats.spd,
    ].reduce((a, b) => a > b ? a : b).toDouble();
    return Column(
      children: [
        for (final (i, k) in StatKind.values.indexed)
          AnimatedOpacity(
            opacity: i < visible ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: _StatRow(
              kind: k,
              value: statValue(stats, k),
              shown: k == StatKind.hp
                  ? stats.hp * hpMultiplier
                  : statValue(stats, k),
              fraction: i < visible ? statValue(stats, k) / scale : 0,
              trailing: trailing?.call(k),
            ),
          ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.kind,
    required this.value,
    required this.shown,
    required this.fraction,
    this.trailing,
  });

  final StatKind kind;
  final int value;
  final int shown;
  final double fraction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            statLabel(kind),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction.clamp(0, 1)),
              duration: const Duration(milliseconds: 600),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 18,
                color: statColor(kind),
                backgroundColor: const Color(0xFFE6E0D4),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '$shown',
            key: Key('stat-${kind.name}'),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// The ten v2 stats as bars (relative to the character's best stat, with
/// the number). [visible] reveals them one by one (birth animation).
class StatBarsV2 extends StatelessWidget {
  const StatBarsV2({super.key, required this.stats, this.visible = 10});

  /// Ten values in [Stat] order.
  final List<int> stats;
  final int visible;

  static Color colorOf(Stat s) => switch (s) {
    Stat.hp || Stat.vit => AppColors.hpHigh,
    Stat.sp || Stat.intl => AppColors.purple,
    Stat.str => AppColors.danger,
    Stat.def || Stat.res => AppColors.secondary,
    Stat.dex || Stat.agi => AppColors.gold,
    Stat.luk => AppColors.pink,
  };

  @override
  Widget build(BuildContext context) {
    final best = stats.fold<int>(1, (a, b) => b > a ? b : a).toDouble();
    return Column(
      children: [
        for (final s in Stat.values)
          AnimatedOpacity(
            opacity: s.index < visible ? 1 : 0,
            duration: const Duration(milliseconds: 300),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: Text(
                      statLabelV2(s),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          end: s.index < visible
                              ? (stats[s.index] / best).clamp(0.0, 1.0)
                              : 0,
                        ),
                        duration: const Duration(milliseconds: 600),
                        builder: (context, v, _) => LinearProgressIndicator(
                          value: v,
                          minHeight: 16,
                          color: colorOf(s),
                          backgroundColor: const Color(0xFFE6E0D4),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${stats[s.index]}',
                      key: Key('stat-${s.name}'),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
