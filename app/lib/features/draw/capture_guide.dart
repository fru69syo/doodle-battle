import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';

/// The three capture tips (SPEC §11.3): white paper, bold lines, a bright
/// place.
const captureTips = <(IconData, String)>[
  (Icons.description, 'しろい かみ'),
  (Icons.brush, 'ふとい せん'),
  (Icons.wb_sunny, 'あかるい ばしょ'),
];

/// Compact row of the capture tips.
class CaptureTips extends StatelessWidget {
  const CaptureTips({super.key});

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('capture-tips'),
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (final (icon, label) in captureTips)
        Flexible(
          child: Column(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFFFF1C9),
                child: Icon(icon, size: 30, color: AppColors.primary),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Guide shown before the camera opens. Returns true to take the photo.
Future<bool> showCaptureGuide(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('capture-guide'),
      icon: const Icon(Icons.photo_camera, size: 56),
      title: const Text('とる まえに', textAlign: TextAlign.center),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CaptureTips(),
          SizedBox(height: 16),
          Text(
            'かみ ぜんぶが うつるように、まっすぐ うえから とってね',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          key: const Key('guide-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('やめる'),
        ),
        FilledButton.icon(
          key: const Key('guide-shoot'),
          icon: const Icon(Icons.photo_camera),
          onPressed: () => Navigator.of(context).pop(true),
          label: const Text('とる！'),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Why a photo could not become a character.
enum RetakeKind {
  /// Too little drawn (「もうすこし かいてみよう」).
  drawMore,

  /// Not a drawing on paper (「かみに かいた えを とってね」).
  notPaper,

  /// The file could not be read.
  unreadable,
}

/// Friendly retake prompt. Never blames the child: it only says what to do
/// next. Returns true when the child wants to take a new photo now.
Future<bool> showRetake(
  BuildContext context, {
  required RetakeKind kind,
  required String message,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: Key('retake-${kind.name}'),
      icon: Icon(
        kind == RetakeKind.drawMore ? Icons.edit : Icons.photo_camera,
        size: 56,
        color: AppColors.primary,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            key: const Key('retake-message'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          if (kind != RetakeKind.drawMore) ...[
            const SizedBox(height: 16),
            const CaptureTips(),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          key: const Key('retake-later'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('あとで'),
        ),
        FilledButton.icon(
          key: const Key('retake-again'),
          icon: const Icon(Icons.photo_camera),
          onPressed: () => Navigator.of(context).pop(true),
          label: Text(kind == RetakeKind.drawMore ? 'かきたして とる' : 'もういちど とる'),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Whether the capture guide was already shown in this app session (it is
/// shown again after every retake request).
class CaptureGuideSeen extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool seen) => state = seen;
}

final captureGuideSeenProvider = NotifierProvider<CaptureGuideSeen, bool>(
  CaptureGuideSeen.new,
);
