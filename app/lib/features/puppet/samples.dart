import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Synthetic "crayon" cut-outs (transparent background) covering the
/// shapes kids draw: a person, a stick figure, a limbless blob, a
/// four-legged animal in profile and a car. No binary assets needed.
enum Sample { hero, stick, blob, dog, car }

Uint8List samplePng(Sample s, {int seed = 3}) => switch (s) {
  Sample.hero => _hero(seed),
  Sample.stick => _stick(seed),
  Sample.blob => _blob(seed),
  Sample.dog => _dog(seed),
  Sample.car => _car(seed),
};

class _Pen {
  _Pen(this.w, this.h, this.seed)
    : im = img.Image(width: w, height: h, numChannels: 4) {
    img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
  }
  final int w, h, seed;
  final img.Image im;

  void blob(
    double cx,
    double cy,
    double rx,
    double ry,
    img.Color c, {
    double wob = 0.04,
  }) {
    for (var y = (cy - ry * 1.2).floor(); y <= (cy + ry * 1.2).ceil(); y++) {
      for (var x = (cx - rx * 1.2).floor(); x <= (cx + rx * 1.2).ceil(); x++) {
        if (x < 0 || y < 0 || x >= w || y >= h) continue;
        final a = math.atan2((y - cy) / ry, (x - cx) / rx);
        final rr =
            1 + wob * math.sin(a * 5 + seed) + wob * 0.6 * math.sin(a * 11);
        final dx = (x - cx) / rx, dy = (y - cy) / ry;
        if (dx * dx + dy * dy <= rr * rr) im.setPixel(x, y, c);
      }
    }
  }

  void line(double x0, double y0, double x1, double y1, double r, img.Color c) {
    final n = (math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)) / 1.5)
        .ceil();
    for (var i = 0; i <= n; i++) {
      final t = i / math.max(1, n);
      img.fillCircle(
        im,
        x: (x0 + (x1 - x0) * t).round(),
        y: (y0 + (y1 - y0) * t).round(),
        radius: r.round(),
        color: c,
      );
    }
  }

  void rect(double x0, double y0, double x1, double y1, img.Color c) =>
      img.fillRect(
        im,
        x1: x0.round(),
        y1: y0.round(),
        x2: x1.round(),
        y2: y1.round(),
        color: c,
      );

  Uint8List png() {
    final rnd = math.Random(seed);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        if (p.a == 0) continue;
        final g = rnd.nextInt(30) - 15;
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
}

final _ink = img.ColorRgba8(40, 32, 50, 255);
final _white = img.ColorRgba8(255, 255, 255, 255);

void _eyes(_Pen p, double cx, double cy, double r, {double gap = 1}) {
  for (final s in [-1.0, 1.0]) {
    p.blob(cx + s * r * 1.3 * gap, cy, r, r, _white, wob: 0.02);
    p.blob(
      cx + s * r * 1.3 * gap + r * 0.25,
      cy + r * 0.2,
      r * 0.5,
      r * 0.5,
      _ink,
      wob: 0,
    );
  }
}

Uint8List _hero(int seed) {
  final p = _Pen(360, 460, seed);
  final skin = img.ColorRgba8(255, 205, 160, 255);
  final shirt = img.ColorRgba8(235, 70, 60, 255);
  final pants = img.ColorRgba8(60, 110, 220, 255);
  for (final (c, g) in [(_ink, 6.0), (null, 0.0)]) {
    p.line(150, 330, 135, 430, 18 + g, c ?? pants); // legs
    p.line(210, 330, 228, 430, 18 + g, c ?? pants);
    p.line(120, 215, 40, 170, 14 + g, c ?? shirt); // arms
    p.line(240, 215, 322, 250, 14 + g, c ?? shirt);
    p.blob(180, 260, 70 + g, 85 + g, c ?? shirt); // body
    p.blob(180, 110, 72 + g, 68 + g, c ?? skin); // head
    p.blob(35, 165, 16 + g, 16 + g, c ?? skin); // hands
    p.blob(327, 252, 16 + g, 16 + g, c ?? skin);
    p.blob(128, 438, 26 + g, 14 + g, c ?? _ink); // shoes
    p.blob(236, 438, 26 + g, 14 + g, c ?? _ink);
  }
  _eyes(p, 180, 100, 13);
  p.line(150, 140, 180, 155, 4, _ink);
  p.line(180, 155, 210, 140, 4, _ink);
  // Hair spikes.
  for (var i = 0; i < 5; i++) {
    p.line(
      130.0 + i * 25,
      52,
      122.0 + i * 27,
      22,
      6,
      img.ColorRgba8(110, 60, 30, 255),
    );
  }
  return p.png();
}

