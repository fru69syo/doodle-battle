/// Tiny deterministic rasteriser for synthetic drawings.
///
/// Used by the Vision tests (synthetic kid scribbles, polished line art,
/// photographed paper) and by `tool/gen_cpu_doodles.dart`. Everything is
/// seeded, so outputs are bit-for-bit reproducible.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:doodle_battle/features/drawing_analysis/src/paper_detection.dart';
import 'package:doodle_battle/features/drawing_analysis/src/raster.dart';
import 'package:image/image.dart' as img;

export 'package:doodle_battle/features/drawing_analysis/src/raster.dart'
    show Pt;

/// Colour with 0..255 channels.
class Rgb {
  const Rgb(this.r, this.g, this.b);
  final double r, g, b;

  Rgb lerp(Rgb o, double t) =>
      Rgb(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t);

  static const white = Rgb(255, 255, 255);
  static const black = Rgb(25, 25, 30);
}

/// Common crayon colours.
abstract final class Crayon {
  static const red = Rgb(220, 40, 35);
  static const orange = Rgb(245, 140, 30);
  static const yellow = Rgb(250, 215, 30);
  static const green = Rgb(40, 165, 60);
  static const blue = Rgb(35, 90, 210);
  static const sky = Rgb(60, 170, 235);
  static const purple = Rgb(130, 60, 180);
  static const pink = Rgb(240, 110, 170);
  static const brown = Rgb(130, 80, 40);
  static const black = Rgb(30, 30, 35);
  static const grey = Rgb(120, 120, 125);
}

/// Integer hash → [0, 1).
double hashNoise(int x, int y, int seed) {
  var h = x * 374761393 + y * 668265263 + seed * 2147483647;
  h = (h ^ (h >> 13)) * 1274126177;
  h = h ^ (h >> 16);
  return (h & 0xffffff) / 0x1000000;
}

/// Float RGB canvas that also records where ink was laid down.
class DoodleCanvas {
  DoodleCanvas(this.width, this.height, {Rgb paper = Rgb.white, this.seed = 1})
    : r = Float32List(width * height)..fillRange(0, width * height, paper.r),
      g = Float32List(width * height)..fillRange(0, width * height, paper.g),
      b = Float32List(width * height)..fillRange(0, width * height, paper.b),
      cover = Float32List(width * height);

  final int width;
  final int height;
  final int seed;
  final Float32List r, g, b;

  /// Max ink coverage per pixel (ground truth for segmentation tests).
  final Float32List cover;

  int _strokeCount = 0;

  void _composite(int i, Rgb c, double a) {
    if (a <= 0) return;
    r[i] += (c.r - r[i]) * a;
    g[i] += (c.g - g[i]) * a;
    b[i] += (c.b - b[i]) * a;
    if (a > cover[i]) cover[i] = a;
  }

  /// Crayon grain: paper texture pokes through as speckles.
  double _grain(int x, int y, double texture, int strokeSeed) {
    if (texture <= 0) return 1;
    final n = hashNoise(x, y, seed);
    final streak = hashNoise(x ~/ 3, y, seed + strokeSeed);
    if (n < texture * 0.55) return 0.15 + 0.3 * streak;
    return 0.75 + 0.25 * streak;
  }

  /// Draws a polyline with round caps. [texture] in 0..1 adds crayon grain.
  void stroke(
    List<Pt> pts,
    double radius,
    Rgb color, {
    double texture = 0,
    bool closed = false,
    double opacity = 1,
  }) {
    if (pts.isEmpty) return;
    final path = closed ? [...pts, pts.first] : pts;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in path) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final pad = radius + 2;
    final x0 = math.max(0, (minX - pad).floor());
    final y0 = math.max(0, (minY - pad).floor());
    final x1 = math.min(width - 1, (maxX + pad).ceil());
    final y1 = math.min(height - 1, (maxY + pad).ceil());
    if (x1 < x0 || y1 < y0) return;
    final bw = x1 - x0 + 1;
    final cov = Float32List(bw * (y1 - y0 + 1));
    void segment(Pt a, Pt c) {
      final sx0 = math.max(x0, (math.min(a.x, c.x) - pad).floor());
      final sy0 = math.max(y0, (math.min(a.y, c.y) - pad).floor());
      final sx1 = math.min(x1, (math.max(a.x, c.x) + pad).ceil());
      final sy1 = math.min(y1, (math.max(a.y, c.y) + pad).ceil());
      final dx = c.x - a.x, dy = c.y - a.y;
      final len2 = dx * dx + dy * dy;
      for (var y = sy0; y <= sy1; y++) {
        for (var x = sx0; x <= sx1; x++) {
          final px = x - a.x, py = y - a.y;
          var t = len2 == 0 ? 0.0 : (px * dx + py * dy) / len2;
          t = t.clamp(0.0, 1.0);
          final ex = px - t * dx, ey = py - t * dy;
          final dist = math.sqrt(ex * ex + ey * ey);
          final v = (radius + 0.5 - dist).clamp(0.0, 1.0);
          final k = (y - y0) * bw + (x - x0);
          if (v > cov[k]) cov[k] = v;
        }
      }
    }

