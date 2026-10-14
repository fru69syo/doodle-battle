/// Renders the character's display picture: the base drawing plus the drawn
/// parts (pure Dart, safe to run in an isolate). The base drawing itself is
/// never modified, so removing a part restores the original exactly.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:image/image.dart' as img;

import '../../../domain/character_v2.dart';
import '../../../domain/character_v2_view.dart';
import '../../../domain/cosmetics.dart';
import 'part_geometry.dart';

/// One drawn part to place.
class CompositePart {
  const CompositePart(this.png, this.transform);
  final Uint8List png;
  final PartTransform transform;
}

class CompositeRequest {
  const CompositeRequest({
    required this.basePng,
    required this.parts,
    this.stage = EvolutionStage.normal,
    this.glowArgb = 0xFFFFB800,
    this.maxSide = 512,
  });

  final Uint8List basePng;

  /// In drawing order; [PartTransform.behind] parts go under the base.
  final List<CompositePart> parts;

  /// Evolution shows parts more prominently: かがやき adds a glow in the
  /// element colour ([glowArgb]); でんせつ adds a gold glow and draws parts
  /// 15% bigger.
  final EvolutionStage stage;
  final int glowArgb;

  /// Longest side of the output (AR and the analyzer expect ≤ 512).
  final int maxSide;
}

class CompositeImage {
  const CompositeImage({
    required this.png,
    required this.width,
    required this.height,
    required this.baseRect,
  });

  final Uint8List png;
  final int width;
  final int height;

  /// Where the base drawing ended up inside the output (pixels).
  final Rect baseRect;
}

/// Outline (white sticker edge) around every part, in output pixels.
const int partOutlinePx = 2;

/// Glow radius around parts by evolution stage, in output pixels.
int partGlowPx(EvolutionStage s) => switch (s) {
  EvolutionStage.normal => 0,
  EvolutionStage.kagayaki => 5,
  EvolutionStage.densetsu => 7,
};

/// Part size multiplier by evolution stage.
double partScaleBoost(EvolutionStage s) =>
    s == EvolutionStage.densetsu ? 1.15 : 1.0;

const int _gold = 0xFFFFB800;

class _Rgba {
  _Rgba(this.w, this.h, this.px);
  final int w, h;
  final Uint8List px; // straight RGBA

  factory _Rgba.decode(Uint8List png) {
    final d = img.decodePng(png) ?? img.decodeImage(png);
    if (d == null) throw const FormatException('not an image');
    final c = d.convert(numChannels: 4, format: img.Format.uint8);
    return _Rgba(c.width, c.height, c.getBytes(order: img.ChannelOrder.rgba));
  }

  /// Bilinear sample at continuous pixel coords (pixel centres at +0.5),
  /// premultiplied into [out] (r, g, b, a in 0..1).
  void sample(double x, double y, List<double> out) {
    final fx = x - 0.5, fy = y - 0.5;
    final x0 = fx.floor(), y0 = fy.floor();
    final tx = fx - x0, ty = fy - y0;
    var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
    for (var j = 0; j < 2; j++) {
      final yy = y0 + j;
      if (yy < 0 || yy >= h) continue;
      final wy = j == 0 ? 1 - ty : ty;
      for (var i = 0; i < 2; i++) {
        final xx = x0 + i;
        if (xx < 0 || xx >= w) continue;
        final wgt = wy * (i == 0 ? 1 - tx : tx);
        if (wgt == 0) continue;
        final o = (yy * w + xx) * 4;
        final pa = px[o + 3] / 255 * wgt;
        r += px[o] / 255 * pa;
        g += px[o + 1] / 255 * pa;
        b += px[o + 2] / 255 * pa;
        a += pa;
      }
    }
    out[0] = r;
    out[1] = g;
    out[2] = b;
    out[3] = a;
  }
}

