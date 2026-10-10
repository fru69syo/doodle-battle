/// Seams of the video export feature (overridden in tests).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'video_encoder.dart';
import 'video_exporter.dart';
import 'video_sharer.dart';

final videoEncoderProvider = Provider<VideoEncoder>(
  (ref) => MethodChannelVideoEncoder(),
);

final videoExporterProvider = Provider<VideoExporter>(
  (ref) => VideoExporter(ref.watch(videoEncoderProvider)),
);

/// Whether the preview plays (tests turn it off so frames can settle).
final videoPreviewAutoplayProvider = Provider<bool>((ref) => true);

final videoSharerProvider = Provider<VideoSharer>(
  (ref) => const PlatformVideoSharer(),
);

/// Bundled asset loader (CPU doodles).
final videoAssetLoaderProvider = Provider<Future<Uint8List> Function(String)>(
  (ref) =>
      (key) async => (await rootBundle.load(key)).buffer.asUint8List(),
);

/// Directory for exported videos: `<cache>/video_export`. Emptied before
/// each export and when the export screen closes (docs/VIDEO.md §5).
final videoExportDirProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}/video_export',
    );
    await dir.create(recursive: true);
    return dir;
  },
);

/// `oekaki_fighters_20261010_153012.mp4` — no character or child name.
String videoFileName(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'oekaki_fighters_${t.year}${two(t.month)}${two(t.day)}_'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}.mp4';
}
