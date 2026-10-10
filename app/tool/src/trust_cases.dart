/// Calibration cases for the "is this a hand drawing on paper?" detector
/// (docs/TRUST.md §3). Shared by `test/features/drawing_analysis/
/// authenticity_test.dart` and `tool/gen_trust_cases.dart`.
///
/// * [kidCases]: things children really photograph — flat scans and camera
///   shots of crayon / felt-tip / pencil drawings on white, coloured, ruled,
///   squared and crumpled paper, in dim and uneven light. **Every one must
///   be accepted.**
/// * [notDrawingCases]: digital / AI-like illustrations, halftone prints and
///   photographed screens and photos, which should be refused.
///
/// Everything is seeded, so the images are bit-for-bit reproducible.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../test/features/drawing_analysis/synthetic_drawings.dart';
import 'doodle_painter.dart';

/// A named encoded image plus the category it belongs to.
class TrustCase {
  const TrustCase(this.name, this.category, this.build);
  final String name;

  /// kid | digital | print | screen | photo
  final String category;
  final Uint8List Function() build;
}

// ---------------------------------------------------------------- helpers

Uint8List _jpg(img.Image im, [int q = 90]) => img.encodeJpg(im, quality: q);

/// The usual "sheet on a table" framing.
List<Pt> _tableCorners(int w, int h, {double skew = 0}) => [
  Pt(w * (0.15 + skew), h * 0.10),
  Pt(w * (0.86 - skew * 0.5), h * (0.14 + skew * 0.5)),
  Pt(w * 0.84, h * 0.91),
  Pt(w * 0.12, h * 0.86),
];

Uint8List _shoot(
  DoodleCanvas paper, {
  int width = 1600,
  int height = 1200,
  double skew = 0,
  double light = 0.3,
  double noise = 4,
  int quality = 90,
  int seed = 11,
  Rgb table = const Rgb(105, 80, 60),
  List<Pt>? corners,
}) => _jpg(
  photograph(
    paper,
    width: width,
    height: height,
    corners: corners ?? _tableCorners(width, height, skew: skew),
    lightFalloff: light,
    noise: noise,
    seed: seed,
    table: table,
  ),
  quality,
);

/// Copies [src] onto a new canvas with paper colour [paper] (ink is
/// multiplied, like real pigment on tinted paper).
DoodleCanvas _onPaper(DoodleCanvas src, Rgb paper, {int seed = 1}) {
  final c = DoodleCanvas(src.width, src.height, paper: paper, seed: seed);
  for (var i = 0; i < src.r.length; i++) {
    c.r[i] = src.r[i] * paper.r / 255;
    c.g[i] = src.g[i] * paper.g / 255;
    c.b[i] = src.b[i] * paper.b / 255;
    c.cover[i] = src.cover[i];
  }
  return c;
}

/// Ruled (lined) notebook paper with a red margin, then [draw] on top.
DoodleCanvas _ruled(DoodleCanvas Function() draw, {bool squares = false}) {
  final d = draw();
  final c = DoodleCanvas(d.width, d.height);
  const line = Rgb(150, 185, 230);
  const grid = Rgb(185, 200, 205);
  final step = squares ? 22.0 : 30.0;
  for (var y = step; y < d.height; y += step) {
    c.stroke([Pt(0, y), Pt(d.width.toDouble(), y)], 0.7, squares ? grid : line);
  }
  if (squares) {
    for (var x = step; x < d.width; x += step) {
      c.stroke([Pt(x, 0), Pt(x, d.height.toDouble())], 0.7, grid);
    }
  } else {
    c.stroke(
      [const Pt(70, 0), Pt(70, d.height.toDouble())],
      0.8,
      const Rgb(225, 120, 120),
    );
  }
  // Pigment over the printed lines (multiply).
  for (var i = 0; i < c.r.length; i++) {
    c.r[i] = c.r[i] * d.r[i] / 255;
    c.g[i] = c.g[i] * d.g[i] / 255;
    c.b[i] = c.b[i] * d.b[i] / 255;
    c.cover[i] = d.cover[i];
  }
  return c;
}

