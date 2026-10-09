import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../ar_effects.dart';

/// Raster work for the paper standee: turns the cut-out drawing into the
/// textures used by the GLB (and by the かんたん AR fallback).
///
/// Everything here is pure Dart (package:image) so it runs in an isolate and
/// in unit tests.
class StandeeTextures {
  StandeeTextures._({
    required this.front,
    required this.back,
    required this.aura,
    required this.auraMarginPx,
    required this.auraScale,
    required this.borderPx,
  });

  /// Builds the textures from a decoded RGBA cut-out.
  ///
  /// * [maxTextureSize]: longest side of the front/back textures, including
  ///   the paper border.
  /// * [borderFraction]: width of the white paper margin around the drawing,
  ///   relative to the drawing's longest side.
  factory StandeeTextures.fromCutout(
    img.Image cutout, {
    int maxTextureSize = 512,
    double borderFraction = 0.035,
    ArEffects effects = ArEffects.none,
    int maxAuraTextureSize = 256,
  }) {
    var src = cutout.convert(numChannels: 4, format: img.Format.uint8);
    src = _cropToContent(src);

    final longest = math.max(src.width, src.height);
    var border = math.max(2, (longest * borderFraction).round());
    final fit = maxTextureSize / (longest + 2 * border);
    if (fit < 1) {
      border = math.max(2, (border * fit).round());
      final s = (maxTextureSize - 2 * border) / longest;
      final w = math.max(1, (src.width * s).floor());
      final h = math.max(1, (src.height * s).floor());
      src = img.copyResize(
        src,
        width: w,
        height: h,
        interpolation: img.Interpolation.average,
      );
    }

    final w = src.width + 2 * border;
    final h = src.height + 2 * border;
    final srcBytes = src.getBytes(order: img.ChannelOrder.rgba);

    // Foreground mask on the padded canvas.
    final mask = Uint8List(w * h);
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        if (srcBytes[(y * src.width + x) * 4 + 3] >= _alphaThreshold) {
          mask[(y + border) * w + (x + border)] = 1;
        }
      }
    }
    final dist2 = squaredDistanceTransform(mask, w, h);
    final border2 = border * border;

    final front = Uint8List(w * h * 4);
    final back = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        final o = i * 4;
        final inside = dist2[i] <= border2;
        // Drawing composited over white paper.
        var r = _paper[0], g = _paper[1], b = _paper[2];
        final sx = x - border, sy = y - border;
        if (sx >= 0 && sy >= 0 && sx < src.width && sy < src.height) {
          final s = (sy * src.width + sx) * 4;
          final a = srcBytes[s + 3] / 255.0;
          r = (srcBytes[s] * a + r * (1 - a)).round();
          g = (srcBytes[s + 1] * a + g * (1 - a)).round();
          b = (srcBytes[s + 2] * a + b * (1 - a)).round();
        }
        // Transparent texels keep the paper colour so linear filtering does
        // not bleed a dark fringe into the cut edge.
        front[o] = r;
        front[o + 1] = g;
        front[o + 2] = b;
        front[o + 3] = inside ? 255 : 0;
        // Back of the paper: off-white with the drawing faintly showing
        // through (it appears mirrored when seen from behind, like real paper).
        back[o] = (_paperBack[0] * 0.86 + r * 0.14).round();
        back[o + 1] = (_paperBack[1] * 0.86 + g * 0.14).round();
        back[o + 2] = (_paperBack[2] * 0.86 + b * 0.14).round();
        back[o + 3] = inside ? 255 : 0;
      }
    }

    img.Image? aura;
    var auraMargin = 0;
    var auraScale = 1.0;
    if (effects.aura) {
      auraMargin = standeeEffectMarginPx(w, h);
      final aw = w + 2 * auraMargin;
      final ah = h + auraMargin; // no margin below the feet
      auraScale = math.min(1.0, maxAuraTextureSize / math.max(aw, ah));
      aura = _buildAura(
        dist2: dist2,
        border2: border2,
        w: w,
        h: h,
        margin: auraMargin,
        scale: auraScale,
        effects: effects,
      );
    }

    return StandeeTextures._(
      front: img.Image.fromBytes(
        width: w,
        height: h,
        bytes: front.buffer,
        numChannels: 4,
      ),
      back: img.Image.fromBytes(
        width: w,
        height: h,
        bytes: back.buffer,
        numChannels: 4,
      ),
      aura: aura,
      auraMarginPx: auraMargin,
      auraScale: auraScale,
      borderPx: border,
    );
  }

  static const _alphaThreshold = 128;
  static const _paper = [255, 254, 250];
  static const _paperBack = [238, 234, 226];

  /// Drawing on white paper with a white margin; alpha is binary (0/255).
  final img.Image front;

  /// Back of the paper, same silhouette as [front].
  final img.Image back;

  /// Soft glow around the silhouette, or null when no aura is requested.
  /// Covers the [front] canvas plus [auraMarginPx] on the left, right and
  /// top (in front-texture pixels), downscaled by [auraScale].
  final img.Image? aura;
  final int auraMarginPx;
  final double auraScale;

  /// Paper margin in front-texture pixels.
  final int borderPx;

  int get width => front.width;
  int get height => front.height;

  static img.Image _cropToContent(img.Image src) {
    final bytes = src.getBytes(order: img.ChannelOrder.rgba);
    var minX = src.width, minY = src.height, maxX = -1, maxY = -1;
    for (var y = 0; y < src.height; y++) {
      for (var x = 0; x < src.width; x++) {
        if (bytes[(y * src.width + x) * 4 + 3] >= _alphaThreshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) {
      // Nothing opaque (e.g. a fully transparent PNG): treat the whole image
      // as the drawing so AR still shows something.
      final out = src.clone();
      for (final p in out) {
        p.a = 255;
      }
      return out;
    }
    return img.copyCrop(
      src,
      x: minX,
      y: minY,
      width: maxX - minX + 1,
      height: maxY - minY + 1,
    );
  }

  static img.Image _buildAura({
    required Float64List dist2,
    required int border2,
    required int w,
    required int h,
    required int margin,
    required double scale,
    required ArEffects effects,
  }) {
    final aw = ((w + 2 * margin) * scale).round().clamp(1, 1 << 14);
    final ah = ((h + margin) * scale).round().clamp(1, 1 << 14);
    // Paper silhouette resampled onto the aura canvas.
    final mask = Uint8List(aw * ah);
    for (var y = 0; y < ah; y++) {
      final fy = (y + 0.5) / scale - margin;
      final py = fy.floor();
      if (py < 0 || py >= h) continue;
      for (var x = 0; x < aw; x++) {
        final px = ((x + 0.5) / scale - margin).floor();
        if (px < 0 || px >= w) continue;
        if (dist2[py * w + px] <= border2) mask[y * aw + x] = 1;
      }
    }
    final d2 = squaredDistanceTransform(mask, aw, ah);
    final reach = margin * scale;
    final out = Uint8List(aw * ah * 4);
    final base = effects.auraColor;
    for (var y = 0; y < ah; y++) {
      final ArColor c;
      if (effects.rainbowAura) {
        c = _hueToColor(1 - y / ah);
      } else {
        c = base;
      }
      for (var x = 0; x < aw; x++) {
        final i = y * aw + x;
        final d = math.sqrt(d2[i]);
        final t = (1 - d / reach).clamp(0.0, 1.0);
        final a = (t * t * 0.85 * 255).round();
        final o = i * 4;
        out[o] = c.r;
        out[o + 1] = c.g;
        out[o + 2] = c.b;
        out[o + 3] = a;
      }
    }
    return img.Image.fromBytes(
      width: aw,
      height: ah,
      bytes: out.buffer,
      numChannels: 4,
    );
  }

  static ArColor _hueToColor(double hue01) {
    final h = (hue01 % 1) * 6;
    final x = 1 - (h % 2 - 1).abs();
    final (r, g, b) = switch (h.floor()) {
      0 => (1.0, x, 0.0),
      1 => (x, 1.0, 0.0),
      2 => (0.0, 1.0, x),
      3 => (0.0, x, 1.0),
      4 => (x, 0.0, 1.0),
      _ => (1.0, 0.0, x),
    };
    // Pastel: mix with white.
    int ch(double v) => (255 * (0.35 + 0.65 * v)).round();
    return ArColor(ch(r), ch(g), ch(b));
  }
}

/// Room around the paper (left, right, top; in front-texture pixels) used by
/// the aura glow and the sparkles.
int standeeEffectMarginPx(int width, int height) =>
    (math.max(width, height) * 0.18).round();

/// 4-point sparkle star used for the densetsu (Lv20+) effect.
img.Image buildSparkleTexture({int size = 64}) {
  final out = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final u = (x + 0.5) / size * 2 - 1;
      final v = (y + 0.5) / size * 2 - 1;
      final r2 = u * u + v * v;
      final core = math.exp(-r2 * 14);
      final rays =
          math.exp(-u.abs() * 22) * math.max(0.0, 1 - v.abs()) +
          math.exp(-v.abs() * 22) * math.max(0.0, 1 - u.abs());
      final a = (core + rays).clamp(0.0, 1.0);
      final o = (y * size + x) * 4;
      // White core fading to warm gold.
      final warm = (1 - core).clamp(0.0, 1.0);
      out[o] = 255;
      out[o + 1] = (255 - 30 * warm).round();
      out[o + 2] = (255 - 140 * warm).round();
      out[o + 3] = (a * 255).round();
    }
  }
  return img.Image.fromBytes(
    width: size,
    height: size,
    bytes: out.buffer,
    numChannels: 4,
  );
}

