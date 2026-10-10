import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:doodle_battle/data/before_photo.dart';
import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/drawing_analysis_result.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/video_export/before_photo_extractor.dart';
import 'package:doodle_battle/features/video_export/video_composer.dart';
import 'package:doodle_battle/features/video_export/video_content_loader.dart';

import '../../../tool/src/doodle_painter.dart';
import '../../support/harness.dart';
import '../drawing_analysis/synthetic_drawings.dart';

/// Registers Zen Maru Gothic so frames show the real font.
Future<void> loadVideoFonts() async {
  for (final f in ['Regular', 'Bold']) {
    final bytes = File('assets/fonts/ZenMaruGothic-$f.ttf').readAsBytesSync();
    await ui.loadFontFromList(bytes, fontFamily: 'ZenMaruGothic');
  }
}

Future<Uint8List> readAssetFile(String key) async =>
    File(key).readAsBytesSync();

/// A kid drawing on portrait paper, photographed on a table.
({Uint8List jpeg, DrawingAnalysisReport report}) photographedKidDrawing({
  int seed = 1,
}) {
  final paper = kidScribble(seed: seed, width: 600, height: 800);
  final photo = photographedOnTable(paper, width: 1200, height: 1600);
  return (jpeg: photo.jpeg, report: analyzeDrawingSync(photo.jpeg));
}

Character characterFrom(
  DrawingAnalysisResult r, {
  String id = 'c_video',
  String name = 'ぐるぐるまる',
  int level = 3,
}) => Character(
  id: id,
  name: name,
  imagePath: 'memory://$id.png',
  imageHash: r.imageHash,
  element: r.element,
  baseStats: r.baseStats,
  energy: r.energy,
  skill: r.skill,
  features: r.features,
  createdAt: DateTime.utc(2026, 10, 10),
  level: level,
);

/// Full pipeline: synthetic photo → analysis → Before photo → content.
Future<VideoComposer> sampleComposer({
  int seed = 1,
  bool withBefore = true,
  String name = 'ぐるぐるまる',
  int level = 3,
}) async {
  final shot = photographedKidDrawing(seed: seed);
  BeforePhoto? before;
  if (withBefore) {
    before = extractBeforePhotoSync(
      shot.jpeg,
      BeforePhotoInput.fromReport(shot.report),
    );
  }
  final content = await loadVideoContent(
    character: characterFrom(shot.report.result, name: name, level: level),
    displayPng: shot.report.result.cutoutPng,
    before: before,
    spec: testSpec,
    roster: testRoster,
    loadAsset: readAssetFile,
  );
  return VideoComposer(content);
}
