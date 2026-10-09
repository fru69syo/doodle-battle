import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/character_picture.dart';
import '../../data/app_state.dart';
import '../../domain/character.dart';
import '../collection/xp_bar.dart';
import '../monetization/rewarded_ad_button.dart';
import 'battle_outcome.dart';

/// After a battle: win/lose, XP, level-up, evolution, seeds (SPEC §4.2).
class BattleResultScreen extends ConsumerStatefulWidget {
  const BattleResultScreen({super.key, required this.outcome});
  final BattleOutcome outcome;

  @override
  ConsumerState<BattleResultScreen> createState() => _BattleResultScreenState();
}

class _BattleResultScreenState extends ConsumerState<BattleResultScreen> {
  late BattleOutcome _o = widget.outcome;

  Future<void> _onAdReward() async {
    final spec = await ref.read(battleSpecProvider.future);
    final o = await ref
        .read(battleRewardsProvider)
        .applyAdBonus(spec: spec, outcome: _o);
    if (mounted) setState(() => _o = o);
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(characterByIdProvider(_o.characterId));
    final spec = ref.watch(battleSpecProvider).value;
    final title = _o.draw
        ? 'ひきわけ！'
        : _o.won
        ? 'かった！'
        : 'まけちゃった…';
    return Scaffold(
      appBar: AppBar(
        title: const Text('けっか'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              title,
              key: const Key('result-title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: _o.won ? AppColors.primary : AppColors.secondary,
              ),
            ),
            if (c != null)
              Center(child: CharacterPicture(character: c, size: 180)),
            const SizedBox(height: 12),
            Text(
              'けいけんち +${_o.xpGained}',
              key: const Key('result-xp'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            if (c != null && spec != null) XpBar(spec: spec, character: c),
            if (_o.leveledUp)
              _Celebrate(
                key: const Key('result-levelup'),
                icon: Icons.arrow_upward,
                text: 'レベルアップ！ Lv${_o.levelAfter} に なった！',
              ),
            if (_o.seedsGained > 0)
              _Celebrate(
                key: const Key('result-seeds'),
                icon: Icons.spa,
                text: 'パワーのたねを ${_o.seedsGained}こ もらった！',
              ),
            for (final e in _o.evolutions)
              _Celebrate(
                key: Key('result-evo-${e.name}'),
                icon: Icons.auto_awesome,
                text: e == EvolutionStage.densetsu
                    ? 'でんせつ に しんか した！ きんの フレーム！'
                    : 'かがやき に しんか した！ オーラが でてきた！',
              ),
            const SizedBox(height: 16),
            RewardedAdButton(onRewarded: _onAdReward),
            const SizedBox(height: 16),
            ..._buttons(context, c),
          ],
        ),
      ),
    );
  }

  List<Widget> _buttons(BuildContext context, Character? c) {
    final stage = _o.stage;
    final lastStage = ref.read(battleSpecProvider).value?.cpu.stages.length ?? 30;
    return [
      if (stage != null && _o.won && stage < lastStage && c != null)
        FilledButton(
          key: const Key('result-next'),
          onPressed: () =>
              context.pushReplacement(Routes.cpuBattle(c.id, stage + 1)),
          child: const Text('つぎの ステージへ'),
        ),
      if (stage != null && c != null) ...[
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('result-retry'),
          onPressed: () =>
              context.pushReplacement(Routes.cpuBattle(c.id, stage)),
          child: const Text('もういちど'),
        ),
      ],
      const SizedBox(height: 12),
      OutlinedButton(
        key: const Key('result-home'),
        onPressed: () => context.go(Routes.home),
        child: const Text('ホームに もどる'),
      ),
    ];
  }
}

class _Celebrate extends StatelessWidget {
  const _Celebrate({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF0C2),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, size: 36, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}
