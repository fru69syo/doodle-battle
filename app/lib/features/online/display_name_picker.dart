import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/app_state.dart';
import '../../data/backend/backend_api.dart';
import 'online_messages.dart';

/// Bundled copy of shared/names/display_name_words.json (the server's
/// vocabulary; re-sync with `dart run tool/sync_shared_names.dart`).
const displayNameWordsAsset = 'assets/names/display_name_words.json';

class DisplayNameWord {
  const DisplayNameWord(this.id, this.text);
  final String id;
  final String text;
}

/// Preset words for online display names (adjective + noun). There is no
/// free text: the server only accepts these ids (docs/BACKEND.md §5).
class DisplayNameWords {
  const DisplayNameWords({required this.adjectives, required this.nouns});

  final List<DisplayNameWord> adjectives;
  final List<DisplayNameWord> nouns;

  factory DisplayNameWords.fromJsonString(String source) {
    final j = (jsonDecode(source) as Map).cast<String, Object?>();
    List<DisplayNameWord> words(String key) => [
      for (final w in (j[key]! as List).cast<Map<Object?, Object?>>())
        DisplayNameWord(w['id']! as String, w['text']! as String),
    ];
    return DisplayNameWords(
      adjectives: words('adjectives'),
      nouns: words('nouns'),
    );
  }

  DisplayNameWord? adjective(String id) =>
      adjectives.where((w) => w.id == id).firstOrNull;
  DisplayNameWord? noun(String id) =>
      nouns.where((w) => w.id == id).firstOrNull;

  /// Same composition as the server (`composeDisplayName`).
  String compose(DisplayNameWord a, DisplayNameWord n) => '${a.text} ${n.text}';
}

final displayNameWordsProvider = FutureProvider<DisplayNameWords>(
  (ref) async => DisplayNameWords.fromJsonString(
    await rootBundle.loadString(displayNameWordsAsset),
  ),
);

/// Lobby header: current online name + 「なまえを かえる」.
class DisplayNameCard extends ConsumerWidget {
  const DisplayNameCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(progressProvider).value?.displayName;
    // Custom row instead of ListTile: the tile's fixed paddings made the
    // title and the name wrap mid-word on 411 dp phones.
    return Card(
      key: const Key('display-name-card'),
      color: const Color(0xFFFFF4D6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            const Icon(Icons.badge, size: 36, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('オンラインの なまえ', style: TextStyle(fontSize: 15)),
                  Text(
                    name?.text ?? 'まだ きまって いないよ',
                    key: const Key('display-name-current'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('display-name-change'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(72, 56),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const DisplayNamePicker(),
              ),
              child: const Text('かえる'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choose an adjective and a noun; the server composes and stores the name.
class DisplayNamePicker extends ConsumerStatefulWidget {
  const DisplayNamePicker({super.key});

  @override
  ConsumerState<DisplayNamePicker> createState() => _DisplayNamePickerState();
}

class _DisplayNamePickerState extends ConsumerState<DisplayNamePicker> {
  String? _adjectiveId;
  String? _nounId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(progressProvider).value?.displayName;
    if (current != null && current.adjectiveId.isNotEmpty) {
      _adjectiveId = current.adjectiveId;
      _nounId = current.nounId;
    }
  }

  Future<void> _save(DisplayNameWords words) async {
    final a = _adjectiveId, n = _nounId;
    if (a == null || n == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(settingsProvider.notifier).ensureConsentSynced();
      final dn = await ref.read(backendApiProvider).setDisplayName(a, n);
      await ref.read(progressProvider.notifier).setDisplayName(dn);
      if (mounted) Navigator.of(context).pop();
    } on BackendException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = backendErrorMessage(e.code);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = ref.watch(displayNameWordsProvider).value;
    if (words == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final a = _adjectiveId == null ? null : words.adjective(_adjectiveId!);
    final n = _nounId == null ? null : words.noun(_nounId!);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'オンラインの なまえを えらぼう',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            a != null && n != null ? words.compose(a, n) : '？？？ ？？？',
            key: const Key('display-name-preview'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          Expanded(
            child: ListView(
              key: const Key('display-name-words'),
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                _WordGroup(
                  title: 'ようす',
                  prefix: 'adj',
                  words: words.adjectives,
                  selected: _adjectiveId,
                  onSelect: (id) => setState(() => _adjectiveId = id),
                ),
                const SizedBox(height: 12),
                _WordGroup(
                  title: 'なかま',
                  prefix: 'noun',
                  words: words.nouns,
                  selected: _nounId,
                  onSelect: (id) => setState(() => _nounId = id),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                key: const Key('display-name-error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger, fontSize: 18),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('やめる'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('display-name-save'),
                    onPressed: a == null || n == null || _saving
                        ? null
                        : () => _save(words),
                    child: Text(_saving ? 'まってね…' : 'これに する'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WordGroup extends StatelessWidget {
  const _WordGroup({
    required this.title,
    required this.prefix,
    required this.words,
    required this.selected,
    required this.onSelect,
  });

  final String title;
  final String prefix;
  final List<DisplayNameWord> words;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final w in words)
            ChoiceChip(
              key: Key('dn-$prefix-${w.id}'),
              label: Text(w.text, style: const TextStyle(fontSize: 17)),
              selected: selected == w.id,
              onSelected: (_) => onSelect(w.id),
            ),
        ],
      ),
    ],
  );
}
