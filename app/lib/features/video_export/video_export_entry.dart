/// Entry points of the Before/After video: the button on the character
/// page (prominent right after naming), the battle result, plus the hook
/// that stores the paper photo when a character is born.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/before_photo.dart';
import '../../data/character_repository.dart';
import 'video_export_screen.dart';

/// Id of the character that was just named (birth → detail page shows the
/// big 「どうがに する」 card). Cleared when the video screen opens.
class JustBornCharacter extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String id) => state = id;
  void clear() => state = null;
}

final justBornCharacterProvider = NotifierProvider<JustBornCharacter, String?>(
  JustBornCharacter.new,
);

/// Stores the paper photo of a newly saved character. Waits at most
/// [timeout] for the background extraction; failures are ignored (the
/// video then falls back to the cut-out on paper).
Future<void> keepBeforePhoto(
  CharacterRepository repo,
  String id,
  Future<BeforePhoto?>? photo, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (photo == null) return;
  try {
    final p = await photo.timeout(timeout, onTimeout: () => null);
    if (p != null) await repo.saveBeforePhoto(id, p);
  } on Object {
    // Best effort.
  }
}

/// Opens the video screen for [characterId].
Future<void> openVideoExport(BuildContext context, String characterId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoExportScreen(characterId: characterId),
      ),
    );

/// 「どうがに する」 button. [prominent] shows it as a big card (right
/// after the character was born).
class VideoExportButton extends ConsumerWidget {
  const VideoExportButton({
    super.key,
    required this.characterId,
    this.prominent = false,
  });

  final String characterId;
  final bool prominent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open() {
      ref.read(justBornCharacterProvider.notifier).clear();
      unawaited(openVideoExport(context, characterId));
    }

    if (!prominent) {
      return FilledButton.icon(
        key: const Key('video-open'),
        style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
        icon: const Icon(Icons.movie_creation),
        label: const Text('どうがに する'),
        onPressed: open,
      );
    }
    return Card(
      key: const Key('video-open-card'),
      color: const Color(0xFFFFE6F2),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: open,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.movie_creation, size: 44, color: AppColors.pink),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'かいた え が うごきだす どうがを つくろう！',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.chevron_right, size: 32),
            ],
          ),
        ),
      ),
    );
  }
}