Uint8List _stick(int seed) {
  final p = _Pen(300, 420, seed);
  final c = img.ColorRgba8(30, 60, 160, 255);
  p.blob(150, 80, 55, 55, c, wob: 0.02);
  p.blob(150, 80, 47, 47, img.ColorRgba8(255, 250, 235, 255), wob: 0.02);
  _eyes(p, 150, 72, 7);
  p.line(130, 100, 170, 100, 3, c);
  p.line(150, 135, 150, 280, 4, c); // spine
  p.line(150, 175, 60, 140, 4, c); // arms
  p.line(150, 175, 245, 215, 4, c);
  p.line(150, 280, 95, 400, 4, c); // legs
  p.line(150, 280, 210, 400, 4, c);
  return p.png();
}

Uint8List _blob(int seed) {
  final p = _Pen(340, 320, seed);
  p.blob(170, 170, 150, 135, _ink, wob: 0.06);
  p.blob(170, 170, 142, 127, img.ColorRgba8(120, 205, 90, 255), wob: 0.06);
  p.blob(170, 220, 90, 60, img.ColorRgba8(170, 230, 130, 255), wob: 0.05);
  _eyes(p, 170, 130, 24);
  p.line(130, 200, 170, 222, 5, _ink);
  p.line(170, 222, 210, 200, 5, _ink);
  return p.png();
}

Uint8List _dog(int seed) {
  final p = _Pen(520, 330, seed);
  final fur = img.ColorRgba8(225, 160, 70, 255);
  for (final (c, g) in [(_ink, 6.0), (null, 0.0)]) {
    for (final x in [150.0, 205.0, 315.0, 370.0]) {
      p.line(x, 190, x + 4, 300, 16 + g, c ?? fur);
    }
    p.line(110, 160, 25, 95, 10 + g, c ?? fur); // tail
    p.blob(260, 170, 160 + g, 62 + g, c ?? fur); // body
    p.blob(420, 105, 72 + g, 62 + g, c ?? fur); // head
    p.blob(470, 125, 34 + g, 26 + g, c ?? fur); // snout
    p.line(
      392,
      60,
      375,
      150,
      15 + g,
      c ?? img.ColorRgba8(150, 90, 40, 255),
    ); // ear
  }
  p.blob(498, 118, 11, 9, _ink, wob: 0);
  p.blob(440, 92, 10, 10, _white, wob: 0);
  p.blob(443, 94, 5, 5, _ink, wob: 0);
  return p.png();
}

Uint8List _car(int seed) {
  final p = _Pen(500, 300, seed);
  final red = img.ColorRgba8(230, 50, 70, 255);
  p.rect(30, 110, 470, 220, _ink);
  p.rect(36, 116, 464, 214, red);
  p.rect(120, 40, 360, 120, _ink);
  p.rect(126, 46, 354, 116, red);
  p.rect(140, 56, 230, 110, img.ColorRgba8(170, 220, 255, 255));
  p.rect(250, 56, 340, 110, img.ColorRgba8(170, 220, 255, 255));
  for (final x in [120.0, 380.0]) {
    p.blob(x, 225, 50, 50, _ink, wob: 0.01);
    p.blob(x, 225, 22, 22, img.ColorRgba8(200, 200, 200, 255), wob: 0);
  }
  return p.png();
}
