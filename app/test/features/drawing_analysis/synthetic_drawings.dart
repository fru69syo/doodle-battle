/// Programmatically generated drawings used to check the scoring behaviour.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../tool/src/doodle_painter.dart';

/// Wobbly, thick-crayon, asymmetric kid scribble with 4 flat colours.
DoodleCanvas kidScribble({int seed = 1, int width = 800, int height = 600}) {
  final rng = math.Random(seed);
  final c = DoodleCanvas(width, height, seed: seed);
  final s = width / 800;
  // Lumpy body coloured in with zig-zags, then a shaky outline.
  final body = ellipse(
    370 * s,
    330 * s,
    190 * s,
    140 * s,
    n: 60,
    wobble: 0.18,
    rng: rng,
  );
  c.scribbleFill(
    body,
    Crayon.red,
    rng,
    radius: 6 * s,
    spacing: 9 * s,
    texture: 0.55,
  );
  c.stroke(
    tremble(densify(body, 6 * s, closed: true), 4 * s, rng),
    7 * s,
    Crayon.black,
    texture: 0.45,
    closed: true,
  );
  // Lopsided eyes.
  c.dot(Pt(300 * s, 290 * s), 22 * s, Rgb.white);
  c.dot(Pt(300 * s, 295 * s), 11 * s, Crayon.black, texture: 0.3);
  c.dot(Pt(440 * s, 270 * s), 15 * s, Crayon.black, texture: 0.3);
  // Uneven legs and a single arm.
  for (final x in [290.0, 380.0, 470.0]) {
    final leg = densify([
      Pt(x * s, 440 * s),
      Pt(
        (x + rng.nextDouble() * 40 - 20) * s,
        (520 + rng.nextDouble() * 30) * s,
      ),
    ], 5 * s);
    c.stroke(tremble(leg, 5 * s, rng), 8 * s, Crayon.blue, texture: 0.5);
  }
  c.stroke(
    tremble(
      densify([
        Pt(540 * s, 300 * s),
        Pt(650 * s, 220 * s),
        Pt(700 * s, 250 * s),
      ], 5 * s),
      5 * s,
      rng,
    ),
    8 * s,
    Crayon.green,
    texture: 0.5,
  );
  // Yellow sun-ish scribble on one side.
  final sun = ellipse(140 * s, 140 * s, 55 * s, 50 * s, wobble: 0.2, rng: rng);
  c.scribbleFill(
    sun,
    Crayon.yellow,
    rng,
    radius: 6 * s,
    spacing: 8 * s,
    texture: 0.5,
  );
  return c;
}

