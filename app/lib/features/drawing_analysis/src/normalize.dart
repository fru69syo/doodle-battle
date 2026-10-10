import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import 'raster.dart';

/// Longest side of the normalised working image (SPEC §3.1-1).
const int kWorkingSize = 512;

/// Longest side of the higher-resolution copy used to sample the
/// perspective-corrected paper crop, so the crop stays sharp.
const int kHiResSize = 1024;

/// Decoded input in a canonical form.
class NormalizedImage {
  NormalizedImage({
    required this.working,
    required this.hiRes,
    required this.hash,
    this.native,
  });

  /// Longest side exactly [kWorkingSize]; orientation applied; alpha
  /// composited onto white.
  final RgbImage working;

  /// Same framing as [working] but up to [kHiResSize] on the longest side.
  final RgbImage hiRes;

  /// SHA-256 (hex) over the working image's dimensions and RGB bytes.
  final String hash;

  /// Pixels of [hiRes] per pixel of [working].
  double get hiResScale => hiRes.width / working.width;

  /// The decoded input at its original resolution (before orientation), kept
  /// for the authenticity checks that need fine detail (halftone dots, screen
  /// pixel grids, sensor noise). Null for images built in tests.
  final NativePixels? native;
}

/// Decoded pixels at the input's native resolution, in stored (not
/// EXIF-rotated) orientation.
class NativePixels {
  NativePixels({
    required this.raw,
    required this.channels,
    required this.width,
    required this.height,
    required this.orientation,
  });

  /// Interleaved 8-bit samples, [channels] (1-4) per pixel.
  final Uint8List raw;
  final int channels;
  final int width;
  final int height;

  /// EXIF orientation (1-8) that turns the stored image upright.
  final int orientation;

  /// Width/height after applying [orientation].
  int get orientedWidth => orientation >= 5 ? height : width;
  int get orientedHeight => orientation >= 5 ? width : height;

  /// Maps a point given in upright (oriented) pixel coordinates to stored
  /// pixel coordinates.
  ({double x, double y}) storedFromOriented(double x, double y) {
    final w = width - 1.0;
    final h = height - 1.0;
    switch (orientation) {
      case 2:
        return (x: w - x, y: y);
      case 3:
        return (x: w - x, y: h - y);
      case 4:
        return (x: x, y: h - y);
      case 5:
        return (x: y, y: x);
      case 6:
        return (x: y, y: h - x);
      case 7:
        return (x: w - y, y: h - x);
      case 8:
        return (x: w - y, y: x);
      default:
        return (x: x, y: y);
    }
  }

  /// RGB of the stored pixel (x, y) (alpha composited onto white).
  void rgbAt(int x, int y, List<int> out) {
    final j = (y * width + x) * channels;
    final r = raw[j];
    if (channels <= 2) {
      final a = channels == 2 ? raw[j + 1] : 255;
      final v = a == 255 ? r : (r * a + 255 * (255 - a)) ~/ 255;
      out[0] = v;
      out[1] = v;
      out[2] = v;
      return;
    }
    final a = channels == 4 ? raw[j + 3] : 255;
    if (a == 255) {
      out[0] = r;
      out[1] = raw[j + 1];
      out[2] = raw[j + 2];
    } else {
      out[0] = (r * a + 255 * (255 - a)) ~/ 255;
      out[1] = (raw[j + 1] * a + 255 * (255 - a)) ~/ 255;
      out[2] = (raw[j + 2] * a + 255 * (255 - a)) ~/ 255;
    }
  }
}

/// Thrown when the input bytes cannot be decoded as an image.
class UndecodableImageException implements Exception {
  const UndecodableImageException();
  @override
  String toString() => 'UndecodableImageException: unsupported image data';
}

/// Decodes [bytes], applies EXIF orientation, flattens alpha onto white and
/// resamples to the canonical working sizes.
NormalizedImage normalizeImage(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    decoded = null;
  }
  if (decoded == null || decoded.width < 2 || decoded.height < 2) {
    throw const UndecodableImageException();
  }
  final orientation = decoded.exif.imageIfd.orientation ?? 1;
  final px = _rawPixels(decoded);
  final srcW = decoded.width;
  final srcH = decoded.height;

  // Resample before rotating (cheaper); rotation keeps the longest side.
  final orientedLongest = math.max(srcW, srcH);
  RgbImage hi;
  if (orientedLongest > kHiResSize) {
    final s = kHiResSize / orientedLongest;
    hi = _areaDownscale(
      px.raw,
      px.nc,
      srcW,
      srcH,
      math.max(1, (srcW * s).round()),
      math.max(1, (srcH * s).round()),
    );
  } else {
    hi = _areaDownscale(px.raw, px.nc, srcW, srcH, srcW, srcH);
  }
  hi = _applyOrientation(hi, orientation);

  final longest = math.max(hi.width, hi.height);
  final s = kWorkingSize / longest;
  final ww = math.max(1, (hi.width * s).round());
  final wh = math.max(1, (hi.height * s).round());
  final RgbImage working;
  if (longest > kWorkingSize) {
    working = _areaDownscale(hi.data, 3, hi.width, hi.height, ww, wh);
  } else if (longest < kWorkingSize) {
    working = _bilinearResize(hi, ww, wh);
    hi = working;
  } else {
    working = hi;
  }

  final hashed = Uint8List(8 + working.data.length);
  hashed.buffer.asByteData()
    ..setUint32(0, working.width)
    ..setUint32(4, working.height);
  hashed.setRange(8, hashed.length, working.data);
  final digest = sha256.convert(hashed);
  return NormalizedImage(
    working: working,
    hiRes: hi,
    hash: digest.toString(),
    native: NativePixels(
      raw: px.raw,
      channels: px.nc,
      width: srcW,
      height: srcH,
      orientation: orientation.clamp(1, 8),
    ),
  );
}

