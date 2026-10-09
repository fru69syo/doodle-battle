import 'dart:math' as math;
import 'dart:typed_data';

import 'raster.dart';

/// Chamfer (3-4) distance from every pixel to the nearest pixel whose mask
/// value equals [target]. Units are thirds of a pixel (3 = one step).
///
/// Pixels outside the image are ignored (they never act as seeds), so
/// morphology does not eat into shapes that touch the border.
Int32List chamferDistance(Mask mask, {required int target}) {
  final w = mask.width;
  final h = mask.height;
  const inf = 1 << 28;
  final d = Int32List(w * h);
  final bits = mask.bits;
  for (var i = 0; i < d.length; i++) {
    d[i] = bits[i] == target ? 0 : inf;
  }
  // Forward pass.
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var v = d[i];
      if (v == 0) continue;
      if (x > 0) v = math.min(v, d[i - 1] + 3);
      if (y > 0) {
        v = math.min(v, d[i - w] + 3);
        if (x > 0) v = math.min(v, d[i - w - 1] + 4);
        if (x < w - 1) v = math.min(v, d[i - w + 1] + 4);
      }
      d[i] = v;
    }
  }
  // Backward pass.
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      var v = d[i];
      if (v == 0) continue;
      if (x < w - 1) v = math.min(v, d[i + 1] + 3);
      if (y < h - 1) {
        v = math.min(v, d[i + w] + 3);
        if (x < w - 1) v = math.min(v, d[i + w + 1] + 4);
        if (x > 0) v = math.min(v, d[i + w - 1] + 4);
      }
      d[i] = v;
    }
  }
  return d;
}

/// Dilates [mask] by a (chamfer) disk of [radius] pixels.
Mask dilate(Mask mask, double radius) {
  if (radius <= 0) return mask.copy();
  final d = chamferDistance(mask, target: 1);
  final limit = (radius * 3).round();
  final out = Uint8List(d.length);
  for (var i = 0; i < d.length; i++) {
    out[i] = d[i] <= limit ? 1 : 0;
  }
  return Mask(mask.width, mask.height, out);
}

/// Erodes [mask] by a (chamfer) disk of [radius] pixels.
Mask erode(Mask mask, double radius) {
  if (radius <= 0) return mask.copy();
  final d = chamferDistance(mask, target: 0);
  final limit = (radius * 3).round();
  final out = Uint8List(d.length);
  for (var i = 0; i < d.length; i++) {
    out[i] = d[i] > limit ? 1 : 0;
  }
  return Mask(mask.width, mask.height, out);
}

/// Morphological closing (dilate then erode).
Mask close(Mask mask, double radius) => erode(dilate(mask, radius), radius);

/// Morphological opening (erode then dilate).
Mask open(Mask mask, double radius) => dilate(erode(mask, radius), radius);

/// A connected component of a mask.
class Component {
  Component(this.label);
  final int label;
  int area = 0;
  int minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;

  /// Index of the first pixel in raster order (top-left-most).
  int firstIndex = -1;
  double sumX = 0, sumY = 0;

  int get bboxWidth => maxX - minX + 1;
  int get bboxHeight => maxY - minY + 1;
  double get cx => sumX / area;
  double get cy => sumY / area;
}

/// Connected-component labelling with 8-connectivity.
class Labeling {
  Labeling(this.width, this.height, this.labels, this.components);
  final int width;
  final int height;

  /// 0 = background; component `k` has label `k + 1`.
  final Int32List labels;
  final List<Component> components;

  Mask maskOf(bool Function(Component c) keep) {
    final keepLabel = Uint8List(components.length + 1);
    for (final c in components) {
      if (keep(c)) keepLabel[c.label] = 1;
    }
    final out = Uint8List(labels.length);
    for (var i = 0; i < labels.length; i++) {
      out[i] = keepLabel[labels[i]];
    }
    return Mask(width, height, out);
  }
}

Labeling labelComponents(Mask mask) {
  final w = mask.width;
  final h = mask.height;
  final bits = mask.bits;
  final labels = Int32List(w * h);
  final comps = <Component>[];
  final stack = Int32List(w * h);
  for (var start = 0; start < bits.length; start++) {
    if (bits[start] == 0 || labels[start] != 0) continue;
    final comp = Component(comps.length + 1)..firstIndex = start;
    comps.add(comp);
    var sp = 0;
    stack[sp++] = start;
    labels[start] = comp.label;
    while (sp > 0) {
      final i = stack[--sp];
      final x = i % w;
      final y = i ~/ w;
      comp.area++;
      comp.sumX += x;
      comp.sumY += y;
      if (x < comp.minX) comp.minX = x;
      if (x > comp.maxX) comp.maxX = x;
      if (y < comp.minY) comp.minY = y;
      if (y > comp.maxY) comp.maxY = y;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= w || (dx == 0 && dy == 0)) continue;
          final j = ny * w + nx;
          if (bits[j] != 0 && labels[j] == 0) {
            labels[j] = comp.label;
            stack[sp++] = j;
          }
        }
      }
    }
  }
  return Labeling(w, h, labels, comps);
}