/// Clean, symmetric line art with smooth gradient shading and fine detail
/// (what a skilled adult would produce).
DoodleCanvas skilledLineArt({int width = 800, int height = 600}) {
  final c = DoodleCanvas(width, height);
  const cx = 400.0, cy = 310.0;
  // Owl-like body with radial gradient shading.
  final body = ellipse(cx, cy, 170, 210, n: 240);
  const light = Rgb(175, 205, 245), dark = Rgb(30, 60, 140);
  c.fillPolygon(body, (x, y) {
    final d = math.sqrt(
      math.pow((x - cx + 60) / 210, 2) + math.pow((y - cy + 80) / 250, 2),
    );
    return light.lerp(dark, d.clamp(0.0, 1.0));
  });
  // Belly with its own vertical gradient.
  final belly = ellipse(cx, cy + 60, 100, 120, n: 200);
  c.fillPolygon(belly, (x, y) {
    final t = ((y - (cy - 60)) / 240).clamp(0.0, 1.0);
    return const Rgb(250, 235, 200).lerp(const Rgb(200, 150, 90), t);
  });
  c.stroke(belly, 1.2, Rgb.black, closed: true);
  c.stroke(body, 1.6, Rgb.black, closed: true);
  // Symmetric eyes with highlights and rings.
  for (final sx in [-1.0, 1.0]) {
    final ex = cx + sx * 70;
    const ey = cy - 90.0;
    c.fillSolid(ellipse(ex, ey, 46, 46, n: 120), Rgb.white);
    c.stroke(ellipse(ex, ey, 46, 46, n: 120), 1.2, Rgb.black, closed: true);
    c.stroke(ellipse(ex, ey, 34, 34, n: 100), 0.8, Rgb.black, closed: true);
    c.fillSolid(ellipse(ex, ey, 18, 18, n: 60), Rgb.black);
    c.dot(Pt(ex - 6, ey - 6), 4, Rgb.white);
    // Ear tufts.
    c.stroke(
      [
        Pt(cx + sx * 110, cy - 170),
        Pt(cx + sx * 150, cy - 245),
        Pt(cx + sx * 160, cy - 160),
      ],
      1.4,
      Rgb.black,
    );
  }
  // Beak.
  c.fillSolid([
    Pt(cx - 14, cy - 60),
    Pt(cx + 14, cy - 60),
    Pt(cx, cy - 30),
  ], const Rgb(240, 170, 40));
  c.stroke(
    [Pt(cx - 14, cy - 60), Pt(cx + 14, cy - 60), Pt(cx, cy - 30)],
    0.9,
    Rgb.black,
    closed: true,
  );
  // Feather pattern: rows of small symmetric arcs on the belly.
  for (var row = 0; row < 6; row++) {
    final y = cy + 5 + row * 20.0;
    final half = 70 - (row - 2.5).abs() * 12;
    for (var x = -half; x <= half + 0.1; x += 18) {
      final arc = [
        for (var k = 0; k <= 8; k++)
          Pt(
            cx + x + 7 * math.cos(math.pi * k / 8),
            y + 6 * math.sin(math.pi * k / 8),
          ),
      ];
      c.stroke(arc, 0.7, const Rgb(90, 60, 40));
    }
  }
  // Wing hatching (mirrored).
  for (final sx in [-1.0, 1.0]) {
    for (var k = 0; k < 9; k++) {
      final y = cy - 20 + k * 16.0;
      c.stroke(
        [Pt(cx + sx * 120, y), Pt(cx + sx * 155, y + 22)],
        0.7,
        const Rgb(20, 30, 70),
      );
    }
  }
  // Feet.
  for (final sx in [-1.0, 1.0]) {
    for (var t = -1; t <= 1; t++) {
      c.stroke(
        [Pt(cx + sx * 50, cy + 205), Pt(cx + sx * 50 + t * 10, cy + 228)],
        1.1,
        const Rgb(200, 120, 20),
      );
    }
  }
  return c;
}

/// Smooth 2D value noise in [0, 1) (bilinear between hashed lattice points).
double valueNoise(double x, double y, int seed) {
  final x0 = x.floor(), y0 = y.floor();
  final fx = x - x0, fy = y - y0;
  final sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
  final a = hashNoise(x0, y0, seed), b = hashNoise(x0 + 1, y0, seed);
  final c = hashNoise(x0, y0 + 1, seed), d = hashNoise(x0 + 1, y0 + 1, seed);
  return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy;
}