/// Crumpled paper: soft low-frequency shading plus a few creases.
DoodleCanvas _crumple(DoodleCanvas src, {int seed = 21}) {
  final rng = math.Random(seed);
  final creases = [
    for (var k = 0; k < 5; k++)
      (
        a: Pt(rng.nextDouble() * src.width, rng.nextDouble() * src.height),
        angle: rng.nextDouble() * math.pi,
      ),
  ];
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      var shade =
          0.86 + 0.14 * valueNoise(x / 90, y / 90, seed) - 0.04 * (x / 800);
      for (final c in creases) {
        final d =
            (x - c.a.x) * math.sin(c.angle) - (y - c.a.y) * math.cos(c.angle);
        if (d.abs() < 3) shade *= d < 0 ? 0.9 : 1.04;
      }
      final i = y * src.width + x;
      src.r[i] = (src.r[i] * shade).clamp(0, 255);
      src.g[i] = (src.g[i] * shade).clamp(0, 255);
      src.b[i] = (src.b[i] * shade).clamp(0, 255);
    }
  }
  return src;
}

/// Thin graphite pencil drawing (grey, grainy, no colour).
DoodleCanvas pencilDrawing({int seed = 31}) {
  final rng = math.Random(seed);
  final c = DoodleCanvas(800, 600, seed: seed);
  const lead = Rgb(95, 95, 100);
  final head = ellipse(400, 230, 110, 95, wobble: 0.2, rng: rng);
  c.stroke(
    tremble(densify(head, 4, closed: true), 3, rng),
    1.6,
    lead,
    texture: 0.6,
    closed: true,
  );
  for (final p in [const Pt(360, 215), const Pt(440, 210)]) {
    c.dot(p, 7, lead, texture: 0.5);
  }
  c.stroke(
    tremble(densify([const Pt(400, 325), const Pt(395, 470)], 4), 3, rng),
    1.6,
    lead,
    texture: 0.6,
  );
  for (final (a, b) in [
    (const Pt(300, 380), const Pt(500, 370)),
    (const Pt(395, 470), const Pt(330, 560)),
    (const Pt(395, 470), const Pt(470, 565)),
  ]) {
    c.stroke(tremble(densify([a, b], 4), 3, rng), 1.6, lead, texture: 0.6);
  }
  // Light hatching on the body, like kids shading with a pencil.
  for (var k = 0; k < 14; k++) {
    final y = 160 + k * 10.0 + rng.nextDouble() * 4;
    c.stroke(
      tremble(densify([Pt(330, y), Pt(470, y + 15)], 6), 2, rng),
      1.1,
      lead,
      texture: 0.7,
      opacity: 0.6,
    );
  }
  return c;
}

/// Kid watercolour painting: soft, bleeding colour patches with gradients
/// (real art that looks "smooth"), plus a wobbly brush outline.
DoodleCanvas watercolourPainting({int seed = 41}) {
  final rng = math.Random(seed);
  final c = DoodleCanvas(800, 600, seed: seed);
  final blobs = [
    (p: const Pt(380, 320), r: 170.0, col: const Rgb(90, 150, 230)),
    (p: const Pt(520, 260), r: 110.0, col: const Rgb(240, 140, 170)),
    (p: const Pt(250, 200), r: 90.0, col: const Rgb(250, 210, 80)),
  ];
  for (final b in blobs) {
    final poly = ellipse(b.p.x, b.p.y, b.r, b.r * 0.8, wobble: 0.25, rng: rng);
    c.fillPolygon(poly, (x, y) {
      final d = math.sqrt(
        math.pow((x - b.p.x) / b.r, 2) + math.pow((y - b.p.y) / b.r, 2),
      );
      // Pigment pools at the rim, thinner in the middle.
      final t = (0.35 + 0.5 * d * d + 0.15 * valueNoise(x / 25, y / 25, seed))
          .clamp(0.0, 1.0);
      return Rgb.white.lerp(b.col, t);
    });
  }
  c.stroke(
    tremble(
      densify(
        ellipse(380, 320, 170, 136, wobble: 0.2, rng: rng),
        5,
        closed: true,
      ),
      4,
      rng,
    ),
    3,
    const Rgb(40, 60, 120),
    texture: 0.2,
    closed: true,
  );
  c.dot(const Pt(330, 290), 12, Crayon.black);
  c.dot(const Pt(430, 285), 12, Crayon.black);
  return c;
}

