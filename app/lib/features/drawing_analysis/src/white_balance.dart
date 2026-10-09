import 'dart:math' as math;
import 'dart:typed_data';

import 'raster.dart';

/// Result of white balancing.
class WhiteBalanced {
  WhiteBalanced(this.image, this.paperColor, this.validCellShare);

  /// Image with the paper mapped to (approximately) pure white and uneven
  /// illumination flattened.
  final RgbImage image;

  /// Estimated paper colour before correction (r, g, b).
  final List<int> paperColor;

  /// Share of grid cells whose bright pixels looked like paper.
  final double validCellShare;
}

const int _cell = 32;

/// White balance + illumination flattening (SPEC §3.1-1).
///
/// The image is split into ~32px cells. In each cell the brightest ~20% of
/// pixels are assumed to be paper (ink is darker than paper). Cells whose
/// "paper" is saturated or much darker than the brightest cells (fully
/// coloured areas, table, shadows) are treated as unknown and filled from
/// neighbouring cells. The global paper colour fixes the white balance, the
/// smooth per-cell brightness field fixes lighting gradients:
///
///   out = in / (paperRgb * gain(x, y)) * 255
WhiteBalanced whiteBalance(RgbImage src) {
  final w = src.width;
  final h = src.height;
  final gw = math.max(1, (w / _cell).round());
  final gh = math.max(1, (h / _cell).round());
  final cellR = Float64List(gw * gh);
  final cellG = Float64List(gw * gh);
  final cellB = Float64List(gw * gh);
  final cellL = Float64List(gw * gh);
  final lum = src.luminance();
  final d = src.data;

  for (var cy = 0; cy < gh; cy++) {
    final y0 = cy * h ~/ gh, y1 = (cy + 1) * h ~/ gh;
    for (var cx = 0; cx < gw; cx++) {
      final x0 = cx * w ~/ gw, x1 = (cx + 1) * w ~/ gw;
      final hist = Int32List(256);
      var count = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          hist[lum[y * w + x]]++;
          count++;
        }
      }
      // Threshold at the 80th percentile.
      var acc = 0;
      var t = 255;
      for (var v = 255; v >= 0; v--) {
        acc += hist[v];
        if (acc >= 0.2 * count) {
          t = v;
          break;
        }
      }
      var r = 0.0, g = 0.0, b = 0.0, l = 0.0;
      var m = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final i = y * w + x;
          if (lum[i] < t) continue;
          r += d[i * 3];
          g += d[i * 3 + 1];
          b += d[i * 3 + 2];
          l += lum[i];
          m++;
        }
      }
      final k = cy * gw + cx;
      m = math.max(m, 1);
      cellR[k] = r / m;
      cellG[k] = g / m;
      cellB[k] = b / m;
      cellL[k] = l / m;
    }
  }

  // Reference brightness: 90th percentile of cell brightness.
  final sortedL = Float64List.fromList(cellL)..sort();
  final refL = sortedL[((sortedL.length - 1) * 0.9).round()];
  final valid = Uint8List(gw * gh);
  var validCount = 0;
  for (var k = 0; k < gw * gh; k++) {
    final mx = math.max(cellR[k], math.max(cellG[k], cellB[k]));
    final mn = math.min(cellR[k], math.min(cellG[k], cellB[k]));
    final sat = mx <= 0 ? 1.0 : (mx - mn) / mx;
    if (sat < 0.22 && cellL[k] >= 0.6 * refL && cellL[k] > 40) {
      valid[k] = 1;
      validCount++;
    }
  }

  // Global paper colour: median of valid cells (or brightest cells).
  List<int> paper;
  if (validCount >= 1) {
    double med(Float64List v) {
      final xs = <double>[
        for (var k = 0; k < v.length; k++)
          if (valid[k] == 1) v[k],
      ]..sort();
      return xs[xs.length ~/ 2];
    }

    paper = [med(cellR).round(), med(cellG).round(), med(cellB).round()];
  } else {
    paper = [refL.round(), refL.round(), refL.round()];
  }
  final paperL = math.max(
      1.0, (paper[0] * 77 + paper[1] * 150 + paper[2] * 29) / 256.0);

  // Per-cell illumination gain; unknown cells diffuse from known ones.
  final gain = Float64List(gw * gh);
  final known = Uint8List.fromList(valid);
  for (var k = 0; k < gw * gh; k++) {
    gain[k] = known[k] == 1 ? cellL[k] / paperL : 0;
  }
  if (validCount == 0) {
    gain.fillRange(0, gain.length, 1);
    known.fillRange(0, known.length, 1);
  }
  for (var pass = 0; pass < gw + gh; pass++) {
    var filledAny = false;
    final next = Float64List.fromList(gain);
    final nextKnown = Uint8List.fromList(known);
    for (var cy = 0; cy < gh; cy++) {
      for (var cx = 0; cx < gw; cx++) {
        final k = cy * gw + cx;
        if (known[k] == 1) continue;
        var s = 0.0;
        var c = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = cx + dx, ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
            final j = ny * gw + nx;
            if (known[j] == 1) {
              s += gain[j];
              c++;
            }
          }
        }
        if (c > 0) {
          next[k] = s / c;
          nextKnown[k] = 1;
          filledAny = true;
        }
      }
    }
    gain.setAll(0, next);
    known.setAll(0, nextKnown);
    if (!filledAny) break;
  }
  // Smooth the field (two 3x3 box passes) and keep gains in a sane range.
  for (var pass = 0; pass < 2; pass++) {
    final next = Float64List(gw * gh);
    for (var cy = 0; cy < gh; cy++) {
      for (var cx = 0; cx < gw; cx++) {
        var s = 0.0;
        var c = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = cx + dx, ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
            s += gain[ny * gw + nx];
            c++;
          }
        }
        next[cy * gw + cx] = s / c;
      }
    }
    gain.setAll(0, next);
  }
  for (var k = 0; k < gain.length; k++) {
    gain[k] = gain[k].clamp(0.45, 1.6);
  }

  // Apply with bilinear interpolation of the gain field between cell centres.
  final out = RgbImage(w, h);
  final o = out.data;
  final scaleR = 255.0 / math.max(1, paper[0]);
  final scaleG = 255.0 / math.max(1, paper[1]);
  final scaleB = 255.0 / math.max(1, paper[2]);
  for (var y = 0; y < h; y++) {
    final gy = ((y + 0.5) * gh / h - 0.5).clamp(0.0, gh - 1.0);
    final gy0 = gy.floor();
    final gy1 = math.min(gh - 1, gy0 + 1);
    final fy = gy - gy0;
    for (var x = 0; x < w; x++) {
      final gx = ((x + 0.5) * gw / w - 0.5).clamp(0.0, gw - 1.0);
      final gx0 = gx.floor();
      final gx1 = math.min(gw - 1, gx0 + 1);
      final fx = gx - gx0;
      final top = gain[gy0 * gw + gx0] * (1 - fx) + gain[gy0 * gw + gx1] * fx;
      final bot = gain[gy1 * gw + gx0] * (1 - fx) + gain[gy1 * gw + gx1] * fx;
      final inv = 1 / (top * (1 - fy) + bot * fy);
      final i = (y * w + x) * 3;
      o[i] = (d[i] * scaleR * inv).round().clamp(0, 255);
      o[i + 1] = (d[i + 1] * scaleG * inv).round().clamp(0, 255);
      o[i + 2] = (d[i + 2] * scaleB * inv).round().clamp(0, 255);
    }
  }
  return WhiteBalanced(out, paper, validCount / (gw * gh));
}
