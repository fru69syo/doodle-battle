import 'dart:math' as math;
import 'dart:typed_data';

import 'morphology.dart';
import 'normalize.dart';
import 'raster.dart';

/// Fraction of the detected paper trimmed from every edge before warping, so
/// that paper borders and their shadows do not become "ink".
const double kPaperInset = 0.015;

/// Corners of the paper in working-image coordinates (clockwise from
/// top-left on screen).
class PaperQuad {
  const PaperQuad(
    this.topLeft,
    this.topRight,
    this.bottomRight,
    this.bottomLeft,
  );
  final Pt topLeft;
  final Pt topRight;
  final Pt bottomRight;
  final Pt bottomLeft;

  List<Pt> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  double get area => polygonArea(corners);
}

/// Outcome of paper detection.
class PaperDetection {
  const PaperDetection({this.quad, required this.paperLike});

  /// Detected sheet, or null to use the full frame.
  final PaperQuad? quad;

  /// 0..1 evidence that the image shows a drawing on paper at all: a bright,
  /// low-saturation, mostly uniform background (either a detected sheet or
  /// paper filling the whole frame). Used by `photoLikelihood`.
  final double paperLike;
}

/// Looks for the largest bright, low-saturation quadrilateral (SPEC §3.1-2).
PaperDetection detectPaper(RgbImage image) {
  final w = image.width;
  final h = image.height;
  final n = w * h;
  final lum = boxBlur(image.luminance(), w, h, 2);

  final hist = List<int>.filled(256, 0);
  for (final v in lum) {
    hist[v]++;
  }
  final t = otsuThreshold(hist);
  final bright = Mask(w, h);
  for (var i = 0; i < n; i++) {
    bright.bits[i] = lum[i] > t ? 1 : 0;
  }
  // Break thin bright bridges between paper and bright table spots.
  final opened = open(bright, 2);
  final labeling = labelComponents(opened);
  Component? best;
  for (final c in labeling.components) {
    if (best == null || c.area > best.area) best = c;
  }
  final whole = _paperLikeness(image, lum, null);
  if (best == null || best.area < 0.15 * n) {
    return PaperDetection(paperLike: whole);
  }
  final sheet = fillHoles(labeling.maskOf((c) => identical(c, best)));
  final sheetArea = sheet.count();

  // Paper fills (almost) the whole frame: no crop needed.
  if (sheetArea > 0.93 * n) {
    return PaperDetection(paperLike: _paperLikeness(image, lum, sheet));
  }

  final paperLike = _paperLikeness(image, lum, sheet);
  var inSum = 0.0, outSum = 0.0;
  var inN = 0, outN = 0;
  for (var i = 0; i < n; i++) {
    if (sheet.bits[i] != 0) {
      inSum += lum[i];
      inN++;
    } else {
      outSum += lum[i];
      outN++;
    }
  }
  final contrast = inSum / inN - outSum / math.max(1, outN);
  if (contrast < 25 || paperLike < 0.5) {
    return PaperDetection(paperLike: whole);
  }

  // A real sheet rarely touches all four borders; a sky band touching three
  // borders is more likely part of a photo.
  final b = sheet.bounds()!;
  final touches =
      (b.left <= 1 ? 1 : 0) +
      (b.top <= 1 ? 1 : 0) +
      (b.right >= w - 2 ? 1 : 0) +
      (b.bottom >= h - 2 ? 1 : 0);
  if (touches >= 3) {
    return PaperDetection(paperLike: whole);
  }

  final contour = toPoints(traceContour(sheet, _firstSet(sheet)));
  final hull = convexHull(contour);
  if (hull.length < 4) return PaperDetection(paperLike: whole);
  final quad = _fitQuad(hull);
  final qa = quad.area;
  if (qa < 0.15 * n || qa / sheetArea < 0.85 || qa / sheetArea > 1.2) {
    return PaperDetection(paperLike: whole);
  }
  if (!_reasonableAngles(quad)) return PaperDetection(paperLike: whole);
  return PaperDetection(quad: quad, paperLike: paperLike);
}