/// Glossy, symmetric "AI mascot sticker": radial 3D shading, rim light,
/// clean anti-aliased outline, catch-lights, many colours, soft drop shadow.
DoodleCanvas aiSticker({
  int seed = 0,
  Rgb base = const Rgb(120, 200, 110),
  int width = 800,
  int height = 600,
}) {
  final c = DoodleCanvas(width, height, seed: seed);
  final cx = width / 2, cy = height / 2 + 10;
  final s = width / 800;
  // Soft drop shadow.
  c.fillPolygon(ellipse(cx, cy + 205 * s, 170 * s, 26 * s, n: 160), (x, y) {
    final d = math.sqrt(
      math.pow((x - cx) / (170 * s), 2) +
          math.pow((y - cy - 205 * s) / (26 * s), 2),
    );
    return Rgb.white.lerp(const Rgb(170, 175, 185), (1 - d).clamp(0.0, 1.0));
  });
  final dark = Rgb(base.r * 0.35, base.g * 0.35, base.b * 0.45);
  final light = base.lerp(Rgb.white, 0.65);
  // Horns.
  for (final sx in [-1.0, 1.0]) {
    final horn = [
      Pt(cx + sx * 70 * s, cy - 150 * s),
      Pt(cx + sx * 120 * s, cy - 250 * s),
      Pt(cx + sx * 130 * s, cy - 140 * s),
    ];
    c.fillPolygon(horn, (x, y) {
      final t = ((y - (cy - 250 * s)) / (110 * s)).clamp(0.0, 1.0);
      return const Rgb(255, 240, 200).lerp(const Rgb(210, 150, 60), t);
    });
    c.stroke(horn, 2.2 * s, dark, closed: true);
  }
  final body = ellipse(cx, cy, 190 * s, 200 * s, n: 360);
  c.fillPolygon(body, (x, y) {
    final d = math.sqrt(
      math.pow((x - cx + 70 * s) / (260 * s), 2) +
          math.pow((y - cy + 90 * s) / (280 * s), 2),
    );
    final rim = math.max(
      0.0,
      1 -
          (math.sqrt(
                        math.pow((x - cx) / (190 * s), 2) +
                            math.pow((y - cy) / (200 * s), 2),
                      ) -
                      0.86)
                  .abs() /
              0.08,
    );
    return light
        .lerp(base, (d * 1.3).clamp(0.0, 1.0))
        .lerp(dark, ((d - 0.8) * 1.5).clamp(0.0, 1.0))
        .lerp(const Rgb(255, 250, 220), rim * 0.35 * (x > cx ? 1 : 0));
  });
  // Belly with a vertical gradient.
  final belly = ellipse(cx, cy + 60 * s, 105 * s, 110 * s, n: 240);
  c.fillPolygon(belly, (x, y) {
    final t = ((y - cy + 50 * s) / (220 * s)).clamp(0.0, 1.0);
    return const Rgb(255, 248, 225).lerp(const Rgb(235, 200, 150), t);
  });
  // Eyes: iris gradient, pupil, two catch-lights each.
  for (final sx in [-1.0, 1.0]) {
    final ex = cx + sx * 68 * s, ey = cy - 60 * s;
    c.fillSolid(ellipse(ex, ey, 44 * s, 50 * s, n: 160), Rgb.white);
    c.fillPolygon(ellipse(ex, ey + 6 * s, 30 * s, 36 * s, n: 140), (x, y) {
      final t = ((y - ey + 30 * s) / (72 * s)).clamp(0.0, 1.0);
      return const Rgb(90, 60, 30).lerp(const Rgb(240, 170, 60), t);
    });
    c.fillSolid(ellipse(ex, ey + 8 * s, 15 * s, 18 * s, n: 80), Rgb.black);
    c.dot(Pt(ex - 10 * s, ey - 8 * s), 7 * s, Rgb.white);
    c.dot(Pt(ex + 9 * s, ey + 16 * s), 3.5 * s, Rgb.white);
    c.stroke(
      ellipse(ex, ey, 44 * s, 50 * s, n: 160),
      2.2 * s,
      dark,
      closed: true,
    );
    // Blush.
    c.fillPolygon(ellipse(cx + sx * 120 * s, cy + 10 * s, 26 * s, 14 * s), (
      x,
      y,
    ) {
      final d = math.sqrt(
        math.pow((x - cx - sx * 120 * s) / (26 * s), 2) +
            math.pow((y - cy - 10 * s) / (14 * s), 2),
      );
      return const Rgb(255, 150, 170).lerp(base, d.clamp(0.0, 1.0));
    });
  }
  // Smile with a tongue.
  final mouth = [
    for (var k = 0; k <= 24; k++)
      Pt(
        cx + 40 * s * math.cos(math.pi * k / 24),
        cy + 20 * s + 26 * s * math.sin(math.pi * k / 24),
      ),
  ];
  c.fillSolid(mouth, const Rgb(150, 40, 60));
  c.fillSolid(
    ellipse(cx, cy + 38 * s, 18 * s, 8 * s, n: 60),
    const Rgb(250, 120, 140),
  );
  c.stroke(mouth, 2 * s, dark, closed: true);
  c.stroke(body, 3 * s, dark, closed: true);
  return c;
}

