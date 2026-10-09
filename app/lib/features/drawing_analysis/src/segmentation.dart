import 'dart:math' as math;
import 'dart:typed_data';

import 'morphology.dart';
import 'raster.dart';

/// Foreground extraction result (SPEC §3.1-3).
class Segmentation {
  Segmentation({
    required this.ink,
    required this.silhouette,
    required this.alpha,
    required this.inkLabels,
    required this.threshold,
  });

  /// Pixels that carry pigment (strokes and coloured areas).
  final Mask ink;

  /// The character's filled shape: ink plus the paper it encloses.
  final Mask silhouette;

  /// Cut-out alpha (0..255): silhouette slightly dilated, soft 1px edge.
  final Uint8List alpha;

  /// Connected components of [ink].
  final Labeling inkLabels;

  /// Adaptive ink threshold that was used (0..1 "distance from paper").
  final double threshold;
}

/// "Distance from paper" of a white-balanced pixel: the larger of darkness
/// and chroma, so light-but-colourful crayon (yellow!) counts as ink.
double inkScore(int r, int g, int b) {
  final l = (r * 77 + g * 150 + b * 29) / (256 * 255);
  final mx = math.max(r, math.max(g, b));
  final mn = math.min(r, math.min(g, b));
  final chroma = (mx - mn) / 255;
  return math.max(1 - l, chroma * 1.1);
}

Segmentation segment(RgbImage image) {
  final w = image.width;
  final h = image.height;
  final n = w * h;
  final d = image.data;

  final score = Uint8List(n);
  final hist = List<int>.filled(256, 0);
  for (var i = 0; i < n; i++) {
    final s = (inkScore(d[i * 3], d[i * 3 + 1], d[i * 3 + 2]) * 255)
        .round()
        .clamp(0, 255);
    score[i] = s;
    hist[s]++;
  }
  // Paper noise level: median + 6 * MAD of the score, measured on the paper
  // side of the Otsu split.
  final otsu = otsuThreshold(hist);
  var paperCount = 0;
  for (var v = 0; v <= otsu; v++) {
    paperCount += hist[v];
  }
  final median = _percentile(hist, 0.5, upTo: otsu, total: paperCount);
  final devHist = List<int>.filled(256, 0);
  for (var v = 0; v <= otsu; v++) {
    devHist[(v - median).abs()] += hist[v];
  }
  final mad = _percentile(devHist, 0.5, total: paperCount);
  final noiseFloor = (median + 6 * mad + 8) / 255;
  final t = math
      .max(noiseFloor, (otsu / 255).clamp(0.13, 0.32))
      .clamp(0.13, 0.45);
  final strong = (t * 255).round();
  final weak = (t * 0.6 * 255).round();

  // Hysteresis: weak pixels are ink only when connected to strong ones.
  final raw = Mask(w, h);
  final stack = Int32List(n);
  var sp = 0;
  for (var i = 0; i < n; i++) {
    if (score[i] >= strong) {
      raw.bits[i] = 1;
      stack[sp++] = i;
    }
  }
  while (sp > 0) {
    final i = stack[--sp];
    final x = i % w;
    final y = i ~/ w;
    for (var dy = -1; dy <= 1; dy++) {
      final ny = y + dy;
      if (ny < 0 || ny >= h) continue;
      for (var dx = -1; dx <= 1; dx++) {
        final nx = x + dx;
        if (nx < 0 || nx >= w) continue;
        final j = ny * w + nx;
        if (raw.bits[j] == 0 && score[j] >= weak) {
          raw.bits[j] = 1;
          stack[sp++] = j;
        }
      }
    }
  }

  // Cleanup: close pinholes (crayon grain), drop specks and border debris.
  final closed = close(raw, 1);
  final labeling = labelComponents(closed);
  final minArea = math.max(10, (0.0002 * n).round());
  final band = math.max(2, (0.03 * math.max(w, h)).round());
  final bandCount = Int32List(labeling.components.length + 1);
  for (var y = 0; y < h; y++) {
    final dyEdge = math.min(y, h - 1 - y);
    for (var x = 0; x < w; x++) {
      final lab = labeling.labels[y * w + x];
      if (lab == 0) continue;
      if (math.min(dyEdge, math.min(x, w - 1 - x)) < band) bandCount[lab]++;
    }
  }
  final ink = labeling.maskOf(
    (c) => c.area >= minArea && bandCount[c.label] < 0.6 * c.area,
  );
  final inkLabels = labelComponents(ink);

  final silhouette = fillHoles(close(ink, 3)).or(ink);
  final grown = dilate(silhouette, 2);
  final outer = dilate(grown, 1);
  final alpha = Uint8List(n);
  for (var i = 0; i < n; i++) {
    alpha[i] = grown.bits[i] == 1 ? 255 : (outer.bits[i] == 1 ? 110 : 0);
  }
  return Segmentation(
    ink: ink,
    silhouette: silhouette,
    alpha: alpha,
    inkLabels: inkLabels,
    threshold: t,
  );
}

int _percentile(List<int> hist, double q, {int upTo = 255, int? total}) {
  final tot = total ?? hist.fold<int>(0, (a, b) => a + b);
  if (tot == 0) return 0;
  var acc = 0;
  for (var v = 0; v <= upTo; v++) {
    acc += hist[v];
    if (acc >= q * tot) return v;
  }
  return upTo;
}
