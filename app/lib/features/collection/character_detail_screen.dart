import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/character_picture.dart';
import '../../core/widgets/attr_badge.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../core/widgets/stat_bars.dart';
import '../../data/app_state.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';
import '../drawing_loop/drawing_loop.dart';
import '../monetization/card_frames.dart';
import '../monetization/monetization_service.dart';
import '../video_export/video_export_entry.dart';
import 'xp_bar.dart';

/// CharacterV2 page: stats, level, XP, evolution, パワーのたね, AR, battle.
class CharacterDetailScreen extends ConsumerWidget {
  const CharacterDetailScreen({super.key, required this.characterId});
  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(characterByIdProvider(characterId));
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
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
            XpBar(character: c),
            const SizedBox(height: 12),
            StatBarsV2(stats: c.stats()),
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
    CharacterV2 c,
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
  final CharacterV2 c;

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
      AttrBadge(c.attribute(), big: true),
      Chip(
        key: const Key('detail-stage'),
        avatar: Icon(
          c.evolution == null ? Icons.child_care : Icons.auto_awesome,
          color: c.stage == EvolutionStage.densetsu
              ? AppColors.gold
              : AppColors.purple,
        ),
        label: Text(
          c.evolution == null ? 'ふつう' : evolutionLabel(c.evolution!),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );
}

class _Moves extends StatelessWidget {
  const _Moves({required this.c});
  final CharacterV2 c;

  @override
  Widget build(BuildContext context) {
    final moves = c.allMoves();
    final open = c.unlockedSlotCount();
    const unlockAt = [1, 1, 10, 50];
    return Column(
      children: [
        const Text(
          'わざ',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 4; i++)
              i < open
                  ? Chip(
                      key: Key('detail-move-$i'),
                      avatar: Icon(
                        attrIcon(moves[i].attr),
                        color: attrColor(moves[i].attr),
                      ),
                      label: Text(
                        moveDisplayName(moves[i]),
                        style: const TextStyle(fontSize: 16),
                      ),
                    )
                  : Chip(
                      key: Key('detail-move-$i'),
                      avatar: const Icon(Icons.lock, color: AppColors.disabled),
                      label: Text(
                        'Lv${unlockAt[i]}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
          ],
        ),
      ],
    );
  }
}

/// フレームパック: choose a card frame (only when the pack is owned; nothing
/// is advertised to the child otherwise).
class _FramePicker extends ConsumerWidget {
  const _FramePicker({required this.c});
  final CharacterV2 c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owned =
        ref
            .watch(settingsProvider)
            .value
            ?.ownedProducts
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
