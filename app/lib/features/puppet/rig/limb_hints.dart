import 'dart:math' as math;
import 'dart:typed_data';

import 'bin_mask.dart';
import 'character_rig.dart';

/// An elongated part of the drawing that could be a limb even though it
/// does not stick out of the silhouette — typically an arm drawn touching
/// the body (hands on hips, arms along a dress), which the silhouette
/// skeleton can not see. Coordinates are drawing pixels; the two ends are
/// unordered.
class LimbHint {
  const LimbHint(
    this.a,
    this.b, {
    required this.thickness,
    this.fromStroke = false,
    this.mid,
  });

  final P2 a, b;

  /// Bend point (elbow) when known (a bent stroke).
  final P2? mid;

  /// Mean width (px).
  final double thickness;

  /// Came from the drawing tool's stroke list (stronger evidence than the
  /// picture's lines).
  final bool fromStroke;

  double get length => a.dist(b);

  @override
  String toString() => 'LimbHint($a–$b, t=${thickness.toStringAsFixed(1)})';
}

/// One stroke of the in-app drawing tool, in drawing pixels.
class HintStroke {
  const HintStroke(this.points, this.width);
  final List<P2> points;
  final double width;
}

/// Limb hints from the drawing tool's strokes: a long open stroke (a line
/// arm) or a closed elongated outline (a sausage arm) is a limb candidate,
/// even where it overlaps the body.
List<LimbHint> strokeLimbHints(List<HintStroke> strokes, double figureSize) {
  final out = <LimbHint>[];
  for (final s in strokes) {
    final pts = s.points;
    if (pts.length < 2) continue;
    var len = 0.0;
    for (var i = 1; i < pts.length; i++) {
      len += pts[i].dist(pts[i - 1]);
    }
    if (len < 0.12 * figureSize) continue;
    final closed = pts.first.dist(pts.last) < math.max(2 * s.width, 0.12 * len);
    if (!closed) {
      // Lines that bend at most once or twice (an arm with an elbow); a
      // scribble fill turns round and round and is not a limb.
      if (_turning(pts, s.width) > 4.2) continue;
      final chord = pts.first.dist(pts.last);
      if (chord < 0.3 * len) continue;
      // The elbow: the point at half the path length.
      var acc = 0.0;
      var mid = pts.first.lerp(pts.last, 0.5);
      for (var i = 1; i < pts.length; i++) {
        acc += pts[i].dist(pts[i - 1]);
        if (acc >= len / 2) {
          mid = pts[i];
          break;
        }
      }
      out.add(
        LimbHint(
          pts.first,
          pts.last,
          thickness: s.width,
          fromStroke: true,
          mid: mid,
        ),
      );
      continue;
    }
    final pca = _Pca();
    for (final p in pts) {
      pca.add(p.x, p.y);
    }
    final h = pca.hint(perimeter: len, fromStroke: true);
    if (h != null && h.length >= 0.12 * figureSize) out.add(h);
  }
  return out;
}

/// Total absolute turning (radians) of a polyline, measured on points at
/// least a line width apart (hand jitter is ignored).
double _turning(List<P2> pts, double width) {
  final step = math.max(4.0, 1.5 * width);
  final q = <P2>[pts.first];
  for (final p in pts.skip(1)) {
    if (p.dist(q.last) >= step) q.add(p);
  }
  var total = 0.0;
  for (var i = 2; i < q.length; i++) {
    final a1 = math.atan2(q[i - 1].y - q[i - 2].y, q[i - 1].x - q[i - 2].x);
    final a2 = math.atan2(q[i].y - q[i - 1].y, q[i].x - q[i - 1].x);
    var d = (a2 - a1).abs();
    if (d > math.pi) d = 2 * math.pi - d;
    total += d;
  }
  return total;
}