/// Fills every background region that is not 4-connected to the image border.
Mask fillHoles(Mask mask) {
  final w = mask.width;
  final h = mask.height;
  final bits = mask.bits;
  final outside = Uint8List(w * h);
  final stack = Int32List(w * h);
  var sp = 0;
  void seed(int i) {
    if (bits[i] == 0 && outside[i] == 0) {
      outside[i] = 1;
      stack[sp++] = i;
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (sp > 0) {
    final i = stack[--sp];
    final x = i % w;
    final y = i ~/ w;
    if (x > 0) seed(i - 1);
    if (x < w - 1) seed(i + 1);
    if (y > 0) seed(i - w);
    if (y < h - 1) seed(i + w);
  }
  final out = Uint8List(w * h);
  for (var i = 0; i < out.length; i++) {
    out[i] = outside[i] == 1 ? 0 : 1;
  }
  return Mask(w, h, out);
}

// Clockwise (on screen, y down) neighbour order starting at West.
const _dx = [-1, -1, 0, 1, 1, 1, 0, -1];
const _dy = [0, -1, -1, -1, 0, 1, 1, 1];

int _dirOf(int dx, int dy) {
  for (var k = 0; k < 8; k++) {
    if (_dx[k] == dx && _dy[k] == dy) return k;
  }
  return 0;
}

/// Traces the outer boundary of the 8-connected region containing
/// [startIndex], which must be the region's first pixel in raster order.
///
/// Uses Moore-neighbour tracing with Jacob's stopping criterion and returns
/// the ordered boundary pixels as a flat list `[x0, y0, x1, y1, ...]`.
Int32List traceContour(
  Mask mask,
  int startIndex, {
  int? labelValue,
  Int32List? labels,
}) {
  final w = mask.width;
  final h = mask.height;
  bool inside(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    final i = y * w + x;
    if (labels != null) return labels[i] == labelValue;
    return mask.bits[i] != 0;
  }

  final sx = startIndex % w;
  final sy = startIndex ~/ w;
  final pts = <int>[sx, sy];
  var cx = sx, cy = sy;
  var backDir = 0; // West of the start pixel is background by construction.
  int? secondX, secondY;
  final maxSteps = 4 * w * h + 16;
  for (var step = 0; step < maxSteps; step++) {
    var found = -1;
    for (var k = 1; k <= 8; k++) {
      final d = (backDir + k) % 8;
      if (inside(cx + _dx[d], cy + _dy[d])) {
        found = d;
        break;
      }
    }
    if (found < 0) break; // Isolated pixel.
    final nx = cx + _dx[found];
    final ny = cy + _dy[found];
    if (cx == sx && cy == sy && secondX != null) {
      if (nx == secondX && ny == secondY) break;
    }
    // The last background pixel examined, relative to the new position.
    final bd = (found + 7) % 8;
    final bx = cx + _dx[bd];
    final by = cy + _dy[bd];
    backDir = _dirOf(bx - nx, by - ny);
    cx = nx;
    cy = ny;
    if (secondX == null) {
      secondX = nx;
      secondY = ny;
    }
    pts
      ..add(cx)
      ..add(cy);
  }
  // Drop the closing duplicate of the start pixel.
  if (pts.length > 2 && pts[pts.length - 2] == sx && pts.last == sy) {
    pts.length -= 2;
  }
  return Int32List.fromList(pts);
}

/// Converts a flat `[x0, y0, ...]` list into points.
List<Pt> toPoints(Int32List flat) => [
  for (var i = 0; i + 1 < flat.length; i += 2)
    Pt(flat[i].toDouble(), flat[i + 1].toDouble()),
];

/// Circular moving average of a closed polyline (window = 2*[radius]+1).
List<Pt> smoothClosed(List<Pt> pts, int radius) {
  final n = pts.length;
  if (n < 2 * radius + 1) return pts;
  final out = <Pt>[];
  var sx = 0.0, sy = 0.0;
  for (var k = -radius; k <= radius; k++) {
    final p = pts[(k % n + n) % n];
    sx += p.x;
    sy += p.y;
  }
  final win = 2 * radius + 1;
  for (var i = 0; i < n; i++) {
    out.add(Pt(sx / win, sy / win));
    final add = pts[(i + radius + 1) % n];
    final rem = pts[((i - radius) % n + n) % n];
    sx += add.x - rem.x;
    sy += add.y - rem.y;
  }
  return out;
}

/// Perimeter of a closed polyline.
double closedLength(List<Pt> pts) {
  if (pts.length < 2) return 0;
  var len = 0.0;
  for (var i = 0; i < pts.length; i++) {
    len += pts[i].distanceTo(pts[(i + 1) % pts.length]);
  }
  return len;
}

/// Absolute shoelace area of a closed polygon.
double polygonArea(List<Pt> pts) {
  var a = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final p = pts[i];
    final q = pts[(i + 1) % pts.length];
    a += p.x * q.y - q.x * p.y;
  }
  return a.abs() / 2;
}

/// Convex hull (Andrew's monotone chain). Returns vertices in clockwise
/// order on screen (y down) without repeating the first point.
List<Pt> convexHull(List<Pt> points) {
  if (points.length < 3) return List.of(points);
  final pts = List.of(points)
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  double cross(Pt o, Pt a, Pt b) =>
      (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <Pt>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Pt>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}
