/// Off-screen rendering of video frames at a fixed resolution.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'video_composer.dart';
import 'video_timeline.dart';

/// Source of raw frames for the exporter.
abstract interface class FrameSource {
  int get frameCount;
  Future<Uint8List> renderRgba(int index);
}

class VideoFrameRenderer implements FrameSource {
  VideoFrameRenderer(
    this.composer, {
    this.width = kVideoWidth,
    this.height = kVideoHeight,
  });

  final VideoComposer composer;
  final int width;
  final int height;

  VideoTimeline get timeline => composer.timeline;
  @override
  int get frameCount => timeline.frameCount;

  /// Frame [index] as an image of [width]×[height] (caller disposes).
  Future<ui.Image> renderImage(int index) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(
      rec,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    canvas.scale(width / kVideoWidth, height / kVideoHeight);
    // Opaque base so the RGBA frame never carries transparency.
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, kVideoWidth * 1.0, kVideoHeight * 1.0),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    composer.paint(canvas, timeline.timeOfFrame(index));
    final picture = rec.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// Frame [index] as tightly packed RGBA bytes (width × height × 4).
  @override
  Future<Uint8List> renderRgba(int index) async {
    final image = await renderImage(index);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('frame $index could not be read');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  /// Frame [index] as PNG (debug frame dumps).
  Future<Uint8List> renderPng(int index) async {
    final image = await renderImage(index);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('frame $index could not be encoded');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }
}
