// Debug tool: renders a few frames of a sample Before/After video to PNG
// for visual review (docs/VIDEO.md §7). Skipped in normal runs (tag
// `video_frames`); run with `tool/video_frames.sh`.
@Tags(['video_frames'])
library;

import 'dart:io';

import 'package:doodle_battle/features/video_export/video_frame_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_fixtures.dart';

final _outDir =
    Platform.environment['VIDEO_FRAMES_DIR'] ?? 'build/video_frames';

void main() {
  test('dump sample frames', () async {
    await loadVideoFonts();
    Directory(_outDir).createSync(recursive: true);
    final all = Platform.environment['VIDEO_FRAMES_ALL'] == '1';
    for (final withBefore in [true, false]) {
      final composer = await sampleComposer(
        withBefore: withBefore,
        seed: withBefore ? 1 : 2,
        drawnEffect: !withBefore,
      );
      final r = VideoFrameRenderer(composer);
      final tl = composer.timeline;
      final times = all
          ? [for (var i = 0; i < r.frameCount; i++) tl.timeOfFrame(i)]
          : [
              0.2,
              2.6,
              3.45,
              3.52,
              3.8,
              4.1,
              4.6,
              5.5,
              6.3,
              7.1,
              7.6,
              8.1,
              9.3,
              10.4,
              11.2,
              11.6,
              12.6,
              13.3,
            ];
      final tag = withBefore ? 'photo' : 'fallback';
      for (final t in times) {
        final frame = (t * tl.fps).round().clamp(0, r.frameCount - 1);
        final png = await r.renderPng(frame);
        final name = all
            ? '${tag}_${frame.toString().padLeft(4, '0')}.png'
            : '${tag}_t${(t * 1000).round().toString().padLeft(5, '0')}.png';
        File('$_outDir/$name').writeAsBytesSync(png);
      }
      // ignore: avoid_print
      print(
        '$tag: ${tl.duration}s, ${r.frameCount} frames, '
        'hits=${composer.content.highlight.hits.length} '
        'cpu=${composer.content.highlight.cpu.name}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
