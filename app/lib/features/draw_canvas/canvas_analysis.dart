import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/drawing_analysis_result.dart';
import '../drawing_analysis/drawing_analyzer.dart';
import '../drawing_analysis/src/cutout.dart';
import '../drawing_analysis/src/feature_extraction.dart';
import '../drawing_analysis/src/normalize.dart';
import '../drawing_analysis/src/segmentation.dart';
import '../drawing_analysis/src/white_balance.dart';
import '../puppet/rig/character_rig.dart';
import '../puppet/rig/limb_hints.dart';
import 'stroke_drawing.dart';

/// Where canvas units land in the cut-out PNG: cutout = units·[scale] −
/// ([dx], [dy]).
class CutoutMapping {
  const CutoutMapping(this.scale, this.dx, this.dy);
  final double scale, dx, dy;

  P2 map(double x, double y) => P2(x * scale - dx, y * scale - dy);

  Map<String, Object?> toJson() => {'k': scale, 'dx': dx, 'dy': dy};
  static CutoutMapping? fromJson(Object? j) {
    if (j is! Map) return null;
    final k = j['k'], dx = j['dx'], dy = j['dy'];
    if (k is! num || dx is! num || dy is! num) return null;
    return CutoutMapping(k.toDouble(), dx.toDouble(), dy.toDouble());
  }
}

/// Result of analysing an in-app drawing.
class CanvasAnalysis {
  const CanvasAnalysis({
    required this.result,
    required this.rejectReason,
    required this.mapping,
  });

  final DrawingAnalysisResult result;

  /// Only [DrawingRejectReason.nearlyEmpty] can happen here.
  final DrawingRejectReason? rejectReason;

  /// Canvas units → cut-out pixels (for the stroke list).
  final CutoutMapping mapping;
}

Future<CanvasAnalysis> analyzeCanvasDrawing(Uint8List png) =>
    Isolate.run(() => analyzeCanvasDrawingSync(png));

/// The photo pipeline (docs/SPEC.md §3) for a drawing made in the app,
/// skipping only what does not apply (docs/PUPPET.md §4):
///
/// * **paper detection / perspective warp** — the canvas *is* the paper
///   (paper likeness is reported as 1, "detected"),
/// * **authenticity** (printed / screen / photo / digital checks,
///   TRUST.md §3) — the picture provably comes from the child's finger on
///   our canvas (no import, no paste), and its flat digital pixels would
///   otherwise read as "digital art".
///
/// Everything else is identical: normalisation and the image hash, white
/// balance, segmentation, the cut-out, the features, のびのび度 /
/// 子どもの絵らしさ, element and stats, and the "nearly empty" check.
CanvasAnalysis analyzeCanvasDrawingSync(Uint8List png) {
  final norm = normalizeImage(png);
  final wb = whiteBalance(norm.working);
  final seg = segment(wb.image);
  final features = extractFeatures(
    wb.image,
    seg,
    paperLike: 1,
    paperDetected: true,
  );
  final cutout = encodeCutout(wb.image, seg.alpha);
  final energy = computeEnergy(features);
  final skill = computeSkill(features);
  // Same crop as encodeCutout (alpha bounding box + 4 px margin).
  final w = wb.image.width, h = wb.image.height;
  var minX = w, minY = h;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (seg.alpha[y * w + x] == 0) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
    }
  }
  minX = minX >= w ? 0 : math.max(0, minX - 4);
  minY = minY >= h ? 0 : math.max(0, minY - 4);
  // The PNG was rendered at 1024 px on the long side (height); normalize
  // scales it to kWorkingSize.
  final k = norm.working.height / StrokeDrawing.height;
  return CanvasAnalysis(
    result: DrawingAnalysisResult(
      cutoutPng: cutout,
      imageHash: norm.hash,
      features: features.toMap(),
      energy: energy,
      skill: skill,
      element: computeElement(features),
      baseStats: computeBaseStats(features, energy, skill),
    ),
    rejectReason: rejectReasonFor(features),
    mapping: CutoutMapping(k, minX.toDouble(), minY.toDouble()),
  );
}

/// The stroke list in cut-out pixels, as the auto-rigger wants it.
/// Eraser strokes are dropped (they only remove ink).
List<HintStroke> hintStrokesOf(StrokeDrawing d, CutoutMapping m) => [
  for (final s in d.strokes)
    if (!s.isEraser && s.length >= 2)
      HintStroke([
        for (var i = 0; i < s.xy.length; i += 2) m.map(s.xy[i], s.xy[i + 1]),
      ], s.width * m.scale),
];

/// What is stored per character: the strokes plus their mapping.
String strokesRecordJson(StrokeDrawing d, CutoutMapping m) =>
    jsonEncode(d.toJson()..['map'] = m.toJson());

/// Decodes a stored record into rigger strokes (null when absent / bad).
List<HintStroke>? hintStrokesFromRecord(String? json) {
  if (json == null) return null;
  try {
    final j = jsonDecode(json);
    if (j is! Map) return null;
    final m = CutoutMapping.fromJson(j['map']);
    if (m == null) return null;
    return hintStrokesOf(StrokeDrawing.fromJson(j.cast<String, Object?>()), m);
  } on Object {
    return null;
  }
}
