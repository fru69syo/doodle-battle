import 'dart:math' as math;
import 'dart:typed_data';

import '../../ar/glb/standee_textures.dart' show squaredDistanceTransform;

/// A binary image (row-major, 1 = foreground) used by the auto-rigger.
///
/// Pure Dart and allocation-light so the whole rig pipeline can run in an
/// isolate on old phones (Android 7+).
class BinMask {
  BinMask(this.w, this.h) : data = Uint8List(w * h);
  BinMask.from(this.w, this.h, this.data) : assert(data.length == w * h);

  final int w, h;
  final Uint8List data;

  bool at(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && data[y * w + x] != 0;

  int get count {
    var n = 0;
    for (final v in data) {
      if (v != 0) n++;
    }
    return n;
  }

  /// Sub-image `[x0, x1] × [y0, y1]` (inclusive).
  BinMask crop(int x0, int y0, int x1, int y1) {
    final cw = x1 - x0 + 1, chh = y1 - y0 + 1;
    final out = BinMask(cw, chh);
    for (var y = 0; y < chh; y++) {
      out.data.setRange(y * cw, y * cw + cw, data, (y + y0) * w + x0);
    }
    return out;
  }

  BinMask copy() => BinMask.from(w, h, Uint8List.fromList(data));

  /// Bounding box `[minX, minY, maxX, maxY]` or null when empty.
  List<int>? bounds() {
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (data[y * w + x] == 0) continue;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
    return x1 < 0 ? null : [x0, y0, x1, y1];
  }

  /// Mask of an RGBA buffer (alpha >= [threshold]).
  static BinMask fromRgba(Uint8List rgba, int w, int h, {int threshold = 128}) {
    final m = BinMask(w, h);
    for (var i = 0; i < w * h; i++) {
      if (rgba[i * 4 + 3] >= threshold) m.data[i] = 1;
    }
    return m;
  }

  /// Area-coverage downscale by [factor] (>= 1) with a [pad] pixel empty
  /// border. A cell is foreground when at least [minCoverage] of it is.
  /// A low coverage keeps 1–2 px stick-figure lines connected.
  BinMask downscale(double factor, {int pad = 2, double minCoverage = 0.3}) {
    final ow = (w / factor).ceil() + 2 * pad;
    final oh = (h / factor).ceil() + 2 * pad;
    if (factor < 1) {
      // Upscale (tiny drawings): nearest neighbour.
      final out = BinMask(ow, oh);
      for (var y = 0; y < oh - 2 * pad; y++) {
        final sy = math.min(h - 1, (y * factor).floor());
        for (var x = 0; x < ow - 2 * pad; x++) {
          final sx = math.min(w - 1, (x * factor).floor());
          if (data[sy * w + sx] != 0) out.data[(y + pad) * ow + x + pad] = 1;
        }
      }
      return out;
    }
    final acc = Float64List(ow * oh);
    for (var y = 0; y < h; y++) {
      final oy = (y / factor).floor() + pad;
      for (var x = 0; x < w; x++) {
        if (data[y * w + x] == 0) continue;
        acc[oy * ow + (x / factor).floor() + pad] += 1;
      }
    }
    final cell = factor * factor;
    final out = BinMask(ow, oh);
    for (var i = 0; i < acc.length; i++) {
      if (acc[i] >= minCoverage * cell) out.data[i] = 1;
    }
    return out;
  }

  BinMask dilate(int r) => _morph(r, true);
  BinMask erode(int r) => _morph(r, false);
  BinMask close(int r) => dilate(r).erode(r);
  BinMask open(int r) => erode(r).dilate(r);

  /// Square-ish (disc) structuring element of radius [r].
  BinMask _morph(int r, bool grow) {
    if (r <= 0) return copy();
    // Separable passes with a disc approximated by distance transform.
    final src = grow ? data : _inverted();
    final d2 = squaredDistanceTransform(src, w, h);
    final out = BinMask(w, h);
    final rr = r * r + 0.5;
    for (var i = 0; i < data.length; i++) {
      final inside = d2[i] <= rr;
      out.data[i] = grow ? (inside ? 1 : 0) : (inside ? 0 : 1);
    }
    return out;
  }

  Uint8List _inverted() {
    final inv = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      inv[i] = data[i] == 0 ? 1 : 0;
    }
    return inv;
  }

  /// Fills background regions that do not touch the border.
  BinMask fillHoles() {
    final out = copy();
    final seen = Uint8List(w * h);
    final stack = <int>[];
    void push(int i) {
      if (seen[i] == 0 && data[i] == 0) {
        seen[i] = 1;
        stack.add(i);
      }
    }

    for (var x = 0; x < w; x++) {
      push(x);
      push((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      push(y * w);
      push(y * w + w - 1);
    }
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w, y = i ~/ w;
      if (x > 0) push(i - 1);
      if (x < w - 1) push(i + 1);
      if (y > 0) push(i - w);
      if (y < h - 1) push(i + w);
    }
    for (var i = 0; i < w * h; i++) {
      if (data[i] == 0 && seen[i] == 0) out.data[i] = 1;
    }
    return out;
  }

  /// 8-connected component labels (0 = background) and their sizes
  /// (index 0 unused).
  (Int32List, List<int>) labels() {
    final lab = Int32List(w * h);
    final sizes = <int>[0];
    final stack = <int>[];
    for (var s = 0; s < w * h; s++) {
      if (data[s] == 0 || lab[s] != 0) continue;
      final id = sizes.length;
      var n = 0;
      lab[s] = id;
      stack.add(s);
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        n++;
        final x = i % w, y = i ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= w) continue;
            final j = yy * w + xx;
            if (data[j] != 0 && lab[j] == 0) {
              lab[j] = id;
              stack.add(j);
            }
          }
        }
      }
      sizes.add(n);
    }
    return (lab, sizes);
  }

  /// Keeps the largest component, plus components of at least
  /// [keepFraction] of it (kids draw detached bits: a hat, a sword...).
  BinMask largestComponents({double keepFraction = 1.0}) {
    final (lab, sizes) = labels();
    if (sizes.length <= 1) return copy();
    var best = 1;
    for (var i = 2; i < sizes.length; i++) {
      if (sizes[i] > sizes[best]) best = i;
    }
    final out = BinMask(w, h);
    for (var i = 0; i < w * h; i++) {
      final l = lab[i];
      if (l != 0 && (l == best || sizes[l] >= keepFraction * sizes[best])) {
        out.data[i] = 1;
      }
    }
    return out;
  }

  /// Euclidean distance (px) from every foreground pixel to the nearest
  /// background pixel (0 on the background).
  Float64List insideDistance() {
    final d2 = squaredDistanceTransform(_inverted(), w, h);
    final out = Float64List(w * h);
    for (var i = 0; i < w * h; i++) {
      out[i] = data[i] == 0 ? 0 : math.sqrt(d2[i]);
    }
    return out;
  }
}