    if (path.length == 1) {
      segment(path.first, path.first);
    }
    for (var i = 0; i + 1 < path.length; i++) {
      segment(path[i], path[i + 1]);
    }
    final strokeSeed = ++_strokeCount * 7919;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final c = cov[(y - y0) * bw + (x - x0)];
        if (c <= 0) continue;
        _composite(
          y * width + x,
          color,
          c * opacity * _grain(x, y, texture, strokeSeed),
        );
      }
    }
  }

  void dot(Pt c, double radius, Rgb color, {double texture = 0}) =>
      stroke([c], radius, color, texture: texture);

  /// Even-odd scanline fill; [colorAt] allows gradients.
  void fillPolygon(
    List<Pt> poly,
    Rgb Function(double x, double y) colorAt, {
    double texture = 0,
  }) {
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in poly) {
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final strokeSeed = ++_strokeCount * 7919;
    for (
      var y = math.max(0, minY.floor());
      y <= math.min(height - 1, maxY.ceil());
      y++
    ) {
      final sy = y + 0.5;
      final xs = <double>[];
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i];
        final c = poly[(i + 1) % poly.length];
        if ((a.y <= sy && c.y > sy) || (c.y <= sy && a.y > sy)) {
          xs.add(a.x + (sy - a.y) / (c.y - a.y) * (c.x - a.x));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        final xa = math.max(0, xs[k].round());
        final xb = math.min(width - 1, xs[k + 1].round() - 1);
        for (var x = xa; x <= xb; x++) {
          _composite(
            y * width + x,
            colorAt(x + 0.5, sy),
            _grain(x, y, texture, strokeSeed),
          );
        }
      }
    }
  }

  void fillSolid(List<Pt> poly, Rgb color, {double texture = 0}) =>
      fillPolygon(poly, (_, _) => color, texture: texture);

  /// Kid-style colouring-in: zig-zag crayon strokes clipped to [poly].
  void scribbleFill(
    List<Pt> poly,
    Rgb color,
    math.Random rng, {
    double radius = 5,
    double spacing = 7,
    double texture = 0.5,
  }) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in poly) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    final run = <Pt>[];
    void flush() {
      if (run.length > 1) stroke(List.of(run), radius, color, texture: texture);
      run.clear();
    }

    var up = true;
    for (var x = minX; x <= maxX; x += spacing) {
      final y0 = up ? minY : maxY;
      final y1 = up ? maxY : minY;
      final steps = ((maxY - minY) / 3).ceil();
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final p = Pt(
          x + spacing * t + (rng.nextDouble() - 0.5) * 3,
          y0 + (y1 - y0) * t,
        );
        if (pointInPolygon(p, poly)) {
          run.add(p);
        } else {
          flush();
        }
      }
      flush();
      up = !up;
    }
  }

  img.Image toImage() {
    final out = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        out.setPixelRgb(
          x,
          y,
          r[i].round().clamp(0, 255),
          g[i].round().clamp(0, 255),
          b[i].round().clamp(0, 255),
        );
      }
    }
    return out;
  }

  /// Ink coverage > 0.35 as a 0/1 mask.
  Uint8List inkMask() {
    final m = Uint8List(width * height);
    for (var i = 0; i < m.length; i++) {
      m[i] = cover[i] > 0.35 ? 1 : 0;
    }
    return m;
  }

  Uint8List encodePng() => img.encodePng(toImage());
}

bool pointInPolygon(Pt p, List<Pt> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.y > p.y) != (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}

/// Ellipse outline; [wobble] adds smooth low-frequency radial jitter
/// (fraction of the radius) like an unsteady hand.
List<Pt> ellipse(
  double cx,
  double cy,
  double rx,
  double ry, {
  int n = 72,
  double wobble = 0,
  math.Random? rng,
  double start = 0,
}) {
  final phases = [
    for (var k = 0; k < 4; k++) (rng?.nextDouble() ?? 0) * 2 * math.pi,
  ];
  final amps = [for (var k = 0; k < 4; k++) (rng?.nextDouble() ?? 0)];
  return [
    for (var i = 0; i < n; i++)
      () {
        final a = start + 2 * math.pi * i / n;
        var f = 1.0;
        for (var k = 0; k < 4; k++) {
          f += wobble * amps[k] * math.sin((k + 2) * a + phases[k]) / (k + 1);
        }
        return Pt(cx + rx * f * math.cos(a), cy + ry * f * math.sin(a));
      }(),
  ];
}

