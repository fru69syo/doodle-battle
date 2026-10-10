import 'dart:typed_data';

import 'package:doodle_battle/features/video_export/video_composer.dart';
import 'package:doodle_battle/features/video_export/video_encoder.dart';
import 'package:doodle_battle/features/video_export/video_exporter.dart';
import 'package:doodle_battle/features/video_export/video_frame_renderer.dart';
import 'package:doodle_battle/features/video_export/video_timeline.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_fixtures.dart';

/// Records calls like the Kotlin side would receive them.
class FakeEncoder implements VideoEncoder {
  FakeEncoder({this.rejectSizes = const {}, this.failAtFrame});

  final Set<(int, int)> rejectSizes;
  final int? failAtFrame;
  final starts = <VideoEncoderConfig>[];
  final frameSizes = <int>[];
  var finished = false;
  var cancelled = 0;

  @override
  Future<void> start(VideoEncoderConfig config) async {
    starts.add(config);
    if (rejectSizes.contains((config.width, config.height))) {
      throw const VideoEncoderException(VideoEncoderErrors.sizeUnsupported);
    }
  }

  @override
  Future<void> addFrame(Uint8List rgba) async {
    if (failAtFrame == frameSizes.length) {
      throw const VideoEncoderException(VideoEncoderErrors.failed, 'boom');
    }
    frameSizes.add(rgba.length);
  }

  @override
  Future<EncodedVideo> finish() async {
    finished = true;
    return EncodedVideo(
      path: starts.last.path,
      bytes: 1234,
      duration: Duration(microseconds: frameSizes.length * 1000000 ~/ 30),
      frames: frameSizes.length,
    );
  }

  @override
  Future<void> cancel() async => cancelled++;
}

class FakeFrames implements FrameSource {
  FakeFrames(this.width, this.height, this.frameCount);
  final int width;
  final int height;
  @override
  final int frameCount;
  final rendered = <int>[];

  @override
  Future<Uint8List> renderRgba(int index) async {
    rendered.add(index);
    return Uint8List(width * height * 4);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelVideoEncoder contract', () {
    const channel = MethodChannel(MethodChannelVideoEncoder.channelName);
    final calls = <MethodCall>[];
    late Object? Function(MethodCall) reply;

    setUp(() {
      calls.clear();
      reply = (_) => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return reply(call);
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('start → addFrame → finish', () async {
      final enc = MethodChannelVideoEncoder();
      await enc.start(
        const VideoEncoderConfig(
          path: '/tmp/x.mp4',
          width: 720,
          height: 1280,
          fps: 30,
          bitrate: 4000000,
        ),
      );
      await enc.addFrame(Uint8List(16));
      reply = (call) => {
        'path': '/tmp/x.mp4',
        'bytes': 5000000,
        'durationUs': 13400000,
        'frames': 402,
      };
      final v = await enc.finish();
      expect(calls.map((c) => c.method), ['start', 'addFrame', 'finish']);
      expect(calls[0].arguments, {
        'path': '/tmp/x.mp4',
        'width': 720,
        'height': 1280,
        'fps': 30,
        'bitrate': 4000000,
      });
      expect((calls[1].arguments as Map)['rgba'], isA<Uint8List>());
      expect(((calls[1].arguments as Map)['rgba'] as Uint8List).length, 16);
      expect(v.path, '/tmp/x.mp4');
      expect(v.bytes, 5000000);
      expect(v.duration, const Duration(milliseconds: 13400));
      expect(v.frames, 402);
    });

    test('platform errors become VideoEncoderException codes', () async {
      reply = (_) => throw PlatformException(
        code: VideoEncoderErrors.sizeUnsupported,
        message: 'nope',
      );
      expect(
        () => MethodChannelVideoEncoder().start(
          const VideoEncoderConfig(path: 'p', width: 1, height: 1, fps: 30),
        ),
        throwsA(
          isA<VideoEncoderException>().having(
            (e) => e.code,
            'code',
            VideoEncoderErrors.sizeUnsupported,
          ),
        ),
      );
    });

    test('cancel swallows errors', () async {
      reply = (_) => throw PlatformException(code: 'not_started');
      await MethodChannelVideoEncoder().cancel();
      expect(calls.single.method, 'cancel');
    });

    test('no platform side → unavailable', () async {
      final enc = MethodChannelVideoEncoder(
        const MethodChannel('doodle_battle/video_encoder_missing'),
      );
      expect(
        () => enc.addFrame(Uint8List(4)),
        throwsA(
          isA<VideoEncoderException>().having(
            (e) => e.code,
            'code',
            VideoEncoderErrors.unavailable,
          ),
        ),
      );
    });
  });

  group('VideoExporter', () {
    late VideoComposer composer;
    setUpAll(() async => composer = await sampleComposer());

    FakeFrames? frames;
    VideoExporter exporter(FakeEncoder enc, {int count = 12}) => VideoExporter(
      enc,
      frames: (c, w, h) => frames = FakeFrames(w, h, count),
    );

    test('feeds every frame in order, reports progress, finishes', () async {
      final enc = FakeEncoder();
      final progress = <double>[];
      final v = await exporter(enc)
          .export(composer, path: '/tmp/a.mp4', onProgress: progress.add);
      expect(enc.starts.single.width, kVideoWidth);
      expect(enc.starts.single.height, kVideoHeight);
      expect(enc.starts.single.fps, 30);
      expect(frames!.rendered, List.generate(12, (i) => i));
      expect(enc.frameSizes, List.filled(12, kVideoWidth * kVideoHeight * 4));
      expect(enc.finished, isTrue);
      expect(v.frames, 12);
      expect(progress.last, 1);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    });

    test('falls back to 576×1024 when the encoder rejects 720×1280', () async {
      final enc = FakeEncoder(rejectSizes: {(kVideoWidth, kVideoHeight)});
      await exporter(enc).export(composer, path: '/tmp/a.mp4');
      expect(enc.starts.map((s) => (s.width, s.height)), [
        (kVideoWidth, kVideoHeight),
        (kVideoFallbackWidth, kVideoFallbackHeight),
      ]);
      expect(
        enc.frameSizes.first,
        kVideoFallbackWidth * kVideoFallbackHeight * 4,
      );
      expect(enc.starts.last.bitrate, lessThan(enc.starts.first.bitrate));
    });

    test('cancel stops early and cancels the encoder', () async {
      final enc = FakeEncoder();
      final token = ExportCancelToken();
      await expectLater(
        exporter(enc, count: 100).export(
          composer,
          path: '/tmp/a.mp4',
          cancel: token,
          onProgress: (p) {
            if (p > 0.2) token.cancel();
          },
        ),
        throwsA(isA<VideoExportCancelled>()),
      );
      expect(enc.frameSizes.length, lessThan(100));
      expect(enc.finished, isFalse);
      expect(enc.cancelled, 1);
    });

    test('an encoder failure cancels and surfaces the error', () async {
      final enc = FakeEncoder(failAtFrame: 3);
      await expectLater(
        exporter(enc).export(composer, path: '/tmp/a.mp4'),
        throwsA(isA<VideoEncoderException>()),
      );
      expect(enc.cancelled, 1);
      expect(enc.finished, isFalse);
    });
  });
}