int _firstSet(Mask m) {
  for (var i = 0; i < m.bits.length; i++) {
    if (m.bits[i] != 0) return i;
  }
  return 0;
}

/// Evidence (0..1) that the region (or the whole image when [region] is
/// null) is a sheet of paper: the bright half of it should be neutral and
/// flat.
double _paperLikeness(RgbImage image, Uint8List lum, Mask? region) {
  final n = image.pixelCount;
  final hist = List<int>.filled(256, 0);
  var count = 0;
  for (var i = 0; i < n; i++) {
    if (region != null && region.bits[i] == 0) continue;
    hist[lum[i]]++;
    count++;
  }
  if (count == 0) return 0;
  // 70th percentile as the paper level.
  var acc = 0;
  var p70 = 255;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc >= 0.7 * count) {
      p70 = v;
      break;
    }
  }
  // Among pixels near the paper level, measure chroma and flatness.
  var near = 0;
  var sumR = 0.0, sumG = 0.0, sumB = 0.0;
  var flat = 0;
  final w = image.width;
  final d = image.data;
  for (var i = 0; i < n; i++) {
    if (region != null && region.bits[i] == 0) continue;
    if ((lum[i] - p70).abs() > 12) continue;
    near++;
    sumR += d[i * 3];
    sumG += d[i * 3 + 1];
    sumB += d[i * 3 + 2];
    final x = i % w;
    if (x > 0 && x < w - 1) {
      final gx = (lum[i + 1] - lum[i - 1]).abs();
      if (gx <= 3) flat++;
    }
  }
  if (near == 0) return 0;
  final share = near / count; // paper should dominate its region
  // Saturation of the mean colour: paper is near-neutral even under warm
  // light, a hazy sky is not.
  final mx = math.max(sumR, math.max(sumG, sumB));
  final mn = math.min(sumR, math.min(sumG, sumB));
  final sat = mx <= 0 ? 1.0 : (mx - mn) / mx;
  final flatness = flat / near;
  final brightness = ramp(p70.toDouble(), 90, 170);
  return clamp01(
    brightness *
        (1 - ramp(sat, 0.12, 0.3)) *
        ramp(share, 0.2, 0.45) *
        ramp(flatness, 0.4, 0.75),
  );
}

/// Largest-area quadrilateral with vertices on the convex hull, found by
/// starting from the diagonal extremes and greedily improving each corner.
PaperQuad _fitQuad(List<Pt> hull) {
  int argBest(double Function(Pt p) score) {
    var bi = 0;
    var bs = -double.infinity;
    for (var i = 0; i < hull.length; i++) {
      final s = score(hull[i]);
      if (s > bs) {
        bs = s;
        bi = i;
      }
    }
    return bi;
  }

  final idx = [
    argBest((p) => -p.x - p.y), // top-left
    argBest((p) => p.x - p.y), // top-right
    argBest((p) => p.x + p.y), // bottom-right
    argBest((p) => -p.x + p.y), // bottom-left
  ];
  double areaOf(List<int> ids) => polygonArea([for (final i in ids) hull[i]]);

  final m = hull.length;
  for (var iter = 0; iter < 8; iter++) {
    var changed = false;
    for (var k = 0; k < 4; k++) {
      final prev = idx[(k + 3) % 4];
      final next = idx[(k + 1) % 4];
      var bestI = idx[k];
      var bestA = areaOf(idx);
      // Walk the hull from prev to next (cyclic, in hull order).
      for (var j = (prev + 1) % m; j != next; j = (j + 1) % m) {
        final trial = List.of(idx)..[k] = j;
        final a = areaOf(trial);
        if (a > bestA + 1e-9) {
          bestA = a;
          bestI = j;
        }
      }
      if (bestI != idx[k]) {
        idx[k] = bestI;
        changed = true;
      }
    }
    if (!changed) break;
  }
  final pts = [for (final i in idx) hull[i]];
  // Re-assign roles by diagonal extremes so orientation is canonical.
  Pt pick(double Function(Pt p) score) =>
      pts.reduce((a, b) => score(a) >= score(b) ? a : b);
  return PaperQuad(
    pick((p) => -p.x - p.y),
    pick((p) => p.x - p.y),
    pick((p) => p.x + p.y),
    pick((p) => -p.x + p.y),
  );
}

