import 'dart:math' as math;
import 'dart:typed_data';

/// Packed 8-bit RGB image used internally by the analysis pipeline.
///
/// The pipeline works on raw typed arrays instead of `package:image` pixel
/// accessors because it is several times faster and fully deterministic.
class RgbImage {
  RgbImage(this.width, this.height, [Uint8List? data])
    : data = data ?? Uint8List(width * height * 3) {
    assert(this.data.length == width * height * 3);
  }

  final int width;
  final int height;

  /// Row-major RGB triplets.
  final Uint8List data;

  int get pixelCount => width * height;

  /// Rec.601 luma per pixel, 0..255.
  Uint8List luminance() {
    final n = pixelCount;
    final out = Uint8List(n);
    for (var i = 0, j = 0; i < n; i++, j += 3) {
      out[i] = (data[j] * 77 + data[j + 1] * 150 + data[j + 2] * 29) >> 8;
    }
    return out;
  }

  /// Bilinear sample of channel [c] at (x, y); coordinates are clamped.
  double sample(double x, double y, int c) {
    final maxX = width - 1;
    final maxY = height - 1;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x > maxX) x = maxX.toDouble();
    if (y > maxY) y = maxY.toDouble();
    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x0 < maxX ? x0 + 1 : x0;
    final y1 = y0 < maxY ? y0 + 1 : y0;
    final fx = x - x0;
    final fy = y - y0;
    final a = data[(y0 * width + x0) * 3 + c];
    final b = data[(y0 * width + x1) * 3 + c];
    final cc = data[(y1 * width + x0) * 3 + c];
    final d = data[(y1 * width + x1) * 3 + c];
    final top = a + (b - a) * fx;
    final bottom = cc + (d - cc) * fx;
    return top + (bottom - top) * fy;
  }
}

/// Binary mask (values 0 or 1), row-major.
class Mask {
  Mask(this.width, this.height, [Uint8List? bits])
    : bits = bits ?? Uint8List(width * height) {
    assert(this.bits.length == width * height);
  }

  final int width;
  final int height;
  final Uint8List bits;

  int get pixelCount => width * height;

  int count() {
    var c = 0;
    for (final b in bits) {
      c += b;
    }
    return c;
  }

  Mask copy() => Mask(width, height, Uint8List.fromList(bits));

  Mask and(Mask other) {
    final out = Uint8List(bits.length);
    for (var i = 0; i < bits.length; i++) {
      out[i] = bits[i] & other.bits[i];
    }
    return Mask(width, height, out);
  }

  Mask or(Mask other) {
    final out = Uint8List(bits.length);
    for (var i = 0; i < bits.length; i++) {
      out[i] = bits[i] | other.bits[i];
    }
    return Mask(width, height, out);
  }

  Mask not() {
    final out = Uint8List(bits.length);
    for (var i = 0; i < bits.length; i++) {
      out[i] = 1 - bits[i];
    }
    return Mask(width, height, out);
  }

  /// Horizontally mirrored copy.
  Mask mirrored() {
    final out = Uint8List(bits.length);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        out[row + x] = bits[row + width - 1 - x];
      }
    }
    return Mask(width, height, out);
  }

  /// Intersection over union with [other]; 0 when both are empty.
  double iou(Mask other) {
    var inter = 0;
    var union = 0;
    for (var i = 0; i < bits.length; i++) {
      inter += bits[i] & other.bits[i];
      union += bits[i] | other.bits[i];
    }
    return union == 0 ? 0 : inter / union;
  }

  /// Bounding box of set pixels or null when empty.
  IntRect? bounds() {
    var minX = width, minY = height, maxX = -1, maxY = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (bits[row + x] != 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return null;
    return IntRect(minX, minY, maxX, maxY);
  }
}

/// Inclusive integer rectangle.
class IntRect {
  const IntRect(this.left, this.top, this.right, this.bottom);
  final int left;
  final int top;
  final int right;
  final int bottom;
  int get width => right - left + 1;
  int get height => bottom - top + 1;
  int get area => width * height;
}

/// 2D point with double coordinates.
class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double s) => Pt(x * s, y * s);
  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Pt o) => (this - o).length;

  @override
  String toString() => 'Pt(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// HSV of an 8-bit colour. Hue in degrees [0, 360), s and v in [0, 1].
/// Hue is -1 for achromatic colours.
({double h, double s, double v}) rgbToHsv(int r, int g, int b) {
  final mx = math.max(r, math.max(g, b));
  final mn = math.min(r, math.min(g, b));
  final v = mx / 255.0;
  if (mx == 0) return (h: -1, s: 0, v: 0);
  final d = (mx - mn).toDouble();
  final s = d / mx;
  if (d == 0) return (h: -1, s: 0, v: v);
  double h;
  if (mx == r) {
    h = 60 * (((g - b) / d) % 6);
  } else if (mx == g) {
    h = 60 * ((b - r) / d + 2);
  } else {
    h = 60 * ((r - g) / d + 4);
  }
  if (h < 0) h += 360;
  if (h >= 360) h -= 360;
  return (h: h, s: s, v: v);
}

/// Box blur of a single-channel image using an integral image.
Uint8List boxBlur(Uint8List src, int width, int height, int radius) {
  final w1 = width + 1;
  final integral = Int32List(w1 * (height + 1));
  for (var y = 0; y < height; y++) {
    var rowSum = 0;
    for (var x = 0; x < width; x++) {
      rowSum += src[y * width + x];
      integral[(y + 1) * w1 + x + 1] = integral[y * w1 + x + 1] + rowSum;
    }
  }
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final y0 = math.max(0, y - radius);
    final y1 = math.min(height - 1, y + radius) + 1;
    for (var x = 0; x < width; x++) {
      final x0 = math.max(0, x - radius);
      final x1 = math.min(width - 1, x + radius) + 1;
      final sum =
          integral[y1 * w1 + x1] -
          integral[y0 * w1 + x1] -
          integral[y1 * w1 + x0] +
          integral[y0 * w1 + x0];
      out[y * width + x] = sum ~/ ((x1 - x0) * (y1 - y0));
    }
  }
  return out;
}

/// Otsu threshold of a 256-bin histogram. Returns t such that values > t
/// belong to the upper class.
int otsuThreshold(List<int> hist) {
  var total = 0;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    total += hist[i];
    sumAll += i * hist[i];
  }
  if (total == 0) return 127;
  var wB = 0;
  var sumB = 0.0;
  var best = -1.0;
  var bestT = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sumAll - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      bestT = t;
    }
  }
  return bestT;
}

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Linear ramp: 0 at [lo], 1 at [hi], clamped.
double ramp(double v, double lo, double hi) => clamp01((v - lo) / (hi - lo));

/// Hermite smoothstep between [lo] and [hi].
double smoothstep(double v, double lo, double hi) {
  final t = ramp(v, lo, hi);
  return t * t * (3 - 2 * t);
}
