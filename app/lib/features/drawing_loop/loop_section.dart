import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../data/app_state.dart';
import '../../data/drawing_loop_storage.dart';
import '../../domain/character.dart';
import '../../domain/cosmetics.dart';
import '../battle_ui/move_labels.dart';
import 'display_image.dart';
import 'effects/move_effect_layer.dart';
import 'loop_labels.dart';

/// 「かきたして あそぼう」 on the character page: the おだい badge, the three
/// part slots (Lv5 / 10 / 20) and the two drawable move effects.
class DrawingLoopSection extends ConsumerWidget {
  const DrawingLoopSection({super.key, required this.character});
  final Character character;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = character;
    final parts = c.cosmetics.parts;
    final slots = partSlotsFor(c.level);
    final odai = c.cosmetics.odai;
    return Card(
      key: const Key('loop-section'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.brush, color: AppColors.primary),
                SizedBox(width: 6),
                Text(
                  'かきたして あそぼう',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (odai != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  key: const Key('loop-odai-badge'),
                  avatar: const Icon(Icons.lightbulb, color: AppColors.gold),
                  label: Text('おだい「${odai.text}」'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'パーツ',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var slot = 1; slot <= CharacterCosmetics.maxParts; slot++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: slot <= parts.length
                          ? _PartSlot(c: c, part: parts[slot - 1])
                          : slot <= slots
                          ? _AddSlot(c: c, slot: slot)
                          : _LockedSlot(slot: slot),
                    ),
                  ),
              ],
            ),
            if (slots == 0)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Lv5に なると、かみに かいた パーツを くっつけられるよ',
                  style: TextStyle(fontSize: 15),
                ),
              ),
            if (parts.isNotEmpty)
              Align(
                child: TextButton.icon(
                  key: const Key('loop-edit-parts'),
                  icon: const Icon(Icons.open_with),
                  label: const Text('パーツを うごかす'),
                  onPressed: () => context.push(Routes.characterParts(c.id)),
                ),
              ),
            const SizedBox(height: 10),
            const Text(
              'わざの え',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final m in DrawnMove.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _EffectTile(c: c, move: m),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotBox extends StatelessWidget {
  const _SlotBox({
    required this.child,
    this.onTap,
    this.color = Colors.white,
    this.tileKey,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Key? tileKey;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: tileKey,
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6E0D4), width: 2),
          ),
          padding: const EdgeInsets.all(6),
          child: child,
        ),
      ),
    ),
  );
}

class _PartSlot extends ConsumerWidget {
  const _PartSlot({required this.c, required this.part});
  final Character c;
  final CharacterPart part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final png = ref.watch(loopAssetProvider((c.id, part.assetName))).value;
    return _SlotBox(
      tileKey: Key('loop-part-${part.id}'),
      onTap: () => context.push(Routes.characterParts(c.id)),
      child: Column(
        children: [
          Expanded(
            child: png == null
                ? Icon(partIcon(part.type), size: 40)
                : Image.memory(png, fit: BoxFit.contain),
          ),
          Text(partLabel(part.type), style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _AddSlot extends StatelessWidget {
  const _AddSlot({required this.c, required this.slot});
  final Character c;
  final int slot;

  @override
  Widget build(BuildContext context) => _SlotBox(
    tileKey: Key('loop-add-part-$slot'),
    color: const Color(0xFFFFF1C9),
    onTap: () => context.push(Routes.characterNewPart(c.id)),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_circle, size: 40, color: AppColors.primary),
        Text('かきたす', style: TextStyle(fontSize: 13)),
      ],
    ),
  );
}

class _LockedSlot extends StatelessWidget {
  const _LockedSlot({required this.slot});
  final int slot;

  @override
  Widget build(BuildContext context) => _SlotBox(
    tileKey: Key('loop-slot-locked-$slot'),
    color: const Color(0xFFF2F0EA),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock, size: 32, color: AppColors.disabled),
        Text(
          'Lv${partSlotUnlockLevel(slot)}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _EffectTile extends ConsumerWidget {
  const _EffectTile({required this.c, required this.move});
  final Character c;
  final DrawnMove move;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = c.cosmetics.effects[move];
    final png = asset == null
        ? null
        : ref.watch(loopAssetProvider((c.id, asset))).value;
    final action = battleActionOf(move);
    return Column(
      children: [
        _SlotBox(
          tileKey: Key('loop-effect-${move.name}'),
          onTap: () => context.push(Routes.characterEffect(c.id, move.name)),
          child: Column(
            children: [
              Expanded(
                child: png != null
                    ? Image.memory(png, fit: BoxFit.contain)
                    : Icon(
                        defaultEffectIcon(c.element, action),
                        size: 44,
                        color: move == DrawnMove.special
                            ? AppColors.gold
                            : AppColors.element(c.element),
                      ),
              ),
              Text(
                characterMoveLabel(c, action),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                asset == null ? 'えを かく' : 'かきなおす',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
        if (asset != null)
          TextButton(
            key: Key('loop-effect-reset-${move.name}'),
            onPressed: () => _reset(context, ref, asset),
            child: const Text('もとに もどす'),
          ),
      ],
    );
  }

  Future<void> _reset(BuildContext context, WidgetRef ref, String asset) async {
    final ok = await askKid(
      context,
      'さいしょの エフェクトに もどす？',
      yesLabel: 'もどす',
      noLabel: 'やめる',
      icon: Icons.undo,
    );
    if (!ok) return;
    final latest = ref.read(characterByIdProvider(c.id)) ?? c;
    await ref.read(drawingLoopStorageProvider).deleteAsset(c.id, asset);
    await ref
        .read(charactersProvider.notifier)
        .save(
          latest.copyWith(
            cosmetics: latest.cosmetics.copyWith(
              effects: {...latest.cosmetics.effects}..remove(move),
            ),
          ),
        );
  }
}
