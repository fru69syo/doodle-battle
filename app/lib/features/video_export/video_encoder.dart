/// H.264/MP4 encoding on the device (docs/VIDEO.md §4). On Android the
/// platform side is `VideoEncoderPlugin.kt` (MediaCodec + MediaMuxer on a
/// background thread); no third-party native code.
library;

import 'package:flutter/services.dart';

/// Settings for one encode.
class VideoEncoderConfig {
  const VideoEncoderConfig({
    required this.path,
    required this.width,
    required this.height,
    required this.fps,
    this.bitrate = 4000000,
  });

  /// Output .mp4 path (overwritten).
  final String path;
  final int width;
  final int height;
  final int fps;

  /// Target bits per second.
  final int bitrate;

  Map<String, Object> toArgs() => {
    'path': path,
    'width': width,
    'height': height,
    'fps': fps,
    'bitrate': bitrate,
  };
}

/// Result of a finished encode.
class EncodedVideo {
  const EncodedVideo({
    required this.path,
    required this.bytes,
    required this.duration,
    required this.frames,
  });

  final String path;
  final int bytes;
  final Duration duration;
  final int frames;
}

/// Error codes of the encoder.
abstract final class VideoEncoderErrors {
  /// No H.264 encoder on the device accepts the requested size.
  static const sizeUnsupported = 'size_unsupported';

  /// No H.264 encoder at all (or the platform has none).
  static const unavailable = 'unavailable';

  /// `addFrame`/`finish` without a running encode.
  static const notStarted = 'not_started';

  /// Anything else that went wrong while encoding.
  static const failed = 'failed';
}

class VideoEncoderException implements Exception {
  const VideoEncoderException(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() =>
      'VideoEncoderException($code${message == null ? '' : ': $message'})';
}

/// Frame-by-frame encoder. One encode at a time: [start], then [addFrame]
/// for every frame in order, then [finish] (or [cancel] at any point).
abstract interface class VideoEncoder {
  Future<void> start(VideoEncoderConfig config);

  /// Encodes one frame of tightly packed RGBA (width × height × 4 bytes).
  /// Completes once the frame has been consumed, which throttles the
  /// renderer to the encoder's speed.
  Future<void> addFrame(Uint8List rgba);

  /// Flushes and closes the file.
  Future<EncodedVideo> finish();

  /// Stops and deletes the partial file. Safe to call at any time.
  Future<void> cancel();
}

/// [VideoEncoder] over the `doodle_battle/video_encoder` method channel.
///
/// Contract (also tested with a fake platform side):
/// - `start` {path, width, height, fps, bitrate} → null
/// - `addFrame` {rgba: Uint8List} → null (after the frame is encoded)
/// - `finish` → {path, bytes, durationUs, frames}
/// - `cancel` → null
/// Errors are PlatformExceptions with a [VideoEncoderErrors] code.
class MethodChannelVideoEncoder implements VideoEncoder {
  MethodChannelVideoEncoder([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'doodle_battle/video_encoder';

  final MethodChannel _channel;

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw VideoEncoderException(e.code, e.message);
    } on MissingPluginException {
      throw const VideoEncoderException(VideoEncoderErrors.unavailable);
    }
  }

  @override
  Future<void> start(VideoEncoderConfig config) =>
      _call<void>('start', config.toArgs());

  @override
  Future<void> addFrame(Uint8List rgba) =>
      _call<void>('addFrame', {'rgba': rgba});

  @override
  Future<EncodedVideo> finish() async {
    final r = await _call<Map<Object?, Object?>>('finish');
    if (r == null) {
      throw const VideoEncoderException(VideoEncoderErrors.failed, 'no result');
    }
    return EncodedVideo(
      path: r['path']! as String,
      bytes: (r['bytes']! as num).toInt(),
      duration: Duration(microseconds: (r['durationUs']! as num).toInt()),
      frames: (r['frames']! as num).toInt(),
    );
  }

  @override
  Future<void> cancel() async {
    try {
      await _call<void>('cancel');
    } on VideoEncoderException {
      // Nothing to cancel.
    }
  }
}