/// Full-frame "AI painting": a smoothly lit scene with a cute character —
/// no paper, gradients everywhere.
DoodleCanvas aiPainting({int seed = 0}) {
  final c = DoodleCanvas(800, 600, seed: seed);
  for (var y = 0; y < 600; y++) {
    for (var x = 0; x < 800; x++) {
      final i = y * 800 + x;
      final v = y / 600, u = x / 800;
      final sky = const Rgb(120, 170, 240).lerp(const Rgb(250, 210, 230), v);
      final col = v > 0.7
          ? const Rgb(110, 190, 120).lerp(const Rgb(60, 130, 80), (v - 0.7) * 3)
          : sky.lerp(
              const Rgb(255, 245, 200),
              math.exp(-(math.pow(u - 0.8, 2) + math.pow(v - 0.2, 2)) * 20),
            );
      c.r[i] = col.r;
      c.g[i] = col.g;
      c.b[i] = col.b;
    }
  }
  final sticker = aiSticker(seed: seed, base: const Rgb(240, 150, 80));
  for (var i = 0; i < c.r.length; i++) {
    final a = sticker.cover[i];
    if (a <= 0) continue;
    c.r[i] += (sticker.r[i] - c.r[i]) * a;
    c.g[i] += (sticker.g[i] - c.g[i]) * a;
    c.b[i] += (sticker.b[i] - c.b[i]) * a;
  }
  return c;
}

/// Prints [src] with an AM halftone screen of [period] px (C, M, Y, K at
/// 15°, 75°, 0°, 45°) onto paper of [scale]× the source size.
DoodleCanvas halftonePrint(
  DoodleCanvas src, {
  double period = 6,
  int scale = 2,
}) {
  final w = src.width * scale, h = src.height * scale;
  final out = DoodleCanvas(w, h);
  final srcImg = RgbImageView(src);
  const angles = [15.0, 75.0, 0.0, 45.0];
  final cs = [for (final a in angles) math.cos(a * math.pi / 180)];
  final sn = [for (final a in angles) math.sin(a * math.pi / 180)];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final (r, g, b) = srcImg.sample(
        (x + 0.5) / scale - 0.5,
        (y + 0.5) / scale - 0.5,
      );
      // RGB → CMYK.
      final k = 1 - math.max(r, math.max(g, b)) / 255;
      final d = k >= 1 ? 1.0 : 1 - k;
      final cmyk = [
        (1 - r / 255 - k) / d,
        (1 - g / 255 - k) / d,
        (1 - b / 255 - k) / d,
        k,
      ];
      var rr = 255.0, gg = 255.0, bb = 255.0;
      for (var ch = 0; ch < 4; ch++) {
        final cov = cmyk[ch].clamp(0.0, 1.0);
        if (cov < 0.02) continue;
        // Position inside the rotated screen cell.
        final u = (x * cs[ch] + y * sn[ch]) / period;
        final v = (-x * sn[ch] + y * cs[ch]) / period;
        final fu = u - u.floorToDouble() - 0.5,
            fv = v - v.floorToDouble() - 0.5;
        final dist = math.sqrt(fu * fu + fv * fv);
        final radius = math.sqrt(cov / math.pi);
        // Anti-aliased dot edge.
        final a = ((radius - dist) * period + 0.5).clamp(0.0, 1.0);
        if (a <= 0) continue;
        switch (ch) {
          case 0: // cyan
            rr *= 1 - 0.85 * a;
          case 1: // magenta
            gg *= 1 - 0.85 * a;
          case 2: // yellow
            bb *= 1 - 0.85 * a;
          default:
            rr *= 1 - 0.9 * a;
            gg *= 1 - 0.9 * a;
            bb *= 1 - 0.9 * a;
        }
      }
      final i = y * w + x;
      out.r[i] = rr;
      out.g[i] = gg;
      out.b[i] = bb;
    }
  }
  return out;
}

