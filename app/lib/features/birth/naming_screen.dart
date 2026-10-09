import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../data/app_state.dart';
import '../../data/character_repository.dart';
import '../../domain/character.dart';
import '../ng_filter/name_rules.dart';
import 'pending_birth.dart';

/// Naming with the offline NG filter (SPEC §2-3).
class NamingScreen extends ConsumerStatefulWidget {
  const NamingScreen({super.key});

  @override
  ConsumerState<NamingScreen> createState() => _NamingScreenState();
}

class _NamingScreenState extends ConsumerState<NamingScreen> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _newId() {
    final now = ref.read(clockProvider)().microsecondsSinceEpoch;
    final r = ref.read(randomProvider).nextInt(0xffff).toRadixString(16);
    return 'c_${now}_$r';
  }

  Future<void> _save(PendingBirth birth) async {
    setState(() => _saving = true);
    final repo = ref.read(characterRepositoryProvider);
    final id = _newId();
    final r = birth.result;
    final c = Character(
      id: id,
      name: canonicalName(_controller.text),
      imagePath: repo.imagePathFor(id),
      imageHash: r.imageHash,
      element: r.element,
      baseStats: r.baseStats,
      energy: r.energy,
      skill: r.skill,
      features: r.features,
      createdAt: ref.read(clockProvider)(),
      subject: birth.cloud?.subject,
      elementMoveName: birth.cloud?.elementMoveName,
      specialMoveName: birth.cloud?.specialMoveName,
    );
    try {
      await ref.read(charactersProvider.notifier).add(c, r.cutoutPng);
    } on CollectionFullException {
      if (!mounted) return;
      setState(() => _saving = false);
      await showKidMessage(context, 'ずかんが いっぱい！ ずかんで おわかれ する キャラを えらんでね');
      return;
    }
    if (!mounted) return;
    ref.read(pendingBirthProvider.notifier).clear();
    context.go(Routes.character(id));
  }

  @override
  Widget build(BuildContext context) {
    final birth = ref.watch(pendingBirthProvider);
    final filter = ref.watch(ngFilterProvider).value;
    if (birth == null || filter == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final problem = checkCharacterName(_controller.text, filter);
    final suggestions = {
      ...?birth.cloud?.suggestedNames,
      ...presetNamesFor(birth.result.imageHash),
    }.where((n) => checkCharacterName(n, filter) == null).take(5);
    return Scaffold(
      appBar: AppBar(title: const Text('なまえを つけよう')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: Image.memory(
                  birth.result.cutoutPng,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('name-field'),
              controller: _controller,
              maxLength: nameMaxLength,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(hintText: 'なまえ'),
            ),
            if (problem != null && problem != NameProblem.empty)
              Text(
                problem.message,
                key: const Key('name-problem'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'こんな なまえは どう？',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in suggestions)
                  ActionChip(
                    key: Key('name-suggestion-$n'),
                    label: Text(n, style: const TextStyle(fontSize: 20)),
                    padding: const EdgeInsets.all(8),
                    onPressed: () => _controller.text = n,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('name-save'),
              icon: const Icon(Icons.check_circle),
              label: const Text('これに きめた！'),
              onPressed: problem == null && !_saving
                  ? () => _save(birth)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
