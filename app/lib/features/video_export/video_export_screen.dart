/// 「どうがに する」: preview, make, then (parent only) save or share the
/// Before/After video (SPEC §11.2-1, docs/VIDEO.md).
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/kid_dialogs.dart';
import '../../data/app_state.dart';
import '../../domain/battle/battle.dart' show BattleAction;
import '../../domain/cosmetics.dart' show DrawnMove;
import '../drawing_loop/display_image.dart';
import 'video_composer.dart';
import 'video_content_loader.dart';
import 'video_encoder.dart';
import 'video_export_providers.dart';
import 'video_exporter.dart';
import 'video_sharer.dart';
import 'video_timeline.dart';

/// Shown to the parent (after the gate) before anything leaves the app.
const videoPrivacyNoticeKid = 'えに なまえや がっこうめいが かいていないか かくにんしてね';
const videoPrivacyNoticeParent =
    'この動画には、紙に描いた絵・キャラクター・バトルの様子が入ります。'
    'お子さまの顔や声、撮影した部屋などは入りません。\n'
    'SNS などに投稿する前に、絵の中にお子さまの名前・学校名・住所などが'
    '書かれていないか確認してください。';

/// Parent notice; true when the parent confirmed.
Future<bool> showVideoPrivacyNotice(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const Key('video-notice'),
      icon: const Icon(Icons.privacy_tip, size: 48, color: AppColors.secondary),
      title: const Text('おうちの方へ', textAlign: TextAlign.center),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              videoPrivacyNoticeKid,
              key: Key('video-notice-kid'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 12),
            Text(videoPrivacyNoticeParent, style: TextStyle(fontSize: 15)),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          key: const Key('video-notice-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('やめる'),
        ),
        FilledButton(
          key: const Key('video-notice-ok'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('確認しました'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

enum _Phase { loading, ready, encoding, done, error }

class VideoExportScreen extends ConsumerStatefulWidget {
  const VideoExportScreen({super.key, required this.characterId});
  final String characterId;

  @override
  ConsumerState<VideoExportScreen> createState() => _VideoExportScreenState();
}

class _VideoExportScreenState extends ConsumerState<VideoExportScreen>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.loading;
  VideoComposer? _composer;
  late final AnimationController _preview = AnimationController(vsync: this);
  double _progress = 0;
  ExportCancelToken? _cancel;
  EncodedVideo? _video;
  String? _error;
  bool _parentOk = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _preview.dispose();
    unawaited(_deleteVideo());
    super.dispose();
  }

  Future<void> _deleteVideo() async {
    final path = _video?.path;
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on Object {
      // Cache dir; cleared on the next export anyway.
    }
  }

  Future<void> _load() async {
    try {
      final id = widget.characterId;
      final c = ref.read(characterByIdProvider(id));
      final repo = ref.read(characterRepositoryProvider);
      if (c == null) throw const VideoContentException('character not found');
      final display = ref.read(displayImageServiceProvider);
      final png = await display.displayImageFor(c);
      final original = await repo.readImage(id);
      if (png == null) {
        throw const VideoContentException('character image not found');
      }
      final effects = <BattleAction, Uint8List>{};
      for (final (action, move) in [
        (BattleAction.element, DrawnMove.element),
        (BattleAction.special, DrawnMove.special),
      ]) {
        final drawn = await display.effectImageFor(c, move);
        if (drawn != null) effects[action] = drawn;
      }
      final content = await loadVideoContent(
        character: c,
        displayPng: png,
        originalPng: original,
        moveEffectPngs: effects,
        before: await repo.readBeforePhoto(id),
        spec: await ref.read(battleSpecProvider.future),
        roster: await ref.read(cpuRosterProvider.future),
        loadAsset: ref.read(videoAssetLoaderProvider),
      );
      if (!mounted) return;
      final composer = VideoComposer(content);
      _preview.duration = Duration(
        milliseconds: (composer.timeline.duration * 1000).round(),
      );
      _playPreview();
      setState(() {
        _composer = composer;
        _phase = _Phase.ready;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '$e';
      });
    }
  }

  void _playPreview() {
    if (ref.read(videoPreviewAutoplayProvider)) {
      unawaited(_preview.repeat());
    } else {
      // Still frame from the battle (tests, reduced motion).
      _preview.value = 0.55;
    }
  }

  Future<void> _make() async {
    final composer = _composer;
    if (composer == null) return;
    final cancel = _cancel = ExportCancelToken();
    _preview.stop();
    setState(() {
      _phase = _Phase.encoding;
      _progress = 0;
    });
    try {
      final dir = await ref.read(videoExportDirProvider)();
      // Only one export is kept at a time.
      await for (final f in dir.list()) {
        if (f is File) await f.delete();
      }
      final path = '${dir.path}/${videoFileName(ref.read(clockProvider)())}';
      final video = await ref
          .read(videoExporterProvider)
          .export(
            composer,
            path: path,
            cancel: cancel,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (!mounted) return;
      setState(() {
        _video = video;
        _phase = _Phase.done;
      });
    } on VideoExportCancelled {
      if (!mounted) return;
      setState(() => _phase = _Phase.ready);
      _playPreview();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e is VideoEncoderException ? e.code : '$e';
      });
    }
  }

  Future<bool> _ensureParent() async {
    if (_parentOk) return true;
    final ok = await ref.read(parentalGateProvider).verify(context);
    if (!ok || !mounted) return false;
    final ack = await showVideoPrivacyNotice(context);
    if (!ack || !mounted) return false;
    setState(() => _parentOk = true);
    return true;
  }

  Future<void> _save() async {
    final video = _video;
    if (video == null || _busy || !await _ensureParent()) return;
    setState(() => _busy = true);
    final r = await ref.read(videoSharerProvider).saveToGallery(video.path);
    if (!mounted) return;
    setState(() => _busy = false);
    await showKidMessage(context, switch (r) {
      VideoSaveResult.saved => '動画をギャラリーに保存しました',
      VideoSaveResult.noPermission => '保存する許可がありません。端末の設定を確認してください',
      VideoSaveResult.noSpace => '空き容量が足りません',
      VideoSaveResult.failed => '保存できませんでした',
    }, icon: r == VideoSaveResult.saved ? Icons.check_circle : Icons.error);
  }

  Future<void> _share() async {
    final video = _video;
    if (video == null || _busy || !await _ensureParent()) return;
    setState(() => _busy = true);
    final ok = await ref.read(videoSharerProvider).share(video.path);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) await showKidMessage(context, '共有できませんでした', icon: Icons.error);
  }

  @override
  Widget build(BuildContext context) {
    final composer = _composer;
    final maxPreviewH = MediaQuery.sizeOf(context).height * 0.5;
    return Scaffold(
      appBar: AppBar(title: const Text('どうがに する')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: SizedBox(
                height: maxPreviewH,
                child: AspectRatio(
                  aspectRatio: kVideoWidth / kVideoHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: composer == null
                        ? const ColoredBox(
                            color: AppColors.background,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : CustomPaint(
                            key: const Key('video-preview'),
                            painter: VideoPreviewPainter(composer, _preview),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ..._controls(),
          ],
        ),
      ),
    );
  }

  List<Widget> _controls() {
    switch (_phase) {
      case _Phase.loading:
        return const [];
      case _Phase.ready:
        return [
          const Text(
            'かいた え が うごきだす どうがを つくるよ',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('video-make'),
            icon: const Icon(Icons.movie_creation),
            label: const Text('どうがを つくる'),
            onPressed: _make,
          ),
        ];
      case _Phase.encoding:
        return [
          const Text(
            'どうがを つくっているよ…',
            key: Key('video-progress-text'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            key: const Key('video-progress'),
            value: _progress,
            minHeight: 14,
            borderRadius: BorderRadius.circular(7),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('video-cancel'),
            onPressed: () => _cancel?.cancel(),
            child: const Text('やめる'),
          ),
        ];
      case _Phase.done:
        return [
          const Text(
            'できた！ おうちのひとに みせてね',
            key: Key('video-done'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (!_parentOk)
            FilledButton.icon(
              key: const Key('video-parent'),
              icon: const Icon(Icons.family_restroom),
              label: const Text('おうちのひとに わたす'),
              onPressed: _ensureParent,
            )
          else ...[
            FilledButton.icon(
              key: const Key('video-save'),
              icon: const Icon(Icons.download),
              label: const Text('ギャラリーに保存'),
              onPressed: _busy ? null : _save,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('video-share'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondary,
              ),
              icon: const Icon(Icons.share),
              label: const Text('共有する'),
              onPressed: _busy ? null : _share,
            ),
          ],
        ];
      case _Phase.error:
        return [
          Text(
            _error == VideoEncoderErrors.unavailable ||
                    _error == VideoEncoderErrors.sizeUnsupported
                ? 'この きかいでは どうがを つくれないみたい…'
                : 'うまく つくれなかったよ',
            key: const Key('video-error'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_composer != null)
            OutlinedButton(
              key: const Key('video-retry'),
              onPressed: _make,
              child: const Text('もういちど'),
            ),
        ];
    }
  }
}

/// Live preview: the same composer that renders the encoded frames.
class VideoPreviewPainter extends CustomPainter {
  VideoPreviewPainter(this.composer, this.clock) : super(repaint: clock);

  final VideoComposer composer;
  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / kVideoWidth, size.height / kVideoHeight);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, kVideoWidth * 1.0, kVideoHeight * 1.0),
      Paint()..color = Colors.white,
    );
    composer.paint(canvas, clock.value * composer.timeline.duration);
    canvas.restore();
  }

  @override
  bool shouldRepaint(VideoPreviewPainter old) => old.composer != composer;
}