bool _reasonableAngles(PaperQuad q) {
  final c = q.corners;
  if ({for (final p in c) '${p.x},${p.y}'}.length < 4) return false;
  for (var i = 0; i < 4; i++) {
    final p = c[i];
    final a = c[(i + 3) % 4] - p;
    final b = c[(i + 1) % 4] - p;
    final cos = (a.x * b.x + a.y * b.y) / (a.length * b.length + 1e-9);
    final deg = math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi;
    if (deg < 35 || deg > 145) return false;
  }
  return true;
}

/// Projective mapping from the unit square to a quadrilateral
/// (Heckbert, "Fundamentals of Texture Mapping", 1989).
class SquareToQuad {
  factory SquareToQuad(PaperQuad q) {
    final x0 = q.topLeft.x, y0 = q.topLeft.y;
    final x1 = q.topRight.x, y1 = q.topRight.y;
    final x2 = q.bottomRight.x, y2 = q.bottomRight.y;
    final x3 = q.bottomLeft.x, y3 = q.bottomLeft.y;
    final sx = x0 - x1 + x2 - x3;
    final sy = y0 - y1 + y2 - y3;
    if (sx.abs() < 1e-9 && sy.abs() < 1e-9) {
      return SquareToQuad._(x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0, 0);
    }
    final dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
    final den = dx1 * dy2 - dx2 * dy1;
    final g = (sx * dy2 - dx2 * sy) / den;
    final h = (dx1 * sy - sx * dy1) / den;
    return SquareToQuad._(
      x1 - x0 + g * x1,
      x3 - x0 + h * x3,
      x0,
      y1 - y0 + g * y1,
      y3 - y0 + h * y3,
      y0,
      g,
      h,
    );
  }

  SquareToQuad._(
    this.a,
    this.b,
    this.c,
    this.d,
    this.e,
    this.f,
    this.g,
    this.h,
  );

  final double a, b, c, d, e, f, g, h;

  Pt map(double u, double v) {
    final z = g * u + h * v + 1;
    return Pt((a * u + b * v + c) / z, (d * u + e * v + f) / z);
  }
}

/// Perspective-corrects the sheet into an upright image whose longest side
/// is [kWorkingSize]. Sampling uses the high-resolution copy.
RgbImage warpPaper(
  NormalizedImage src,
  PaperQuad quad, {
  double inset = kPaperInset,
}) {
  final c = quad.corners;
  final top = c[0].distanceTo(c[1]);
  final bottom = c[3].distanceTo(c[2]);
  final left = c[0].distanceTo(c[3]);
  final right = c[1].distanceTo(c[2]);
  final pw = (top + bottom) / 2 * (1 - 2 * inset);
  final ph = (left + right) / 2 * (1 - 2 * inset);
  final s = kWorkingSize / math.max(pw, ph);
  final ow = math.max(8, (pw * s).round());
  final oh = math.max(8, (ph * s).round());
  final map = SquareToQuad(quad);
  final hi = src.hiRes;
  final k = src.hiResScale;
  final out = RgbImage(ow, oh);
  final span = 1 - 2 * inset;
  for (var y = 0; y < oh; y++) {
    final v = inset + span * (y + 0.5) / oh;
    for (var x = 0; x < ow; x++) {
      final u = inset + span * (x + 0.5) / ow;
      final p = map.map(u, v);
      // Working-image pixel centres map to hi-res centres.
      final hx = (p.x + 0.5) * k - 0.5;
      final hy = (p.y + 0.5) * k - 0.5;
      final o = (y * ow + x) * 3;
      for (var ch = 0; ch < 3; ch++) {
        out.data[o + ch] = hi.sample(hx, hy, ch).round().clamp(0, 255);
      }
    }
  }
  return out;
}
