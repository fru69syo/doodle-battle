import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/big_button.dart';
import '../../data/app_state.dart';
import '../birth/pending_birth.dart';
import 'album_import.dart';
import 'capture_guide.dart';
import 'draw_flow.dart';
import 'drawing_services.dart';

/// 「かく」: take a photo of the paper drawing and analyse it (SPEC §11.1).
///
/// The camera is the only input for children. A parent can import one
/// picture from the album via おうちのひと → 「アルバムから とりこむ」, which
/// arms [albumImportArmProvider]; that picture goes through exactly the same
/// checks. Before the first shot a capture guide is shown, and every
/// rejection ends in a friendly retake flow.
class DrawScreen extends ConsumerStatefulWidget {
  const DrawScreen({super.key});

  @override
  ConsumerState<DrawScreen> createState() => _DrawScreenState();
}

class _DrawScreenState extends ConsumerState<DrawScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(albumImportArmProvider.notifier).consume()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pick(PhotoSource.gallery);
      });
    }
  }

  /// Camera: show the capture guide first (once per app session, and again
  /// after a "not a paper drawing" / unreadable retake).
  Future<void> _shoot() async {
    final seen = ref.read(captureGuideSeenProvider.notifier);
    if (!ref.read(captureGuideSeenProvider)) {
      final go = await showCaptureGuide(context);
      if (!go || !mounted) return;
      seen.set(true);
    }
    await _pick(PhotoSource.camera);
  }

  Future<void> _pick(PhotoSource source) async {
    final bytes = await ref.read(drawingImageSourceProvider).pick(source);
    if (bytes == null || !mounted) return;
    setState(() => _busy = true);
    final outcome = await ref.read(drawFlowProvider).process(bytes);
    if (!mounted) return;
    setState(() => _busy = false);
    final RetakeKind kind;
    final String message;
    switch (outcome) {
      case DrawReady(:final birth):
        ref.read(pendingBirthProvider.notifier).set(birth);
        context.pushReplacement(Routes.birth);
        return;
      case DrawRetake(message: final msg, :final notPaperDrawing):
        kind = notPaperDrawing ? RetakeKind.notPaper : RetakeKind.drawMore;
        message = msg;
      case DrawUnreadable():
        kind = RetakeKind.unreadable;
        message = 'しゃしんが よめなかったよ。もういちど とってみてね';
    }
    final again = await showRetake(context, kind: kind, message: message);
    if (!again || !mounted) return;
    if (kind != RetakeKind.drawMore) {
      ref.read(captureGuideSeenProvider.notifier).set(false);
    }
    await _shoot();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(charactersProvider).value?.length ?? 0;
    final full = count >= ref.watch(collectionLimitProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('かく')),
      body: SafeArea(
        child: _busy
            ? const _Analyzing()
            : full
            ? const _CollectionFull()
            : _Choices(onShoot: _shoot),
      ),
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({required this.onShoot});
  final VoidCallback onShoot;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Icon(Icons.draw, size: 96, color: AppColors.primary),
      const SizedBox(height: 8),
      const Text(
        'かみに すきな えを かいてね。\nかみ ぜんぶが うつるように とってね！',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 16),
      const CaptureTips(),
      const SizedBox(height: 24),
      BigActionButton(
        key: const Key('draw-camera'),
        icon: Icons.photo_camera,
        label: 'しゃしんを とる',
        color: AppColors.primary,
        onPressed: onShoot,
      ),
    ],
  );
}

class _Analyzing extends StatelessWidget {
  const _Analyzing();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: CircularProgressIndicator(strokeWidth: 10),
        ),
        SizedBox(height: 24),
        Text(
          'えを しらべているよ…',
          key: Key('draw-analyzing'),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _CollectionFull extends StatelessWidget {
  const _CollectionFull();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.inventory_2, size: 96, color: AppColors.gold),
        const SizedBox(height: 16),
        const Text(
          'ずかんが いっぱい！\nあたらしい キャラを ふやすには、ずかんで おわかれ する キャラを えらんでね',
          key: Key('draw-full'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.pushReplacement(Routes.zukan),
          child: const Text('ずかんを ひらく'),
        ),
      ],
    ),
  );
}