/// What a camera sees on an LCD showing [src]: every source pixel is drawn
/// as a [pitch]×[pitch] cell of R, G, B sub-pixel stripes with a dark
/// matrix between them, on a backlit panel.
DoodleCanvas screenPanel(DoodleCanvas src, {double pitch = 5, int scale = 2}) {
  final w = src.width * scale, h = src.height * scale;
  final out = DoodleCanvas(w, h);
  final view = RgbImageView(src);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final sx = (x / pitch).floorToDouble() * pitch / scale;
      final sy = (y / pitch).floorToDouble() * pitch / scale;
      final (r, g, b) = view.sample(sx, sy);
      final fx = (x % pitch) / pitch, fy = (y % pitch) / pitch;
      final sub = (fx * 3).floor().clamp(0, 2);
      final inSub = (fx * 3 - sub) < 0.8 && fy < 0.85;
      final glow = inSub ? 1.0 : 0.15;
      final i = y * w + x;
      // Backlight bleeds a little into the other channels.
      out.r[i] = ((sub == 0 ? r : r * 0.12) * glow * 1.1 + 6).clamp(0, 255);
      out.g[i] = ((sub == 1 ? g : g * 0.12) * glow * 1.1 + 6).clamp(0, 255);
      out.b[i] = ((sub == 2 ? b : b * 0.12) * glow * 1.1 + 8).clamp(0, 255);
    }
  }
  return out;
}

/// Adds a soft specular glare blob (screens and glossy prints).
img.Image _glare(img.Image im, double u, double v, double radius) {
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final d = math.pow(x / im.width - u, 2) + math.pow(y / im.height - v, 2);
      final g = 120 * math.exp(-d / (radius * radius));
      if (g < 1) continue;
      final p = im.getPixel(x, y);
      im.setPixelRgb(
        x,
        y,
        (p.r + g).clamp(0, 255).toInt(),
        (p.g + g).clamp(0, 255).toInt(),
        (p.b + g).clamp(0, 255).toInt(),
      );
    }
  }
  return im;
}

/// Bilinear sampler over a [DoodleCanvas].
class RgbImageView {
  RgbImageView(this.c);
  final DoodleCanvas c;

  (double, double, double) sample(double x, double y) {
    x = x.clamp(0, c.width - 1.0);
    y = y.clamp(0, c.height - 1.0);
    final x0 = x.floor(), y0 = y.floor();
    final x1 = math.min(x0 + 1, c.width - 1),
        y1 = math.min(y0 + 1, c.height - 1);
    final fx = x - x0, fy = y - y0;
    double ch(List<double> a) {
      final top = a[y0 * c.width + x0] * (1 - fx) + a[y0 * c.width + x1] * fx;
      final bot = a[y1 * c.width + x0] * (1 - fx) + a[y1 * c.width + x1] * fx;
      return top * (1 - fy) + bot * fy;
    }

    return (ch(c.r), ch(c.g), ch(c.b));
  }
}

/// A CPU doodle cut-out composited back onto a white sheet.
DoodleCanvas _cpuOnPaper(String id) {
  final png = img.decodePng(File('assets/cpu/$id.png').readAsBytesSync())!;
  final c = DoodleCanvas(png.width + 120, png.height + 120);
  for (var y = 0; y < png.height; y++) {
    for (var x = 0; x < png.width; x++) {
      final p = png.getPixel(x, y);
      final a = p.a / 255;
      final i = (y + 60) * c.width + x + 60;
      c.r[i] = p.r * a + 255 * (1 - a);
      c.g[i] = p.g * a + 255 * (1 - a);
      c.b[i] = p.b * a + 255 * (1 - a);
    }
  }
  return c;
}