/// Star / spiky outline.
List<Pt> star(
  double cx,
  double cy,
  double rOuter,
  double rInner,
  int points, {
  double rotation = -math.pi / 2,
  double jitter = 0,
  math.Random? rng,
}) {
  return [
    for (var i = 0; i < points * 2; i++)
      () {
        final a = rotation + math.pi * i / points;
        final r0 = i.isEven ? rOuter : rInner;
        final r = r0 * (1 + jitter * ((rng?.nextDouble() ?? 0.5) - 0.5));
        return Pt(cx + r * math.cos(a), cy + r * math.sin(a));
      }(),
  ];
}

/// Adds hand tremor: per-point jitter smoothed along the path.
List<Pt> tremble(
  List<Pt> pts,
  double amplitude,
  math.Random rng, {
  int smooth = 2,
}) {
  final raw = [
    for (final _ in pts)
      Pt((rng.nextDouble() - 0.5) * 2, (rng.nextDouble() - 0.5) * 2),
  ];
  return [
    for (var i = 0; i < pts.length; i++)
      () {
        var sx = 0.0, sy = 0.0;
        var c = 0;
        for (var k = -smooth; k <= smooth; k++) {
          final j = i + k;
          if (j < 0 || j >= pts.length) continue;
          sx += raw[j].x;
          sy += raw[j].y;
          c++;
        }
        return Pt(pts[i].x + amplitude * sx / c, pts[i].y + amplitude * sy / c);
      }(),
  ];
}

/// Subdivides a polyline so consecutive points are at most [step] apart.
List<Pt> densify(List<Pt> pts, double step, {bool closed = false}) {
  final path = closed ? [...pts, pts.first] : pts;
  final out = <Pt>[];
  for (var i = 0; i + 1 < path.length; i++) {
    final a = path[i], b = path[i + 1];
    final n = math.max(1, (a.distanceTo(b) / step).ceil());
    for (var k = 0; k < n; k++) {
      out.add(a + (b - a) * (k / n));
    }
  }
  if (!closed) out.add(path.last);
  return out;
}

/// Places [paper] in a camera frame: the paper's corners land on
/// [corners] (TL, TR, BR, BL), the rest is a textured table. Lighting falls
/// off by [lightFalloff] across the frame and sensor [noise] (0..255 std) is
/// added. Returns the rendered photo.
img.Image photograph(
  DoodleCanvas paper, {
  required int width,
  required int height,
  required List<Pt> corners,
  Rgb table = const Rgb(105, 80, 60),
  double lightFalloff = 0.25,
  double noise = 3,
  int seed = 7,
}) {
  final h = SquareToQuad(
    PaperQuad(corners[0], corners[1], corners[2], corners[3]),
  );
  // Invert [a b c; d e f; g h 1].
  final m = [h.a, h.b, h.c, h.d, h.e, h.f, h.g, h.h, 1.0];
  final inv = _invert3(m);
  final rng = math.Random(seed);
  final out = img.Image(width: width, height: height);
  final paperRgb = RgbImage(paper.width, paper.height);
  for (var i = 0; i < paper.width * paper.height; i++) {
    paperRgb.data[i * 3] = paper.r[i].round().clamp(0, 255);
    paperRgb.data[i * 3 + 1] = paper.g[i].round().clamp(0, 255);
    paperRgb.data[i * 3 + 2] = paper.b[i].round().clamp(0, 255);
  }
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final z = inv[6] * x + inv[7] * y + inv[8];
      final u = (inv[0] * x + inv[1] * y + inv[2]) / z;
      final v = (inv[3] * x + inv[4] * y + inv[5]) / z;
      double cr, cg, cb;
      if (u >= 0 && u <= 1 && v >= 0 && v <= 1) {
        final px = u * paper.width - 0.5;
        final py = v * paper.height - 0.5;
        cr = paperRgb.sample(px, py, 0);
        cg = paperRgb.sample(px, py, 1);
        cb = paperRgb.sample(px, py, 2);
      } else {
        final grain = 0.85 + 0.15 * math.sin(y * 0.15 + 3 * math.sin(x * 0.01));
        cr = table.r * grain;
        cg = table.g * grain;
        cb = table.b * grain;
      }
      final light = 1 - lightFalloff * (x / width * 0.7 + y / height * 0.3);
      double n() =>
          noise *
          (rng.nextDouble() + rng.nextDouble() + rng.nextDouble() - 1.5);
      out.setPixelRgb(
        x,
        y,
        (cr * light + n()).round().clamp(0, 255),
        (cg * light * 0.98 + n()).round().clamp(0, 255),
        (cb * light * 0.93 + n()).round().clamp(0, 255),
      );
    }
  }
  return out;
}

List<double> _invert3(List<double> m) {
  final a = m[0], b = m[1], c = m[2];
  final d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  return [
    (e * i - f * h) / det,
    (c * h - b * i) / det,
    (b * f - c * e) / det,
    (f * g - d * i) / det,
    (a * i - c * g) / det,
    (c * d - a * f) / det,
    (d * h - e * g) / det,
    (b * g - a * h) / det,
    (a * e - b * d) / det,
  ];
}
