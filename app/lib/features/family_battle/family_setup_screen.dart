import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/widgets/character_picture.dart';
import '../../core/widgets/attr_badge.dart';
import '../../data/app_state.dart';
import '../../domain/character_v2.dart';
import 'family_setup.dart';
import 'family_theme.dart';

/// 「かぞくで たいせん」: choose two players' characters and the ハンデ.
class FamilySetupScreen extends ConsumerStatefulWidget {
  const FamilySetupScreen({super.key});

  @override
  ConsumerState<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends ConsumerState<FamilySetupScreen> {
  FamilyBattleConfig? _config;

  /// Defaults: newest character for あか, the one before it for あお (the
  /// same one when there is only one: a mirror match).
  FamilyBattleConfig _defaults(List<CharacterV2> chars) {
    final newest = chars.last;
    final second = chars.length > 1 ? chars[chars.length - 2] : newest;
    return FamilyBattleConfig(
      a: FamilyPlayer(label: familyPlayerLabels[0], character: newest),
      b: FamilyPlayer(label: familyPlayerLabels[1], character: second),
    );
  }

  /// Keeps the chosen characters in sync with the ずかん (level changes,
  /// release).
  FamilyBattleConfig? _resolve(List<CharacterV2> chars) {
    if (chars.isEmpty) return null;
    final base = _config ?? _defaults(chars);
    CharacterV2 fresh(CharacterV2 c) =>
        chars.where((x) => x.id == c.id).firstOrNull ?? chars.last;
    return base.copyWith(
      a: base.a.copyWith(character: fresh(base.a.character)),
      b: base.b.copyWith(character: fresh(base.b.character)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chars = ref.watch(charactersProvider).value;
    final config = chars == null ? null : _resolve(chars);
    return Scaffold(
      appBar: AppBar(title: const Text('かぞくで たいせん')),
      body: SafeArea(
        child: chars == null
            ? const Center(child: CircularProgressIndicator())
            : config == null
            ? const _NoCharacters()
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '1だいの スマホで こうたいに わざを えらぶよ。'
                    'あいての ばんの ときは みないでね！',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  for (final side in FamilySide.values) ...[
                    _PlayerPanel(
                      side: side,
                      config: config,
                      characters: chars,
                      onChanged: (p) => setState(
                        () => _config = side == FamilySide.a
                            ? config.copyWith(a: p)
                            : config.copyWith(b: p),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: SwitchListTile(
                      key: const Key('family-same-level'),
                      value: config.sameLevel,
                      onChanged: (v) => setState(
                        () => _config = config.copyWith(sameLevel: v),
                      ),
                      title: const Text(
                        'おなじ レベルで たたかう',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: const Text('ひくい ほうの レベルを たかい ほうに あわせるよ'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'かぞくで たいせんは れんしゅう バトル。けいけんちは ふえないよ',
                    key: Key('family-no-xp-note'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('family-start'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                    ),
                    icon: const Icon(Icons.sports_martial_arts),
                    label: const Text('たいせん スタート！'),
                    onPressed: () =>
                        context.push(Routes.familyBattle, extra: config),
                  ),
                ],
              ),
      ),
    );
  }
}

class _NoCharacters extends StatelessWidget {
  const _NoCharacters();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'まずは えを かいて キャラを つくろう！',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.pushReplacement(Routes.draw),
            child: const Text('かく'),
          ),
        ],
      ),
    ),
  );
}

/// One player: name, character and ハンデ.
class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({
    required this.side,
    required this.config,
    required this.characters,
    required this.onChanged,
  });

  final FamilySide side;
  final FamilyBattleConfig config;
  final List<CharacterV2> characters;
  final ValueChanged<FamilyPlayer> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = config.player(side);
    final colour = familyColour(side);
    final c = p.character;
    final level = config.battleLevel(side);
    return Card(
      key: Key('family-panel-${side.name}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colour, width: 4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: Key('family-name-${side.name}'),
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final label = await _pickLabel(context, side, p.label);
                if (label != null) onChanged(p.copyWith(label: label));
              },
              child: Row(
                children: [
                  Icon(Icons.person, color: colour, size: 32),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      p.label,
                      key: Key('family-label-${side.name}'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: colour,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit, color: colour, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              key: Key('family-pick-${side.name}'),
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final picked = await _pickCharacter(
                  context,
                  p.label,
                  characters,
                );
                if (picked != null) onChanged(p.copyWith(character: picked));
              },
              child: Row(
                children: [
                  CharacterPicture(character: c, size: 88),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          key: Key('family-char-${side.name}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Lv$level',
                              key: Key('family-level-${side.name}'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (level != c.level)
                              const Icon(
                                Icons.arrow_upward,
                                color: Color(0xFF2E9E44),
                              ),
                            AttrBadge(c.attribute()),
                          ],
                        ),
                        const Text(
                          'タップで キャラを かえる',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'ハンデ',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                for (final b in familyBoostChoices)
                  ChoiceChip(
                    key: Key('family-boost-${side.name}-$b'),
                    label: Text(b == 0 ? 'なし' : 'Lv＋$b'),
                    selected: p.boost == b,
                    onSelected: (_) => onChanged(p.copyWith(boost: b)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _pickLabel(
  BuildContext context,
  FamilySide side,
  String current,
) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'なまえを えらんでね',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final l in familyPlayerLabels)
                ChoiceChip(
                  key: Key('family-label-option-$l'),
                  label: Text(l, style: const TextStyle(fontSize: 18)),
                  selected: l == current,
                  selectedColor: familyColour(side).withValues(alpha: 0.25),
                  onSelected: (_) => Navigator.of(context).pop(l),
                ),
            ],
          ),
        ],
      ),
    ),
  ),
);

Future<CharacterV2?> _pickCharacter(
  BuildContext context,
  String label,
  List<CharacterV2> characters,
) => showModalBottomSheet<CharacterV2>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(
        children: [
          Text(
            '$labelの キャラを えらんでね',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const Text('おなじ キャラ どうしでも たたかえるよ'),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.8,
              ),
              itemCount: characters.length,
              itemBuilder: (context, i) {
                final c = characters[characters.length - 1 - i];
                return Card(
                  key: Key('family-option-${c.id}'),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(c),
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
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text('Lv${c.level}'),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  ),
);