/// Raw interleaved 8-bit pixels of [image] and their channel count (1-4).
/// Uses the decoder's buffer directly when possible (no copy).
({Uint8List raw, int nc}) _rawPixels(img.Image image) {
  var src = image;
  if (src.hasPalette || src.format != img.Format.uint8) {
    src = src.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
  }
  final nc = src.numChannels;
  final raw = src.toUint8List();
  if (nc >= 1 && nc <= 4 && raw.length == src.width * src.height * nc) {
    return (raw: raw, nc: nc);
  }
  // Unusual layouts (row padding): slow but safe path.
  final out = Uint8List(src.width * src.height * 4);
  var o = 0;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      out[o++] = p.r.toInt();
      out[o++] = p.g.toInt();
      out[o++] = p.b.toInt();
      out[o++] = nc == 2 || nc == 4 ? p.a.toInt() : 255;
    }
  }
  return (raw: out, nc: 4);
}

/// Area-averaging resample of interleaved pixels with [nc] channels to RGB
/// (alpha composited onto white). With dw == sw and dh == sh it is a plain
/// format conversion.
RgbImage _areaDownscale(Uint8List raw, int nc, int sw, int sh, int dw, int dh) {
  final xmap = Int32List(sw);
  for (var x = 0; x < sw; x++) {
    xmap[x] = math.min(dw - 1, x * dw ~/ sw);
  }
  final sums = Float64List(dw * dh * 3);
  final counts = Int32List(dw * dh);
  for (var y = 0; y < sh; y++) {
    final oy = math.min(dh - 1, y * dh ~/ sh);
    final orow = oy * dw;
    var j = y * sw * nc;
    if (nc == 3) {
      for (var x = 0; x < sw; x++, j += 3) {
        final o = orow + xmap[x];
        final o3 = o * 3;
        sums[o3] += raw[j];
        sums[o3 + 1] += raw[j + 1];
        sums[o3 + 2] += raw[j + 2];
        counts[o]++;
      }
      continue;
    }
    for (var x = 0; x < sw; x++, j += nc) {
      final o = orow + xmap[x];
      final o3 = o * 3;
      final gray = nc <= 2;
      final r = raw[j];
      final g = gray ? r : raw[j + 1];
      final b = gray ? r : raw[j + 2];
      final a = nc == 2 ? raw[j + 1] : (nc == 4 ? raw[j + 3] : 255);
      if (a == 255) {
        sums[o3] += r;
        sums[o3 + 1] += g;
        sums[o3 + 2] += b;
      } else {
        final fa = a / 255.0;
        final white = 255 * (1 - fa);
        sums[o3] += r * fa + white;
        sums[o3 + 1] += g * fa + white;
        sums[o3 + 2] += b * fa + white;
      }
      counts[o]++;
    }
  }
  final out = RgbImage(dw, dh);
  for (var i = 0; i < dw * dh; i++) {
    final n = counts[i] == 0 ? 1 : counts[i];
    for (var c = 0; c < 3; c++) {
      out.data[i * 3 + c] = (sums[i * 3 + c] / n).round().clamp(0, 255);
    }
  }
  return out;
}

RgbImage _bilinearResize(RgbImage src, int dw, int dh) {
  final out = RgbImage(dw, dh);
  final sx = src.width / dw;
  final sy = src.height / dh;
  for (var y = 0; y < dh; y++) {
    final fy = (y + 0.5) * sy - 0.5;
    for (var x = 0; x < dw; x++) {
      final fx = (x + 0.5) * sx - 0.5;
      final o = (y * dw + x) * 3;
      for (var c = 0; c < 3; c++) {
        out.data[o + c] = src.sample(fx, fy, c).round().clamp(0, 255);
      }
    }
  }
  return out;
}

/// Applies EXIF orientation (1-8) so the image is upright.
RgbImage _applyOrientation(RgbImage src, int orientation) {
  if (orientation < 2 || orientation > 8) return src;
  final w = src.width;
  final h = src.height;
  final swap = orientation >= 5;
  final ow = swap ? h : w;
  final oh = swap ? w : h;
  final out = RgbImage(ow, oh);
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      // Source coordinate for destination (x, y).
      int sx, sy;
      switch (orientation) {
        case 2:
          sx = w - 1 - x;
          sy = y;
        case 3:
          sx = w - 1 - x;
          sy = h - 1 - y;
        case 4:
          sx = x;
          sy = h - 1 - y;
        case 5:
          sx = y;
          sy = x;
        case 6:
          sx = y;
          sy = h - 1 - x;
        case 7:
          sx = w - 1 - y;
          sy = h - 1 - x;
        default: // 8
          sx = w - 1 - y;
          sy = x;
      }
      final si = (sy * w + sx) * 3;
      final di = (y * ow + x) * 3;
      out.data[di] = src.data[si];
      out.data[di + 1] = src.data[si + 1];
      out.data[di + 2] = src.data[si + 2];
    }
  }
  return out;
}
