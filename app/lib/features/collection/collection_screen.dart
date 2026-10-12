import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/character_picture.dart';
import '../../core/widgets/attr_badge.dart';
import '../../data/app_state.dart';
import '../../domain/character_v2.dart';
import '../../domain/character_v2_view.dart';

/// 「ずかん」: grid of the child's characters.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chars = ref.watch(charactersProvider).value;
    final limit = ref.watch(collectionLimitProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('ずかん  ${chars?.length ?? 0} / $limit'),
        actions: [
          if (chars != null && chars.isNotEmpty)
            TextButton.icon(
              key: const Key('zukan-cards'),
              icon: const Icon(Icons.style, size: 28),
              label: const Text('カード', style: TextStyle(fontSize: 18)),
              onPressed: () => context.push(Routes.cardSelect),
            ),
        ],
      ),
      body: SafeArea(
        child: chars == null
            ? const Center(child: CircularProgressIndicator())
            : chars.isEmpty
            ? const _Empty()
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: chars.length,
                itemBuilder: (context, i) => _CharacterCard(chars[i]),
              ),
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard(this.c);
  final CharacterV2 c;

  @override
  Widget build(BuildContext context) => Card(
    key: Key('zukan-card-${c.id}'),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.push(Routes.character(c.id)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => CharacterPicture(
                  character: c,
                  size: box.maxHeight < box.maxWidth
                      ? box.maxHeight
                      : box.maxWidth,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  Text(
                    'Lv${c.level} ',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  AttrBadge(c.attribute()),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.collections_bookmark,
            size: 96,
            color: AppColors.disabled,
          ),
          const SizedBox(height: 12),
          const Text(
            'まだ キャラが いないよ。えを かいて キャラを つくろう！',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.brush),
            label: const Text('かく'),
            onPressed: () => context.pushReplacement(Routes.draw),
          ),
        ],
      ),
    ),
  );
}