/// Exact squared Euclidean distance transform (Felzenszwalb & Huttenlocher).
///
/// [mask] is row-major `w*h`, non-zero for foreground. Returns, for every
/// pixel, the squared distance (in pixels) to the nearest foreground pixel.
/// When there is no foreground at all every value is `double.infinity`.
Float64List squaredDistanceTransform(Uint8List mask, int w, int h) {
  const inf = 1e20;
  final grid = Float64List(w * h);
  for (var i = 0; i < grid.length; i++) {
    grid[i] = mask[i] != 0 ? 0 : inf;
  }
  final n = math.max(w, h);
  final f = Float64List(n);
  final d = Float64List(n);
  final v = Int32List(n);
  final z = Float64List(n + 1);

  void transform1d(int len) {
    var k = 0;
    v[0] = 0;
    z[0] = -inf;
    z[1] = inf;
    for (var q = 1; q < len; q++) {
      var s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      while (s <= z[k]) {
        k--;
        s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      }
      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = inf;
    }
    k = 0;
    for (var q = 0; q < len; q++) {
      while (z[k + 1] < q) {
        k++;
      }
      final dq = q - v[k];
      d[q] = dq * dq + f[v[k]];
    }
  }

  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      f[y] = grid[y * w + x];
    }
    transform1d(h);
    for (var y = 0; y < h; y++) {
      grid[y * w + x] = d[y];
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      f[x] = grid[y * w + x];
    }
    transform1d(w);
    for (var x = 0; x < w; x++) {
      grid[y * w + x] = d[x];
    }
  }
  for (var i = 0; i < grid.length; i++) {
    if (grid[i] >= inf) grid[i] = double.infinity;
  }
  return grid;
}
