/// On-device drawing analysis (SPEC §3): photo of a paper drawing →
/// cut-out PNG, features, のびのび度 / じょうずさ, ぞくせい and Lv1 stats.
///
/// Typical use from the UI:
///
/// ```dart
/// final report = await analyzeDrawingDetailed(bytes);
/// if (report.rejectReason != null) {
///   showMessage(report.rejectReason!.message); // もうすこし かいてみよう
/// } else {
///   createCharacter(report.result);
/// }
/// ```
library;

import 'dart:isolate';
import 'dart:typed_data';

import '../../domain/drawing_analysis_result.dart';
import 'drawing_features.dart';
import 'scoring.dart';
import 'src/cutout.dart';
import 'src/feature_extraction.dart';
import 'src/normalize.dart';
import 'src/paper_detection.dart';
import 'src/raster.dart';
import 'src/segmentation.dart';
import 'src/white_balance.dart';
import 'stat_generator.dart';

export 'drawing_features.dart';
export 'scoring.dart';
export 'src/normalize.dart' show UndecodableImageException;
export 'src/paper_detection.dart' show PaperQuad, kPaperInset;
export 'src/raster.dart' show Mask, Pt;
export 'stat_generator.dart';

/// Analyses an encoded image (JPEG/PNG/WebP...) off the UI thread.
///
/// Throws [UndecodableImageException] when [imageBytes] is not an image.
/// Use [rejectReasonOf] (or [analyzeDrawingDetailed]) to find out whether
/// the drawing is too empty to play with.
Future<DrawingAnalysisResult> analyzeDrawing(Uint8List imageBytes) =>
    Isolate.run(() => analyzeDrawingSync(imageBytes).result);

/// Like [analyzeDrawing] but also returns diagnostics.
Future<DrawingAnalysisReport> analyzeDrawingDetailed(Uint8List imageBytes) =>
    Isolate.run(() => analyzeDrawingSync(imageBytes));

/// Synchronous pipeline. Prefer [analyzeDrawing] in the app; this is for
/// tests and tools that already run off the UI thread.
DrawingAnalysisReport analyzeDrawingSync(Uint8List imageBytes) {
  final timings = <String, int>{};
  final sw = Stopwatch()..start();
  void lap(String name) {
    timings[name] = sw.elapsedMilliseconds;
    sw.reset();
  }

  final norm = normalizeImage(imageBytes);
  lap('normalize');
  final paper = detectPaper(norm.working);
  final paperImage = paper.quad == null
      ? norm.working
      : warpPaper(norm, paper.quad!);
  lap('paper');
  final wb = whiteBalance(paperImage);
  lap('whiteBalance');
  final seg = segment(wb.image);
  lap('segment');
  final features = extractFeatures(
    wb.image,
    seg,
    paperLike: paper.paperLike,
    paperDetected: paper.quad != null,
  );
  lap('features');
  final cutout = encodeCutout(wb.image, seg.alpha);
  lap('cutout');

  final energy = computeEnergy(features);
  final skill = computeSkill(features);
  final result = DrawingAnalysisResult(
    cutoutPng: cutout,
    imageHash: norm.hash,
    features: features.toMap(),
    energy: energy,
    skill: skill,
    element: computeElement(features),
    baseStats: computeBaseStats(features, energy, skill),
  );
  return DrawingAnalysisReport(
    result: result,
    features: features,
    rejectReason: rejectReasonFor(features),
    paperQuad: paper.quad,
    silhouette: seg.silhouette,
    timingsMs: timings,
  );
}

/// Pipeline output plus diagnostics.
class DrawingAnalysisReport {
  const DrawingAnalysisReport({
    required this.result,
    required this.features,
    required this.rejectReason,
    required this.paperQuad,
    required this.silhouette,
    required this.timingsMs,
  });

  final DrawingAnalysisResult result;
  final DrawingFeatures features;

  /// Non-null when the child should draw more (e.g. a single dot).
  final DrawingRejectReason? rejectReason;

  /// Detected paper corners in the 512px working image, if any.
  final PaperQuad? paperQuad;

  /// Character mask in the (perspective-corrected) paper image.
  final Mask silhouette;

  /// Milliseconds per pipeline stage.
  final Map<String, int> timingsMs;

  int get totalMs => timingsMs.values.fold(0, (a, b) => a + b);
}

/// Reject reason derived from a result's feature map.
DrawingRejectReason? rejectReasonOf(DrawingAnalysisResult result) =>
    rejectReasonFor(DrawingFeatures.fromMap(result.features));

/// Applies the cloud judge's skill estimate (SPEC §3.3): blends skill
/// 0.6/0.4 and re-derives the Lv1 stats from the same features and energy.
DrawingAnalysisResult applyCloudSkill(
  DrawingAnalysisResult result,
  double cloudSkill,
) {
  final skill = (blendCloudSkill(result.skill, cloudSkill) * 10).round() / 10;
  return DrawingAnalysisResult(
    cutoutPng: result.cutoutPng,
    imageHash: result.imageHash,
    features: result.features,
    energy: result.energy,
    skill: skill,
    element: result.element,
    baseStats: computeBaseStatsFromMap(result.features, result.energy, skill),
  );
}