const cpuDoodleIds = [
  'cpu_fire_blob',
  'cpu_fire_spiky',
  'cpu_water_snake',
  'cpu_water_fish',
  'cpu_leaf_frog',
  'cpu_leaf_caterpillar',
  'cpu_thunder_bird',
  'cpu_thunder_star',
  'cpu_shadow_ghost',
  'cpu_shadow_bat',
  'cpu_rainbow_cat',
  'cpu_rainbow_robot',
];

// ------------------------------------------------------------------ cases

/// Kids' drawings (must all be accepted). [withCpu] needs the working
/// directory to be `app/` (reads `assets/cpu/*.png`).
List<TrustCase> kidCases({bool withCpu = true}) => [
  // Flat, noise-free renders (also what older tests feed the analyzer).
  for (final s in [1, 2, 3])
    TrustCase('crayon flat #$s', 'kid', () => kidScribble(seed: s).encodePng()),
  TrustCase('felt-tip flat', 'kid', () => kidMarker().encodePng()),
  TrustCase('pencil flat', 'kid', () => pencilDrawing().encodePng()),
  for (final (n, col) in [
    ('red', Crayon.red),
    ('orange', Crayon.orange),
    ('blue', Crayon.blue),
    ('sky', Crayon.sky),
    ('green', Crayon.green),
    ('yellow', Crayon.yellow),
  ])
    TrustCase('blob $n flat', 'kid', () => colourBlob(col).encodePng()),
  TrustCase('monochrome flat', 'kid', () => monochrome().encodePng()),
  TrustCase('rainbow flat', 'kid', () => rainbowBlob().encodePng()),
  TrustCase('watercolour flat', 'kid', () => watercolourPainting().encodePng()),
  if (withCpu)
    for (final id in cpuDoodleIds)
      TrustCase(
        '$id (asset)',
        'kid',
        () => File('assets/cpu/$id.png').readAsBytesSync(),
      ),
  // Camera shots.
  TrustCase(
    'photo crayon on table',
    'kid',
    () => photographedOnTable(kidScribble()).jpeg,
  ),
  TrustCase(
    'photo felt-tip, steep perspective',
    'kid',
    () => _shoot(kidMarker(), skew: 0.12, light: 0.45, seed: 12),
  ),
  TrustCase(
    'photo pencil only',
    'kid',
    () => _shoot(pencilDrawing(), seed: 13),
  ),
  TrustCase(
    'photo crumpled paper',
    'kid',
    () => _shoot(_crumple(kidScribble(seed: 4)), seed: 14),
  ),
  TrustCase(
    'photo ruled notebook',
    'kid',
    () => _shoot(_ruled(kidMarker), seed: 15),
  ),
  TrustCase(
    'photo squared paper',
    'kid',
    () => _shoot(_ruled(() => kidScribble(seed: 5), squares: true), seed: 16),
  ),
  TrustCase(
    'photo yellow paper',
    'kid',
    () => _shoot(
      _onPaper(kidScribble(seed: 6), const Rgb(250, 232, 165)),
      seed: 17,
    ),
  ),
  TrustCase(
    'photo pink paper',
    'kid',
    () => _shoot(
      _onPaper(kidMarker(seed: 7), const Rgb(248, 200, 212)),
      seed: 18,
    ),
  ),
  TrustCase('photo dim room', 'kid', () {
    final im = photograph(
      kidScribble(seed: 8),
      width: 1600,
      height: 1200,
      corners: _tableCorners(1600, 1200),
      lightFalloff: 0.55,
      noise: 9,
      seed: 19,
    );
    for (final p in im) {
      p
        ..r = p.r * 0.55
        ..g = p.g * 0.5
        ..b = p.b * 0.42;
    }
    return _jpg(im, 85);
  }),
  TrustCase(
    'photo close-up (paper fills frame)',
    'kid',
    () => _shoot(
      rainbowBlob(),
      corners: const [
        Pt(-60, -50),
        Pt(1660, -40),
        Pt(1650, 1250),
        Pt(-50, 1240),
      ],
      seed: 20,
    ),
  ),
  TrustCase(
    'photo low-quality JPEG',
    'kid',
    () => _shoot(colourBlob(Crayon.green), quality: 55, seed: 21),
  ),
  TrustCase(
    'photo phone noise reduction',
    'kid',
    () => _shoot(kidScribble(seed: 9), noise: 0.8, quality: 95, seed: 22),
  ),
  TrustCase(
    'photo watercolour painting',
    'kid',
    () => _shoot(watercolourPainting(), seed: 23),
  ),
  TrustCase('photo 512px from gallery', 'kid', () {
    final full = img.decodeJpg(_shoot(kidMarker(seed: 10), seed: 24))!;
    return _jpg(img.copyResize(full, width: 512), 88);
  }),
  TrustCase(
    'photo 4000px original',
    'kid',
    () => _shoot(kidScribble(seed: 11), width: 2048, height: 1536, seed: 25),
  ),
  if (withCpu)
    for (final id in cpuDoodleIds.take(4))
      TrustCase(
        'photo $id',
        'kid',
        () => _shoot(_cpuOnPaper(id), seed: 26 + id.length),
      ),
];

