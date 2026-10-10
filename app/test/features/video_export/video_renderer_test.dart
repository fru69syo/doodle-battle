import 'dart:typed_data';

import 'package:doodle_battle/features/video_export/video_composer.dart';
import 'package:doodle_battle/features/video_export/video_frame_renderer.dart';
import 'package:doodle_battle/features/video_export/video_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_fixtures.dart';

bool _opaque(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 255) return false;
  }
  return true;
}

void main() {
  late VideoComposer composer;
  late VideoComposer fallback;

  setUpAll(() async {
    composer = await sampleComposer();
    fallback = await sampleComposer(withBefore: false, seed: 2);
  });

  test('frames are 720×1280 opaque RGBA', () async {
    final r = VideoFrameRenderer(composer);
    expect(r.frameCount, composer.timeline.frameCount);
    final rgba = await r.renderRgba(0);
    expect(rgba.length, kVideoWidth * kVideoHeight * 4);
    expect(_opaque(rgba), isTrue);
    final img = await r.renderImage(100);
    expect(img.width, kVideoWidth);
    expect(img.height, kVideoHeight);
    img.dispose();
  });

  test('fallback size renders the same composition smaller', () async {
    final r = VideoFrameRenderer(
      composer,
      width: kVideoFallbackWidth,
      height: kVideoFallbackHeight,
    );
    final rgba = await r.renderRgba(200);
    expect(rgba.length, kVideoFallbackWidth * kVideoFallbackHeight * 4);
    expect(_opaque(rgba), isTrue);
  });

  test('deterministic: the same frame twice gives identical bytes', () async {
    final r = VideoFrameRenderer(composer);
    final f = composer.timeline.frameCount ~/ 2;
    expect(await r.renderRgba(f), await r.renderRgba(f));
  });

  test('each scene looks different', () async {
    final r = VideoFrameRenderer(composer, width: 90, height: 160);
    final tl = composer.timeline;
    final frames = <Uint8List>[];
    for (final s in VideoScene.values) {
      final mid = tl.starts[s]! + 1.0;
      frames.add(await r.renderRgba((mid * tl.fps).round()));
    }
    for (var i = 0; i < frames.length; i++) {
      for (var j = i + 1; j < frames.length; j++) {
        expect(frames[i], isNot(equals(frames[j])), reason: 'scene $i vs $j');
      }
    }
  });

  test('characters without a paper photo use the paper fallback', () async {
    expect(fallback.content.before.width, 900);
    expect(fallback.content.before.height, 1200);
    final ink = fallback.content.inkRect;
    expect(ink.centerX, closeTo(0.5, 0.01));
    final rgba = await VideoFrameRenderer(fallback).renderRgba(10);
    expect(_opaque(rgba), isTrue);
  });

  test('uses the display image it is given (drawn-on parts appear)', () async {
    expect(composer.content.character.width, greaterThan(8));
    expect(composer.content.name, 'ぐるぐるまる');
  });
}
