import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/widgets/character_picture.dart';
import '../../core/widgets/attr_badge.dart';
import '../../data/app_state.dart';
import '../../domain/character_v2.dart';

/// Choose which character fights (バトル).
class BattleSelectScreen extends ConsumerWidget {
  const BattleSelectScreen({
    super.key,
    this.title = 'だれで たたかう？',
    this.onSelect,
    this.filter,
    this.header,
  });

  final String title;

  /// Defaults to opening the CPU stage list.
  final void Function(BuildContext context, CharacterV2 c)? onSelect;

  /// Characters that may be chosen (others are greyed out with the reason).
  final String? Function(CharacterV2 c)? filter;

  /// Shown above the list (e.g. the online display name).
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chars = ref.watch(charactersProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: chars == null
            ? const Center(child: CircularProgressIndicator())
            : chars.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ?header,
                      const Text(
                        'まずは えを かいて キャラを つくろう！',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => context.pushReplacement(Routes.draw),
                        child: const Text('かく'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  ?header,
                  for (final c in chars.reversed)
                    _Row(c: c, blocked: filter?.call(c), onTap: onSelect),
                ],
              ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.c, required this.blocked, required this.onTap});
  final CharacterV2 c;
  final String? blocked;
  final void Function(BuildContext context, CharacterV2 c)? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: blocked == null ? 1 : 0.5,
    child: Card(
      key: Key('select-${c.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: blocked != null
            ? null
            : () => onTap == null
                  ? context.push(Routes.stages(c.id))
                  : onTap!(context, c),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CharacterPicture(character: c, size: 80),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Lv${c.level}',
                          style: const TextStyle(fontSize: 18),
                        ),
                        AttrBadge(c.attribute()),
                      ],
                    ),
                    if (blocked != null)
                      Text(
                        blocked!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              if (blocked == null) const Icon(Icons.chevron_right, size: 40),
            ],
          ),
        ),
      ),
    ),
  );
}
