import 'dart:math' as math;
import 'dart:typed_data';

import 'raster.dart' show Mask;

/// Sobel gradients plus structure-tensor coherence of a luminance image.
///
/// Coherence (0..1) tells whether the edges around a pixel share one
/// orientation (a clean line or shape border → ~1) or point every which way
/// (crayon grain, scribbles, noise → low). It is the key signal that
/// separates "clean, controlled" strokes from textured kid crayon.
class EdgeField {
  EdgeField._(this.width, this.height, this.magnitude, this.coherence);

  final int width;
  final int height;

  /// Sobel gradient magnitude (|gx| + |gy|, 0..~2040).
  final Float32List magnitude;

  /// Structure-tensor coherence over a 5x5 window.
  final Float32List coherence;

  factory EdgeField.compute(Uint8List lum, int w, int h) {
    final n = w * h;
    final gx = Float32List(n);
    final gy = Float32List(n);
    final mag = Float32List(n);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final a = lum[i - w - 1], b = lum[i - w], c = lum[i - w + 1];
        final d = lum[i - 1], f = lum[i + 1];
        final g = lum[i + w - 1], hh = lum[i + w], k = lum[i + w + 1];
        final sx = (c + 2 * f + k) - (a + 2 * d + g);
        final sy = (g + 2 * hh + k) - (a + 2 * b + c);
        gx[i] = sx.toDouble();
        gy[i] = sy.toDouble();
        mag[i] = (sx.abs() + sy.abs()).toDouble();
      }
    }
    // Structure tensor components, box-summed with a 5x5 window via
    // separable running sums.
    final j11 = Float64List(n), j22 = Float64List(n), j12 = Float64List(n);
    for (var i = 0; i < n; i++) {
      j11[i] = gx[i] * gx[i];
      j22[i] = gy[i] * gy[i];
      j12[i] = gx[i] * gy[i];
    }
    final s11 = _boxSum(j11, w, h, 2);
    final s22 = _boxSum(j22, w, h, 2);
    final s12 = _boxSum(j12, w, h, 2);
    final coh = Float32List(n);
    for (var i = 0; i < n; i++) {
      final tr = s11[i] + s22[i];
      if (tr <= 1e-6) continue;
      final diff = s11[i] - s22[i];
      coh[i] = math.sqrt(diff * diff + 4 * s12[i] * s12[i]) / tr;
    }
    return EdgeField._(w, h, mag, coh);
  }
}

Float64List _boxSum(Float64List src, int w, int h, int r) {
  final tmp = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    var s = 0.0;
    final row = y * w;
    for (var x = -r; x <= r; x++) {
      if (x >= 0 && x < w) s += src[row + x];
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = s;
      final add = x + r + 1;
      final rem = x - r;
      if (add < w) s += src[row + add];
      if (rem >= 0) s -= src[row + rem];
    }
  }
  final out = Float64List(w * h);
  for (var x = 0; x < w; x++) {
    var s = 0.0;
    for (var y = -r; y <= r; y++) {
      if (y >= 0 && y < h) s += tmp[y * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = s;
      final add = y + r + 1;
      final rem = y - r;
      if (add < h) s += tmp[add * w + x];
      if (rem >= 0) s -= tmp[rem * w + x];
    }
  }
  return out;
}

/// Mean coherence and the density of coherent edge pixels inside [region].
({double meanCoherence, int edgePixels, int coherentEdgePixels})
    edgeStats(EdgeField f, Mask region,
        {double minMagnitude = 60, double coherentAbove = 0.75}) {
  var sum = 0.0;
  var edges = 0;
  var coherent = 0;
  for (var i = 0; i < f.magnitude.length; i++) {
    if (region.bits[i] == 0 || f.magnitude[i] < minMagnitude) continue;
    edges++;
    final c = f.coherence[i];
    sum += c;
    if (c >= coherentAbove) coherent++;
  }
  return (
    meanCoherence: edges == 0 ? 0.0 : sum / edges,
    edgePixels: edges,
    coherentEdgePixels: coherent,
  );
}
