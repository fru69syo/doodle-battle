import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/character_picture.dart';
import '../../data/app_state.dart';
import 'card_content.dart';

/// Choose up to [cardsPerSheet] characters from the ずかん for one A4 sheet.
class CardSelectScreen extends ConsumerStatefulWidget {
  const CardSelectScreen({super.key});

  @override
  ConsumerState<CardSelectScreen> createState() => _CardSelectScreenState();
}

class _CardSelectScreenState extends ConsumerState<CardSelectScreen> {
  final _selected = <String>[];

  void _toggle(String id) {
    setState(() {
      if (_selected.remove(id)) return;
      if (_selected.length >= cardsPerSheet) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('1まいの かみに 9まいまで だよ')));
        return;
      }
      _selected.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chars = ref.watch(charactersProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('カードに する キャラ')),
      body: SafeArea(
        child: chars == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'えらんでね  ${_selected.length} / $cardsPerSheet',
                      key: const Key('card-select-count'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 160,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.8,
                          ),
                      itemCount: chars.length,
                      itemBuilder: (context, i) {
                        final c = chars[i];
                        final on = _selected.contains(c.id);
                        return Card(
                          key: Key('card-select-${c.id}'),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: on
                                  ? AppColors.primary
                                  : Colors.transparent,
                              width: 4,
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _toggle(c.id),
                            child: Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: LayoutBuilder(
                                          builder: (context, box) =>
                                              CharacterPicture(
                                                character: c,
                                                size:
                                                    box.maxHeight < box.maxWidth
                                                    ? box.maxHeight
                                                    : box.maxWidth,
                                              ),
                                        ),
                                      ),
                                      Text(
                                        c.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Icon(
                                    on
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: on
                                        ? AppColors.primary
                                        : AppColors.disabled,
                                    size: 32,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      key: const Key('card-select-next'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(60),
                      ),
                      icon: const Icon(Icons.style),
                      label: const Text('カードを みる'),
                      onPressed: _selected.isEmpty
                          ? null
                          : () => context.push(Routes.cardPrint(_selected)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
