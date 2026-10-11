import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A 512 px "crayon" doodle with a transparent background: round body,
/// two stubby arms, legs, a pointy antenna and a wobbly outline, coloured
/// with per-pixel noise like a scanned crayon drawing. Used for timings and
/// as the second fighter in the battle prototype (no binary assets needed).
Uint8List buildLargeSampleCutoutPng({
  int size = 512,
  int seed = 7,
  img.ColorRgba8? bodyColor,
}) {
  final rnd = math.Random(seed);
  final im = img.Image(width: size, height: size, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
  final s = size / 512;
  final ink = img.ColorRgba8(35, 30, 45, 255);
  final body = bodyColor ?? img.ColorRgba8(70, 170, 235, 255);

  void blob(double cx, double cy, double r, img.Color c) {
    // Wobbly circle (hand-drawn look).
    for (var y = (cy - r * 1.2).floor(); y <= (cy + r * 1.2).ceil(); y++) {
      for (var x = (cx - r * 1.2).floor(); x <= (cx + r * 1.2).ceil(); x++) {
        if (x < 0 || y < 0 || x >= size || y >= size) continue;
        final a = math.atan2(y - cy, x - cx);
        final rr =
            r * (1 + 0.04 * math.sin(a * 5 + seed) + 0.025 * math.sin(a * 11));
        final dx = x - cx, dy = y - cy;
        if (dx * dx + dy * dy <= rr * rr) im.setPixel(x, y, c);
      }
    }
  }

  void limb(double x0, double y0, double x1, double y1, double r, img.Color c) {
    final n = (math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)) / 2)
        .ceil();
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      img.fillCircle(
        im,
        x: (x0 + (x1 - x0) * t).round(),
        y: (y0 + (y1 - y0) * t).round(),
        radius: r.round(),
        color: c,
      );
    }
  }

  // Outline pass (ink, slightly larger) then fill pass.
  for (final (c, grow) in [(ink, 7.0 * s), (body, 0.0)]) {
    limb(200 * s, 380 * s, 185 * s, 470 * s, 22 * s + grow, c); // legs
    limb(312 * s, 380 * s, 327 * s, 470 * s, 22 * s + grow, c);
    limb(150 * s, 270 * s, 60 * s, 215 * s, 18 * s + grow, c); // arms
    limb(362 * s, 270 * s, 452 * s, 225 * s, 18 * s + grow, c);
    limb(256 * s, 140 * s, 300 * s, 40 * s, 7 * s + grow, c); // antenna
    blob(302 * s, 38 * s, 16 * s + grow, c);
    blob(256 * s, 270 * s, 140 * s + grow, c); // body
  }
  // Face.
  for (final dx in [-50.0, 50.0]) {
    blob((256 + dx) * s, 240 * s, 26 * s, img.ColorRgba8(255, 255, 255, 255));
    blob((262 + dx) * s, 246 * s, 12 * s, ink);
  }
  limb(205 * s, 320 * s, 256 * s, 345 * s, 6 * s, ink);
  limb(256 * s, 345 * s, 307 * s, 320 * s, 6 * s, ink);
  // Crayon grain on opaque pixels.
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = im.getPixel(x, y);
      if (p.a == 0) continue;
      final g = rnd.nextInt(36) - 18;
      im.setPixelRgba(
        x,
        y,
        (p.r + g).clamp(0, 255),
        (p.g + g).clamp(0, 255),
        (p.b + g).clamp(0, 255),
        255,
      );
    }
  }
  return img.encodePng(im);
}
