import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/app_state.dart';
import '../../data/game_progress.dart';
import '../../domain/battle_v3/battle_v3.dart';
import '../battle_stage/stage_theme.dart';

/// Stars of world [w] (1..10): collected / possible.
(int, int) worldStars(GameProgress p, int w) {
  var got = 0;
  for (var n = (w - 1) * 10 + 1; n <= w * 10; n++) {
    got += p.starsOf(n);
  }
  return (got, 30);
}

/// A world is open once the boss of the previous one is beaten.
bool worldOpen(GameProgress p, int w) => p.clearedStage >= (w - 1) * 10;

/// Stage [n] is open once the previous stage was won.
bool stageOpen(GameProgress p, int n) => n <= p.clearedStage + 1;

/// 「どこで たたかう？」: the 10 worlds (no story), with stars collected.
class WorldSelectScreen extends ConsumerWidget {
  const WorldSelectScreen({super.key, required this.characterId});
  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider).value;
    if (p == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('どこで たたかう？')),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: kWorldNames.length,
          itemBuilder: (context, i) {
            final w = i + 1;
            final open = worldOpen(p, w);
            final (got, all) = worldStars(p, w);
            final theme = StageTheme.forWorld(w);
            return Card(
              key: Key('world-$w'),
              clipBehavior: Clip.antiAlias,
              color: open ? theme.skyBottom : const Color(0xFFDDDDDD),
              child: InkWell(
                onTap: open
                    ? () => context.push(Routes.world(characterId, w))
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        open ? _worldIcon(w) : Icons.lock,
                        size: 48,
                        color: open ? AppColors.ink : AppColors.disabled,
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          open ? kWorldNames[i] : '？？？',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (open)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star, color: AppColors.gold),
                            Text(
                              '$got / $all',
                              key: Key('world-stars-$w'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static IconData _worldIcon(int w) => switch (w) {
    1 => Icons.grass,
    2 => Icons.forest,
    3 => Icons.waves,
    4 => Icons.terrain,
    5 => Icons.ac_unit,
    6 => Icons.location_city,
    7 => Icons.wb_sunny,
    8 => Icons.castle,
    9 => Icons.cloud,
    _ => Icons.menu_book,
  };
}

/// The 10 stages of world [world]: number, CPU picture, stars; the 10th is
/// the boss.
class StageSelectScreen extends ConsumerWidget {
  const StageSelectScreen({
    super.key,
    required this.characterId,
    required this.world,
  });
  final String characterId;
  final int world;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(progressProvider).value;
    final roster = ref.watch(cpuRosterV2Provider).value;
    if (p == null || roster == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final w = world.clamp(1, 10);
    return Scaffold(
      appBar: AppBar(title: Text(kWorldNames[w - 1])),
      body: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.9,
          ),
          itemCount: 10,
          itemBuilder: (context, i) {
            final st = stageAt((w - 1) * 10 + i + 1);
            final open = stageOpen(p, st.stage);
            final stars = p.starsOf(st.stage);
            final cpu = roster.byId[st.cpuId];
            return Card(
              key: Key('stage-${st.stage}'),
              color: st.boss
                  ? const Color(0xFFFFE9A8)
                  : (open ? Colors.white : const Color(0xFFEDEDED)),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: open
                    ? () =>
                          context.push(Routes.cpuBattle(characterId, st.stage))
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: stars > 0
                                ? AppColors.gold
                                : AppColors.secondary,
                            child: Text(
                              '${st.position}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (st.boss)
                            const Icon(
                              Icons.workspace_premium,
                              color: AppColors.danger,
                              size: 30,
                            ),
                        ],
                      ),
                      Expanded(
                        child: open && cpu != null
                            ? Image.asset(cpu.asset, fit: BoxFit.contain)
                            : const Icon(
                                Icons.lock,
                                size: 40,
                                color: AppColors.disabled,
                              ),
                      ),
                      Row(
                        key: Key('stage-stars-${st.stage}'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var k = 0; k < 3; k++)
                            Icon(
                              k < stars ? Icons.star : Icons.star_border,
                              color: k < stars
                                  ? AppColors.gold
                                  : AppColors.disabled,
                              size: 26,
                            ),
                        ],
                      ),
                      Text(
                        'Lv${st.recommendedLevel}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
