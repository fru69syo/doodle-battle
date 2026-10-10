import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/big_button.dart';
import '../draw/drawing_services.dart';
import '../drawing_analysis/drawing_analyzer.dart'
    show UndecodableImageException;

sealed class LoopCapture {
  const LoopCapture();
}

/// The cut-out (transparent background, ≤ 512 px) of the new drawing.
class LoopCaptured extends LoopCapture {
  const LoopCaptured(this.cutoutPng);
  final Uint8List cutoutPng;
}

/// The analyzer turned the photo down (too empty, not a paper drawing, …):
/// [message] is its kind hiragana text.
class LoopRejected extends LoopCapture {
  const LoopRejected(this.message);
  final String message;
}

class LoopUnreadable extends LoopCapture {
  const LoopUnreadable();
}

class LoopCancelled extends LoopCapture {
  const LoopCancelled();
}

/// Photo of a paper drawing → the same on-device analyzer as a new
/// character (so every check of the analyzer, including the Trust team's
/// "paper drawings only" checks, applies to parts and effects too) → its
/// cut-out. Camera only: like new characters, children capture paper.
Future<LoopCapture> captureLoopDrawing(WidgetRef ref) async {
  final bytes = await ref
      .read(drawingImageSourceProvider)
      .pick(PhotoSource.camera);
  if (bytes == null) return const LoopCancelled();
  try {
    final o = await ref.read(drawingAnalyzerProvider).analyze(bytes);
    final reject = o.rejectReason;
    if (reject != null) return LoopRejected(reject.message);
    return LoopCaptured(o.result.cutoutPng);
  } on UndecodableImageException {
    return const LoopUnreadable();
  }
}

const unreadableMessage = 'しゃしんが よめなかったよ。もういちど とってみてね';

/// Intro shown before taking the photo of a part / effect.
class LoopCaptureIntro extends StatelessWidget {
  const LoopCaptureIntro({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onCapture,
    this.color = AppColors.primary,
    this.header,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onCapture;
  final Color color;
  final Widget? header;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      ?header,
      Icon(icon, size: 88, color: color),
      const SizedBox(height: 8),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(
        hint,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 17),
      ),
      const SizedBox(height: 8),
      const Card(
        color: Color(0xFFFFF1C9),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'しろい かみに、ふとい せんで おおきく かいてね。あかるい ところで とろう！',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
      const SizedBox(height: 20),
      BigActionButton(
        key: const Key('loop-capture'),
        icon: Icons.photo_camera,
        label: 'しゃしんを とる',
        color: color,
        onPressed: onCapture,
      ),
    ],
  );
}

/// Static "done" state (shown under the stamp dialog).
class LoopDone extends StatelessWidget {
  const LoopDone({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(Icons.check_circle, size: 96, color: AppColors.success),
  );
}

class LoopBusy extends StatelessWidget {
  const LoopBusy({super.key, this.text = 'えを しらべているよ…'});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(strokeWidth: 8),
        ),
        const SizedBox(height: 20),
        Text(
          text,
          key: const Key('loop-busy'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