/// Renders [r]. Without parts the base PNG is returned unchanged.
CompositeImage renderComposite(CompositeRequest r) {
  final base = _Rgba.decode(r.basePng);
  if (r.parts.isEmpty) {
    return CompositeImage(
      png: r.basePng,
      width: base.w,
      height: base.h,
      baseRect: Rect.fromLTWH(0, 0, base.w.toDouble(), base.h.toDouble()),
    );
  }
  final boost = partScaleBoost(r.stage);
  final glow = partGlowPx(r.stage);
  final halo = partOutlinePx + glow;
  final glowColor = r.stage == EvolutionStage.densetsu ? _gold : r.glowArgb;

  final parts = [for (final p in r.parts) _Rgba.decode(p.png)];
  final maps = [
    for (var i = 0; i < parts.length; i++)
      partToBase(
        r.parts[i].transform,
        baseW: base.w,
        baseH: base.h,
        partW: parts[i].w,
        partH: parts[i].h,
        scaleBoost: boost,
      ),
  ];

  // Bounds in base pixels.
  var bounds = Rect.fromLTWH(0, 0, base.w.toDouble(), base.h.toDouble());
  final partBounds = <Rect>[];
  for (var i = 0; i < parts.length; i++) {
    final b = maps[i].boundsOf(parts[i].w.toDouble(), parts[i].h.toDouble());
    partBounds.add(b);
    bounds = bounds.expandToInclude(b);
  }
  final pad = halo + 1;
  final longest = math.max(bounds.width, bounds.height);
  final k = math.min(1.0, (r.maxSide - 2 * pad) / longest);
  final outW = (bounds.width * k).ceil() + 2 * pad;
  final outH = (bounds.height * k).ceil() + 2 * pad;

  Offset toBase(int ox, int oy) => Offset(
    (ox + 0.5 - pad) / k + bounds.left,
    (oy + 0.5 - pad) / k + bounds.top,
  );
  (int, int, int, int) outBox(Rect b, int margin) => (
    math.max(0, ((b.left - bounds.left) * k + pad).floor() - margin),
    math.max(0, ((b.top - bounds.top) * k + pad).floor() - margin),
    math.min(outW, ((b.right - bounds.left) * k + pad).ceil() + margin),
    math.min(outH, ((b.bottom - bounds.top) * k + pad).ceil() + margin),
  );

  final out = Float64List(outW * outH * 4); // premultiplied
  final s = List<double>.filled(4, 0);

  void over(int i, double r0, double g0, double b0, double a0) {
    final o = i * 4;
    final inv = 1 - a0;
    out[o] = r0 + out[o] * inv;
    out[o + 1] = g0 + out[o + 1] * inv;
    out[o + 2] = b0 + out[o + 2] * inv;
    out[o + 3] = a0 + out[o + 3] * inv;
  }

  void drawPart(int pi) {
    final src = parts[pi];
    final inv = maps[pi].inverse();
    final (x0, y0, x1, y1) = outBox(partBounds[pi], halo + 2);
    final bw = x1 - x0, bh = y1 - y0;
    if (bw <= 0 || bh <= 0) return;
    final layer = Float64List(bw * bh * 4);
    // dist: 0 = part pixel, n = reached by the n-th dilation, 255 = none.
    final dist = Uint8List(bw * bh)..fillRange(0, bw * bh, 255);
    for (var y = 0; y < bh; y++) {
      for (var x = 0; x < bw; x++) {
        final p = inv.apply(toBase(x0 + x, y0 + y));
        src.sample(p.dx, p.dy, s);
        final i = y * bw + x;
        layer[i * 4] = s[0];
        layer[i * 4 + 1] = s[1];
        layer[i * 4 + 2] = s[2];
        layer[i * 4 + 3] = s[3];
        if (s[3] >= 0.5) dist[i] = 0;
      }
    }
    // Octagonal dilation (alternating 8- and 4-neighbourhoods).
    for (var step = 1; step <= halo; step++) {
      final eight = step.isOdd;
      final prev = step - 1;
      final next = <int>[];
      for (var y = 0; y < bh; y++) {
        for (var x = 0; x < bw; x++) {
          final i = y * bw + x;
          if (dist[i] != 255) continue;
          var hit = false;
          for (var dy = -1; dy <= 1 && !hit; dy++) {
            final yy = y + dy;
            if (yy < 0 || yy >= bh) continue;
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              if (!eight && dx != 0 && dy != 0) continue;
              final xx = x + dx;
              if (xx < 0 || xx >= bw) continue;
              if (dist[yy * bw + xx] == prev) {
                hit = true;
                break;
              }
            }
          }
          if (hit) next.add(i);
        }
      }
      for (final i in next) {
        dist[i] = step;
      }
    }
    final gr = ((glowColor >> 16) & 0xFF) / 255;
    final gg = ((glowColor >> 8) & 0xFF) / 255;
    final gb = (glowColor & 0xFF) / 255;
    for (var y = 0; y < bh; y++) {
      for (var x = 0; x < bw; x++) {
        final i = y * bw + x;
        final oi = (y0 + y) * outW + (x0 + x);
        final d = dist[i];
        if (d != 255 && d > partOutlinePx) {
          // Glow, fading outwards.
          final a = 0.75 * (1 - (d - partOutlinePx) / (glow + 1));
          over(oi, gr * a, gg * a, gb * a, a);
        } else if (d != 255) {
          // White sticker edge (also under the part's soft rim).
          final a = d == partOutlinePx ? 0.85 : 1.0;
          over(oi, a, a, a, a);
        }
        final o = i * 4;
        if (layer[o + 3] > 0) {
          over(oi, layer[o], layer[o + 1], layer[o + 2], layer[o + 3]);
        }
      }
    }
  }

  void drawBase() {
    final (x0, y0, x1, y1) = outBox(
      Rect.fromLTWH(0, 0, base.w.toDouble(), base.h.toDouble()),
      1,
    );
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final p = toBase(x, y);
        base.sample(p.dx, p.dy, s);
        if (s[3] > 0) over(y * outW + x, s[0], s[1], s[2], s[3]);
      }
    }
  }

  for (var i = 0; i < parts.length; i++) {
    if (r.parts[i].transform.behind) drawPart(i);
  }
  drawBase();
  for (var i = 0; i < parts.length; i++) {
    if (!r.parts[i].transform.behind) drawPart(i);
  }

  final bytes = Uint8List(outW * outH * 4);
  for (var i = 0; i < outW * outH; i++) {
    final o = i * 4;
    final a = out[o + 3];
    if (a <= 0) continue;
    bytes[o] = (out[o] / a * 255).round().clamp(0, 255);
    bytes[o + 1] = (out[o + 1] / a * 255).round().clamp(0, 255);
    bytes[o + 2] = (out[o + 2] / a * 255).round().clamp(0, 255);
    bytes[o + 3] = (a * 255).round().clamp(0, 255);
  }
  final image = img.Image.fromBytes(
    width: outW,
    height: outH,
    bytes: bytes.buffer,
    numChannels: 4,
  );
  return CompositeImage(
    png: img.encodePng(image, level: 6),
    width: outW,
    height: outH,
    baseRect: Rect.fromLTWH(
      pad - bounds.left * k,
      pad - bounds.top * k,
      base.w * k,
      base.h * k,
    ),
  );
}

/// Builds the request for [c] from its stored PNGs ([partPngs] by part id;
/// parts whose PNG is missing are skipped).
CompositeRequest compositeRequestFor(
  CharacterV2 c,
  Uint8List basePng,
  Map<String, Uint8List> partPngs, {
  required int glowArgb,
}) => CompositeRequest(
  basePng: basePng,
  parts: [
    for (final p in c.cosmetics.parts)
      if (partPngs[p.id] != null) CompositePart(partPngs[p.id]!, p.transform),
  ],
  stage: c.stage,
  glowArgb: glowArgb,
);