/// Pictures that are not a hand drawing on paper.
List<TrustCase> notDrawingCases() => [
  // Digital / AI-like illustrations (gallery import, screenshots).
  TrustCase('AI sticker PNG', 'digital', () => aiSticker().encodePng()),
  TrustCase(
    'AI sticker JPEG',
    'digital',
    () => _jpg(aiSticker(base: const Rgb(110, 150, 240)).toImage(), 88),
  ),
  TrustCase(
    'AI sticker pink PNG',
    'digital',
    () => aiSticker(base: const Rgb(240, 130, 170), seed: 2).encodePng(),
  ),
  TrustCase(
    'AI sticker 1024 JPEG',
    'digital',
    () => _jpg(
      aiSticker(
        base: const Rgb(250, 190, 70),
        width: 1024,
        height: 1024,
      ).toImage(),
      92,
    ),
  ),
  TrustCase('AI painting PNG', 'digital', () => aiPainting().encodePng()),
  TrustCase(
    'AI painting JPEG',
    'digital',
    () => _jpg(aiPainting(seed: 1).toImage(), 85),
  ),
  TrustCase(
    'shaded line art PNG',
    'digital',
    () => skilledLineArt().encodePng(),
  ),
  TrustCase(
    'shaded line art JPEG',
    'digital',
    () => _jpg(skilledLineArt().toImage(), 90),
  ),
  // Halftone prints photographed on a table.
  for (final (n, src, period) in [
    ('AI sticker', () => aiSticker(), 6.0),
    ('kid crayon', () => kidScribble(seed: 12), 6.0),
    ('shaded line art', skilledLineArt, 5.0),
    ('AI painting', () => aiPainting(seed: 2), 7.0),
  ])
    TrustCase(
      'print of $n (${period.toStringAsFixed(0)}px dots)',
      'print',
      () => _shoot(
        halftonePrint(src(), period: period),
        width: 2000,
        height: 1500,
        noise: 3,
        seed: 40 + period.round(),
      ),
    ),
  // Photos of a screen (pixel grid, sub-pixels, glare, dark bezel).
  for (final (n, src, pitch) in [
    ('AI sticker', () => aiSticker(), 5.0),
    ('kid crayon', () => kidScribble(seed: 13), 4.5),
    ('AI painting', () => aiPainting(seed: 3), 6.0),
  ])
    TrustCase(
      'screen showing $n',
      'screen',
      () => _jpg(
        _glare(
          photograph(
            screenPanel(src(), pitch: pitch),
            width: 2000,
            height: 1500,
            corners: _tableCorners(2000, 1500, skew: 0.04),
            table: const Rgb(25, 25, 28),
            lightFalloff: 0.15,
            noise: 3,
            seed: 50 + pitch.round(),
          ),
          0.62,
          0.35,
          0.12,
        ),
      ),
    ),
  // Photographs.
  TrustCase('photo still life', 'photo', photoLike),
  TrustCase('photo landscape', 'photo', photoLandscape),
  TrustCase('photo still life #2', 'photo', () => photoLike(seed: 9)),
  TrustCase('photo landscape #2', 'photo', () => photoLandscape(seed: 9)),
];
