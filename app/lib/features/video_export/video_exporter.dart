/// Renders every frame off-screen and feeds it to the encoder, with progress
/// and cancellation (docs/VIDEO.md §4).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'video_composer.dart';
import 'video_encoder.dart';
import 'video_frame_renderer.dart';
import 'video_timeline.dart';

/// Thrown by [VideoExporter.export] after [ExportCancelToken.cancel].
class VideoExportCancelled implements Exception {
  const VideoExportCancelled();
}

class ExportCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

typedef FrameSourceFactory = FrameSource Function(
  VideoComposer composer,
  int width,
  int height,
);

FrameSource _renderer(VideoComposer composer, int width, int height) =>
    VideoFrameRenderer(composer, width: width, height: height);

class VideoExporter {
  VideoExporter(
    this.encoder, {
    this.bitrate = 4000000,
    @visibleForTesting this.frames = _renderer,
  });

  final VideoEncoder encoder;
  final int bitrate;

  /// Where frames come from (the off-screen renderer; fakes in tests).
  final FrameSourceFactory frames;

  /// Sizes tried in order (some older encoders cap the height at 1088).
  static const sizes = [
    (kVideoWidth, kVideoHeight),
    (kVideoFallbackWidth, kVideoFallbackHeight),
  ];

  /// Encodes the whole video to [path]. [onProgress] gets 0..1.
  Future<EncodedVideo> export(
    VideoComposer composer, {
    required String path,
    void Function(double progress)? onProgress,
    ExportCancelToken? cancel,
  }) async {
    final fps = composer.timeline.fps;
    (int, int)? size;
    for (final (w, h) in sizes) {
      try {
        await encoder.start(
          VideoEncoderConfig(
            path: path,
            width: w,
            height: h,
            fps: fps,
            bitrate: (bitrate * (w * h) / (kVideoWidth * kVideoHeight)).round(),
          ),
        );
        size = (w, h);
        break;
      } on VideoEncoderException catch (e) {
        if (e.code != VideoEncoderErrors.sizeUnsupported) rethrow;
      }
    }
    if (size == null) {
      throw const VideoEncoderException(VideoEncoderErrors.sizeUnsupported);
    }
    final renderer = frames(composer, size.$1, size.$2);
    final n = renderer.frameCount;
    Future<void>? pending;
    try {
      for (var i = 0; i < n; i++) {
        if (cancel?.isCancelled ?? false) throw const VideoExportCancelled();
        // Render frame i while the encoder still works on frame i - 1.
        final rgba = await renderer.renderRgba(i);
        if (pending != null) await pending;
        if (cancel?.isCancelled ?? false) throw const VideoExportCancelled();
        pending = encoder.addFrame(rgba)..ignore();
        onProgress?.call(0.97 * i / n);
      }
      if (pending != null) await pending;
      if (cancel?.isCancelled ?? false) throw const VideoExportCancelled();
      final video = await encoder.finish();
      onProgress?.call(1);
      return video;
    } on Object {
      await encoder.cancel();
      rethrow;
    }
  }
}