/// Close-up still-life photo: blurred warm background, shaded fruit, a wood
/// table with grain, highlights, soft shadows and sensor noise. Fills the
/// frame, no paper. Returned as JPEG bytes.
Uint8List photoLike({int width = 1200, int height = 900, int seed = 3}) {
  final rng = math.Random(seed);
  final im = img.Image(width: width, height: height);
  final fruits = [
    (u: 0.35, v: 0.52, r: 0.20, base: const Rgb(235, 120, 20)), // orange
    (u: 0.66, v: 0.58, r: 0.16, base: const Rgb(150, 30, 40)), // apple
    (u: 0.53, v: 0.33, r: 0.11, base: const Rgb(120, 170, 40)), // lime
  ];
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final u = x / width, v = y / height;
      double r, g, b;
      if (v < 0.62) {
        // Out-of-focus wall with bokeh blobs.
        final n = valueNoise(u * 4, v * 4, seed);
        r = 150 + 60 * n + 40 * u;
        g = 110 + 50 * n + 10 * v;
        b = 80 + 30 * n - 20 * u;
      } else {
        // Wooden table with grain and texture.
        final grain = valueNoise(u * 3, v * 60, seed + 1);
        final fine = valueNoise(u * 40, v * 200, seed + 2);
        r = 120 + 50 * grain + 20 * fine - 40 * (v - 0.62);
        g = 75 + 35 * grain + 12 * fine - 30 * (v - 0.62);
        b = 45 + 20 * grain + 8 * fine;
      }
      for (final f in fruits) {
        // Soft contact shadow under each fruit.
        final sd = math.sqrt(
          math.pow((u - f.u - 0.04) / 1.6, 2) +
              math.pow((v - f.v - f.r * 0.9) * 3, 2),
        );
        if (sd < f.r) {
          final k = 0.55 + 0.45 * sd / f.r;
          r *= k;
          g *= k;
          b *= k;
        }
      }
      for (final f in fruits) {
        final dx = (u - f.u) * width / height, dy = v - f.v;
        final dd = math.sqrt(dx * dx + dy * dy);
        if (dd < f.r) {
          final nz = math.sqrt(1 - math.pow(dd / f.r, 2));
          final lambert =
              (0.35 + 0.65 * (nz * 0.7 - dx / f.r * 0.5 - dy / f.r * 0.5))
                  .clamp(0.15, 1.0);
          final spec =
              math.pow(
                math.max(
                  0,
                  1 -
                      math.sqrt(
                            math.pow(dx / f.r + 0.35, 2) +
                                math.pow(dy / f.r + 0.4, 2),
                          ) *
                          3,
                ),
                2,
              ) *
              200;
          final pores = valueNoise(x / 3, y / 3, seed + 5) * 18;
          r = f.base.r * lambert + spec + pores;
          g = f.base.g * lambert + spec * 0.95 + pores;
          b = f.base.b * lambert + spec * 0.9 + pores * 0.5;
        }
      }
      double nz() => 5 * (rng.nextDouble() + rng.nextDouble() - 1);
      im.setPixelRgb(
        x,
        y,
        (r + nz()).round().clamp(0, 255),
        (g + nz()).round().clamp(0, 255),
        (b + nz()).round().clamp(0, 255),
      );
    }
  }
  return img.encodeJpg(im, quality: 90);
}

/// Landscape photo: sky gradient with a sun glow, hills, a shaded ball and
/// sensor noise. Returned as JPEG bytes.
Uint8List photoLandscape({int width = 1200, int height = 900, int seed = 3}) {
  final rng = math.Random(seed);
  final im = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final u = x / width, v = y / height;
      double r, g, b;
      final hill = 0.55 + 0.08 * math.sin(u * 7) + 0.05 * math.cos(u * 13 + 1);
      if (v < hill) {
        // Sky: blue to warm haze.
        r = 70 + 150 * v + 20 * u;
        g = 120 + 100 * v;
        b = 220 - 40 * v;
        final sd = math.sqrt(math.pow(u - 0.75, 2) + math.pow(v - 0.2, 2));
        final glow = math.exp(-sd * sd * 40);
        r += 120 * glow;
        g += 100 * glow;
        b += 40 * glow;
      } else {
        final t = (v - hill) / (1 - hill);
        r = 60 + 80 * t + 30 * math.sin(u * 20);
        g = 120 + 50 * t - 20 * u;
        b = 40 + 30 * t;
      }
      // A shaded "ball" in the foreground.
      final bd = math.sqrt(
        math.pow(u - 0.3, 2) + math.pow((v - 0.72) * 1.33, 2),
      );
      if (bd < 0.12) {
        final shade = 1 - bd / 0.12;
        r = 120 + 120 * shade;
        g = 30 + 60 * shade;
        b = 60 + 90 * shade;
      }
      double n() => 6 * (rng.nextDouble() + rng.nextDouble() - 1);
      im.setPixelRgb(
        x,
        y,
        (r + n()).round().clamp(0, 255),
        (g + n()).round().clamp(0, 255),
        (b + n()).round().clamp(0, 255),
      );
    }
  }
  return img.encodeJpg(im, quality: 90);
}

/// A single dot on otherwise blank paper.
DoodleCanvas singleDot() =>
    DoodleCanvas(800, 600)..dot(const Pt(400, 300), 6, Crayon.black);

/// One short thin line.
DoodleCanvas tinyLine() =>
    DoodleCanvas(800, 600)
      ..stroke([const Pt(380, 300), const Pt(440, 310)], 1.5, Crayon.blue);

/// A simple kid blob filled with one colour and a few black features.
DoodleCanvas colourBlob(Rgb colour, {int seed = 5}) {
  final rng = math.Random(seed);
  final c = DoodleCanvas(800, 600, seed: seed);
  final body = ellipse(400, 300, 200, 160, wobble: 0.15, rng: rng);
  c.scribbleFill(body, colour, rng, radius: 6, spacing: 8, texture: 0.4);
  c.stroke(
    tremble(densify(body, 6, closed: true), 3, rng),
    5,
    colour,
    texture: 0.3,
    closed: true,
  );
  c.dot(const Pt(340, 260), 10, Crayon.black);
  c.dot(const Pt(450, 255), 10, Crayon.black);
  return c;
}