/// Limb hints from the picture itself: regions of the drawing separated by
/// its own drawn lines (darker than their surroundings). An arm outlined
/// against the body is its own region even when the silhouette is solid.
///
/// [rgba] is straight-alpha RGBA of [mask]'s size. Works at ~[workSize] px.
List<LimbHint> inkLimbHints(
  Uint8List rgba,
  BinMask mask, {
  int workSize = 200,
}) {
  final fb = mask.bounds();
  if (fb == null) return const [];
  final fw = fb[2] - fb[0] + 1, fh = fb[3] - fb[1] + 1;
  final s = math.max(1.0, math.max(fw, fh) / workSize);
  final ww = (fw / s).ceil(), wh = (fh / s).ceil();
  final n = ww * wh;
  final lum = Float64List(n), cnt = Float64List(n);
  final chroma = Float64List(n);
  for (var y = fb[1]; y <= fb[3]; y++) {
    final cy = ((y - fb[1]) / s).floor();
    for (var x = fb[0]; x <= fb[2]; x++) {
      final i = y * mask.w + x;
      if (mask.data[i] == 0) continue;
      final c = cy * ww + ((x - fb[0]) / s).floor();
      final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
      lum[c] += (0.3 * r + 0.59 * g + 0.11 * b) / 255;
      chroma[c] +=
          (math.max(r, math.max(g, b)) - math.min(r, math.min(g, b))) / 255;
      cnt[c] += 1;
    }
  }
  final fg = Uint8List(n);
  final cell = s * s;
  for (var i = 0; i < n; i++) {
    if (cnt[i] >= 0.5 * cell) {
      fg[i] = 1;
      lum[i] /= cnt[i];
      chroma[i] /= cnt[i];
    }
  }
  // Ink: clearly darker than the brightest nearby foreground (a line on a
  // lighter area), or simply dark and grey.
  final ink = Uint8List(n);
  const r = 2;
  for (var y = 0; y < wh; y++) {
    for (var x = 0; x < ww; x++) {
      final i = y * ww + x;
      if (fg[i] == 0) continue;
      var mx = lum[i];
      for (var yy = math.max(0, y - r); yy <= math.min(wh - 1, y + r); yy++) {
        for (var xx = math.max(0, x - r); xx <= math.min(ww - 1, x + r); xx++) {
          final j = yy * ww + xx;
          if (fg[j] != 0 && lum[j] > mx) mx = lum[j];
        }
      }
      final l = lum[i];
      if ((l < mx - 0.16 && l < 0.8) || (l < 0.3 && chroma[i] < 0.25)) {
        ink[i] = 1;
      }
    }
  }
  // Regions: 4-connected non-ink foreground.
  final lab = Int32List(n);
  final stack = <int>[];
  var total = 0;
  for (var i = 0; i < n; i++) {
    if (fg[i] != 0) total++;
  }
  final hints = <LimbHint>[];
  var next = 0;
  for (var s0 = 0; s0 < n; s0++) {
    if (fg[s0] == 0 || ink[s0] != 0 || lab[s0] != 0) continue;
    next++;
    final pca = _Pca();
    lab[s0] = next;
    stack.add(s0);
    var touchesEdge = false;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % ww, y = i ~/ ww;
      pca.add(x.toDouble(), y.toDouble());
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= ww || yy >= wh) {
          touchesEdge = true;
          continue;
        }
        final j = yy * ww + xx;
        if (fg[j] == 0) {
          touchesEdge = true;
          continue;
        }
        if (ink[j] != 0 || lab[j] != 0) continue;
        lab[j] = next;
        stack.add(j);
      }
    }
    // Regions open to the outside are coloured areas without an outline
    // (their shape is already in the silhouette); a region must be a real
    // part, not a speck or the whole body.
    if (pca.n < math.max(12, 0.004 * total) || pca.n > 0.22 * total) continue;
    final h = pca.hint();
    if (h == null) continue;
    final minLen = 0.14 * math.max(ww, wh);
    if (h.length < minLen) continue;
    final weight = touchesEdge ? 0.0 : 1.0;
    if (weight == 0) continue;
    P2 d(P2 p) => P2(fb[0] + (p.x + 0.5) * s, fb[1] + (p.y + 0.5) * s);
    hints.add(LimbHint(d(h.a), d(h.b), thickness: h.thickness * s));
  }
  return hints;
}

/// Principal-axis summary of a point set.
class _Pca {
  int n = 0;
  double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
  final _pts = <double>[];

  void add(double x, double y) {
    n++;
    sx += x;
    sy += y;
    sxx += x * x;
    syy += y * y;
    sxy += x * y;
    _pts
      ..add(x)
      ..add(y);
  }

  /// Ends of the main axis (extreme projections) when the set is
  /// elongated (≥ 2.4 : 1), else null. [perimeter] marks an outline (its
  /// points are the boundary, not the area).
  LimbHint? hint({double? perimeter, bool fromStroke = false}) {
    if (n < 3) return null;
    final mx = sx / n, my = sy / n;
    final cxx = sxx / n - mx * mx, cyy = syy / n - my * my;
    final cxy = sxy / n - mx * my;
    final tr = cxx + cyy, det = cxx * cyy - cxy * cxy;
    final disc = math.sqrt(math.max(0, tr * tr / 4 - det));
    final l1 = tr / 2 + disc, l2 = math.max(1e-9, tr / 2 - disc);
    if (l1 / l2 < 2.4 * 2.4) return null;
    final ang = 0.5 * math.atan2(2 * cxy, cxx - cyy);
    final ux = math.cos(ang), uy = math.sin(ang);
    var lo = double.infinity, hi = -double.infinity;
    for (var i = 0; i < _pts.length; i += 2) {
      final p = (_pts[i] - mx) * ux + (_pts[i + 1] - my) * uy;
      if (p < lo) lo = p;
      if (p > hi) hi = p;
    }
    final len = hi - lo;
    final thick = perimeter != null
        ? math.max(1.0, perimeter / 2 - len)
        : n / math.max(1, len);
    if (len < 2.4 * thick) return null;
    // Pull the ends in by half the thickness (joint centres, not edges).
    final a = P2(mx + ux * (lo + thick / 2), my + uy * (lo + thick / 2));
    final b = P2(mx + ux * (hi - thick / 2), my + uy * (hi - thick / 2));
    return LimbHint(a, b, thickness: thick, fromStroke: fromStroke);
  }
}
