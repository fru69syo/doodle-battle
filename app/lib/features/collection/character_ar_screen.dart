import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/app_state.dart';
import '../ar/ar.dart';

/// Opens the AR team's [ArViewScreen]. The ARCore install prompt is never
/// offered here (children's screen); parents can install ARCore from
/// おうちのひと (behind the parental gate). See SPEC §10.
class CharacterArScreen extends ConsumerWidget {
  const CharacterArScreen({super.key, required this.characterId});
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
    final repo = ref.read(characterRepositoryProvider);
    return ArViewScreen(
      character: c,
      allowArCoreInstallPrompt: false,
      dependencies: ArViewDependencies(
        readImage: (_) async {
          final bytes = await repo.readImage(c.id);
          if (bytes == null) throw StateError('missing image');
          return bytes;
        },
      ),
    );
  }
}