/// Black/grey pencil-and-marker drawing.
DoodleCanvas monochrome({int seed = 6}) {
  final rng = math.Random(seed);
  final c = DoodleCanvas(800, 600, seed: seed);
  final body = ellipse(400, 300, 180, 170, wobble: 0.15, rng: rng);
  c.scribbleFill(body, Crayon.grey, rng, radius: 5, spacing: 8, texture: 0.4);
  c.stroke(
    tremble(densify(body, 6, closed: true), 3, rng),
    6,
    Crayon.black,
    texture: 0.3,
    closed: true,
  );
  c.dot(const Pt(340, 260), 14, Crayon.black);
  return c;
}

/// Five balanced colour stripes inside a blob.
DoodleCanvas rainbowBlob({int seed = 8}) {
  final rng = math.Random(seed);
  final c = DoodleCanvas(800, 600, seed: seed);
  final colours = [
    Crayon.red,
    Crayon.yellow,
    Crayon.green,
    Crayon.blue,
    Crayon.purple,
  ];
  for (var k = 0; k < colours.length; k++) {
    final top = 130 + k * 70.0;
    final band = [
      Pt(180, top),
      Pt(620, top - 10),
      Pt(620, top + 62),
      Pt(180, top + 66),
    ];
    c.scribbleFill(band, colours[k], rng, radius: 6, spacing: 8, texture: 0.4);
  }
  return c;
}

/// Encodes a canvas photographed on a darker table with mild perspective
/// and uneven light. Also returns the corners used.
({Uint8List jpeg, List<Pt> corners}) photographedOnTable(
  DoodleCanvas paper, {
  int width = 1600,
  int height = 1200,
}) {
  final corners = [
    Pt(width * 0.17, height * 0.12),
    Pt(width * 0.86, height * 0.16),
    Pt(width * 0.82, height * 0.90),
    Pt(width * 0.13, height * 0.85),
  ];
  final photo = photograph(
    paper,
    width: width,
    height: height,
    corners: corners,
    lightFalloff: 0.3,
    noise: 4,
    seed: 11,
  );
  return (jpeg: img.encodeJpg(photo, quality: 90), corners: corners);
}

/// Kid drawing made with thin felt-tip markers: clean edges (no crayon
/// grain) but shaky, asymmetric, flat colours.
DoodleCanvas kidMarker({int seed = 4}) {
  final rng = math.Random(seed);
  final c = DoodleCanvas(800, 600, seed: seed);
  final head = ellipse(380, 250, 120, 105, wobble: 0.2, rng: rng);
  c.stroke(
    tremble(densify(head, 5, closed: true), 4, rng, smooth: 3),
    2.5,
    Crayon.black,
    closed: true,
  );
  c.dot(const Pt(340, 230), 8, Crayon.black);
  c.dot(const Pt(425, 220), 6, Crayon.black);
  c.stroke(
    tremble(
      densify([const Pt(330, 300), const Pt(380, 320), const Pt(430, 290)], 5),
      3,
      rng,
    ),
    2.5,
    Crayon.red,
  );
  // Stick body and limbs.
  c.stroke(
    tremble(densify([const Pt(380, 355), const Pt(390, 500)], 5), 4, rng),
    2.5,
    Crayon.blue,
  );
  c.stroke(
    tremble(
      densify([const Pt(300, 400), const Pt(385, 420), const Pt(500, 380)], 5),
      4,
      rng,
    ),
    2.5,
    Crayon.blue,
  );
  c.stroke(
    tremble(
      densify([const Pt(330, 570), const Pt(390, 500), const Pt(460, 575)], 5),
      4,
      rng,
    ),
    2.5,
    Crayon.green,
  );
  // Hair squiggle.
  final hair = <Pt>[
    for (var k = 0; k <= 40; k++)
      Pt(290 + k * 4.5, 150 - 25 * math.sin(k * 0.9).abs()),
  ];
  c.stroke(tremble(hair, 3, rng), 2.5, Crayon.orange);
  return c;
}
