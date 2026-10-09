import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'raster.dart';

/// Encodes the cut-out as an RGBA PNG cropped to the alpha's bounding box
/// (plus a small margin). Longest side is at most 512 because the paper
/// image already is.
Uint8List encodeCutout(RgbImage image, Uint8List alpha, {int margin = 4}) {
  final w = image.width;
  final h = image.height;
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (alpha[y * w + x] == 0) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) {
    // Nothing found: a tiny fully transparent image keeps consumers simple.
    final empty = img.Image(width: 1, height: 1, numChannels: 4);
    return img.encodePng(empty);
  }
  minX = math.max(0, minX - margin);
  minY = math.max(0, minY - margin);
  maxX = math.min(w - 1, maxX + margin);
  maxY = math.min(h - 1, maxY + margin);
  final ow = maxX - minX + 1;
  final oh = maxY - minY + 1;
  final bytes = Uint8List(ow * oh * 4);
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      final si = (y + minY) * w + (x + minX);
      final o = (y * ow + x) * 4;
      final a = alpha[si];
      if (a == 0) continue; // fully transparent black
      bytes[o] = image.data[si * 3];
      bytes[o + 1] = image.data[si * 3 + 1];
      bytes[o + 2] = image.data[si * 3 + 2];
      bytes[o + 3] = a;
    }
  }
  final out = img.Image.fromBytes(
    width: ow,
    height: oh,
    bytes: bytes.buffer,
    numChannels: 4,
  );
  return img.encodePng(out, level: 6);
}
