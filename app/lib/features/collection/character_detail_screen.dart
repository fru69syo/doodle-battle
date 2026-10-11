import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/character_picture.dart';
import '../../core/widgets/element_badge.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../core/widgets/stat_bars.dart';
import '../../data/app_state.dart';
import '../../domain/battle/battle.dart';
import '../../domain/character.dart';
import '../../domain/stats.dart';
import '../battle_ui/move_labels.dart';
import '../drawing_loop/drawing_loop.dart';
import '../monetization/card_frames.dart';
import '../monetization/monetization_service.dart';
import '../video_export/video_export_entry.dart';
import 'xp_bar.dart';

/// Character page: stats, level, XP, evolution, パワーのたね, AR, battle.
class CharacterDetailScreen extends ConsumerWidget {
  const CharacterDetailScreen({super.key, required this.characterId});
  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(characterByIdProvider(characterId));
    final spec = ref.watch(battleSpecProvider).value;
    if (c == null || spec == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final seeds = seedsAvailable(spec, c);
    final justBorn = ref.watch(justBornCharacterProvider) == c.id;
    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: CharacterPicture(character: c, size: 220)),
            if (justBorn) ...[
              // Right after naming: invite to make the video, just below the
              // picture (never over the drawing).
              const SizedBox(height: 12),
              Center(
                child: VideoExportButton(characterId: c.id, prominent: true),
              ),
            ],
            const SizedBox(height: 12),
            _Header(c: c),
            const SizedBox(height: 8),
            XpBar(spec: spec, character: c),
            const SizedBox(height: 12),
            if (seeds > 0) _SeedHeader(seeds: seeds),
            StatBars(
              stats: currentStats(spec, c),
              hpMultiplier: spec.hpMultiplier,
              trailing: seeds > 0 ? (k) => _SeedButton(c: c, stat: k) : null,
            ),
            const SizedBox(height: 12),
            _Moves(c: c),
            _FramePicker(c: c),
            const SizedBox(height: 16),
            DrawingLoopSection(character: c),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('detail-battle'),
              icon: const Icon(Icons.sports_martial_arts),
              label: const Text('バトルする'),
              onPressed: () => context.push(Routes.stages(c.id)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('detail-joints'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A00),
              ),
              icon: const Icon(Icons.accessibility_new),
              label: const Text('うごく ところを なおす'),
              onPressed: () => context.push(Routes.characterJoints(c.id)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('detail-ar'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              icon: const Icon(Icons.view_in_ar),
              label: const Text('AR で みる'),
              onPressed: () => context.push(Routes.characterAr(c.id)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('detail-card'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
              icon: const Icon(Icons.style),
              label: const Text('カードに する'),
              onPressed: () => context.push(Routes.cardPrint([c.id])),
            ),
            const SizedBox(height: 12),
            VideoExportButton(characterId: c.id),
            const SizedBox(height: 24),
            TextButton.icon(
              key: const Key('detail-release'),
              icon: const Icon(Icons.waving_hand),
              label: const Text('おわかれ する'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () => _release(context, ref, c),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _release(
    BuildContext context,
    WidgetRef ref,
    Character c,
  ) async {
    final ok = await askKid(
      context,
      '${c.name} と ほんとうに おわかれ する？\nもう もどって こないよ',
      yesLabel: 'おわかれ する',
      noLabel: 'やっぱり やめる',
      icon: Icons.waving_hand,
    );
    if (!ok || !context.mounted) return;
    await ref.read(charactersProvider.notifier).delete(c.id);
    if (context.mounted) context.pop();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.c});
  final Character c;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      Text(
        'Lv${c.level}',
        key: const Key('detail-level'),
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
      ),
      ElementBadge(c.element, big: true),
      Chip(
        key: const Key('detail-stage'),
        avatar: Icon(
          c.stage == EvolutionStage.normal
              ? Icons.child_care
              : Icons.auto_awesome,
          color: c.stage == EvolutionStage.densetsu
              ? AppColors.gold
              : AppColors.purple,
        ),
        label: Text(
          stageLabel(c.stage),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _SeedHeader extends StatelessWidget {
  const _SeedHeader({required this.seeds});
  final int seeds;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFE8F8E0),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.spa, color: AppColors.success, size: 36),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'パワーのたねが $seeds こ あるよ！ ＋を おして つよく しよう',
              key: const Key('detail-seeds'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SeedButton extends ConsumerWidget {
  const _SeedButton({required this.c, required this.stat});
  final Character c;
  final StatKind stat;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    key: Key('seed-${stat.name}'),
    tooltip: '${statLabel(stat)} を つよく する',
    icon: const Icon(Icons.add_circle, color: AppColors.success),
    onPressed: () async {
      final spec = await ref.read(battleSpecProvider.future);
      final current = ref.read(characterByIdProvider(c.id)) ?? c;
      if (seedsAvailable(spec, current) <= 0) return;
      await ref
          .read(charactersProvider.notifier)
          .save(allocateSeed(spec, current, stat));
    },
  );
}

class _Moves extends StatelessWidget {
  const _Moves({required this.c});
  final Character c;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text(
        'わざ',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in [
            BattleAction.tackle,
            BattleAction.element,
            BattleAction.guard,
            BattleAction.special,
          ])
            Chip(
              label: Text(
                characterMoveLabel(c, a),
                style: const TextStyle(fontSize: 16),
              ),
            ),
        ],
      ),
    ],
  );
}

/// フレームパック: choose a card frame (only when the pack is owned; nothing
/// is advertised to the child otherwise).
class _FramePicker extends ConsumerWidget {
  const _FramePicker({required this.c});
  final Character c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned =
        ref
            .watch(settingsProvider)
            .value
            ?.entitlements
            .contains(Product.framePack.id) ??
        false;
    if (!owned) return const SizedBox.shrink();
    Future<void> pick(String? id) => ref
        .read(charactersProvider.notifier)
        .save(c.copyWith(cardFrame: () => id));
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        key: const Key('frame-picker'),
        children: [
          const Text(
            'カードの わく',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const Key('frame-none'),
                label: const Text('なし', style: TextStyle(fontSize: 18)),
                selected: CardFrame.byId(c.cardFrame) == null,
                onSelected: (_) => pick(null),
              ),
              for (final f in CardFrame.values)
                ChoiceChip(
                  key: Key('frame-${f.id}'),
                  label: Text(f.label, style: const TextStyle(fontSize: 18)),
                  selected: c.cardFrame == f.id,
                  onSelected: (_) => pick(f.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
