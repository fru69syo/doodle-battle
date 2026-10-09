import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Procedurally drawn doodle (a round crayon-ish monster) with a transparent
/// background, used by the AR debug page and tests so no binary asset is
/// needed.
Uint8List buildSampleCutoutPng({int width = 360, int height = 420}) {
  final im = img.Image(width: width, height: height, numChannels: 4);
  // Fully transparent background.
  img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));

  final cx = width ~/ 2;
  final ink = img.ColorRgba8(40, 40, 40, 255);
  final body = img.ColorRgba8(255, 140, 60, 255);

  // Feet.
  img.fillCircle(
    im,
    x: cx - width ~/ 6,
    y: height - 40,
    radius: width ~/ 10,
    color: ink,
  );
  img.fillCircle(
    im,
    x: cx + width ~/ 6,
    y: height - 40,
    radius: width ~/ 10,
    color: ink,
  );
  // Body with outline.
  final r = (width * 0.42).round();
  final cy = height - r - 30;
  img.fillCircle(im, x: cx, y: cy, radius: r + 6, color: ink);
  img.fillCircle(im, x: cx, y: cy, radius: r, color: body);
  // Ears / horns.
  for (final dx in [-1, 1]) {
    for (var i = 0; i < 40; i++) {
      img.fillCircle(
        im,
        x: cx + dx * (r ~/ 2 + i ~/ 3),
        y: cy - r - i + 10,
        radius: 14 - i ~/ 4,
        color: ink,
      );
    }
  }
  // Eyes.
  for (final dx in [-1, 1]) {
    img.fillCircle(
      im,
      x: cx + dx * r ~/ 3,
      y: cy - r ~/ 5,
      radius: r ~/ 5,
      color: img.ColorRgba8(255, 255, 255, 255),
    );
    img.fillCircle(
      im,
      x: cx + dx * r ~/ 3 + 4,
      y: cy - r ~/ 5 + 4,
      radius: r ~/ 10,
      color: ink,
    );
  }
  // Smile.
  for (var a = -6; a <= 6; a++) {
    img.fillCircle(
      im,
      x: cx + a * r ~/ 14,
      y: cy + r ~/ 3 + (36 - a * a) ~/ -3 + 12,
      radius: 4,
      color: ink,
    );
  }
  return img.encodePng(im);
}
