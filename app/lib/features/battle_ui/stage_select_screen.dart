import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/element_badge.dart';
import '../../data/app_state.dart';
import '../../domain/battle/battle.dart';

String aiTierLabel(AiTier t) => switch (t) {
  AiTier.weak => 'よわい',
  AiTier.normal => 'ふつう',
  AiTier.strong => 'つよい',
};

/// CPU stages 1–30 from the battle spec's stage table (SPEC §4.3).
class StageSelectScreen extends ConsumerWidget {
  const StageSelectScreen({super.key, required this.characterId});
  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ref.watch(battleSpecProvider).value;
    final roster = ref.watch(cpuRosterProvider).value;
    final cleared = ref.watch(progressProvider).value?.clearedStage ?? 0;
    if (spec == null || roster == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('ステージを えらぼう')),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: spec.cpu.stages.length,
          itemBuilder: (context, i) {
            final stage = spec.cpu.stages[i];
            return _StageTile(
              stage: stage,
              cpu: roster[stage.cpuId],
              unlocked: stage.stage <= cleared + 1,
              cleared: stage.stage <= cleared,
              onTap: () =>
                  context.push(Routes.cpuBattle(characterId, stage.stage)),
            );
          },
        ),
      ),
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({
    required this.stage,
    required this.cpu,
    required this.unlocked,
    required this.cleared,
    required this.onTap,
  });

  final CpuStage stage;
  final CpuCharacter cpu;
  final bool unlocked;
  final bool cleared;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('stage-${stage.stage}'),
    color: unlocked ? Colors.white : const Color(0xFFEDEDED),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: unlocked ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: cleared ? AppColors.gold : AppColors.secondary,
              child: Text(
                '${stage.stage}',
                style: const TextStyle(
                  fontSize: 22,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              height: 64,
              child: unlocked
                  ? Image.asset(cpu.asset, fit: BoxFit.contain)
                  : const Icon(Icons.help, size: 48, color: AppColors.disabled),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unlocked ? cpu.name : '？？？',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'おすすめ Lv${stage.recommendedLevel}  ${aiTierLabel(stage.aiTier)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      if (unlocked) ElementBadge(cpu.element),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              cleared
                  ? Icons.emoji_events
                  : unlocked
                  ? Icons.play_circle
                  : Icons.lock,
              size: 36,
              color: cleared
                  ? AppColors.gold
                  : unlocked
                  ? AppColors.primary
                  : AppColors.disabled,
            ),
          ],
        ),
      ),
    ),
  );
}
