/// Keeps the "Before" picture for the Before/After video (docs/VIDEO.md §2):
/// the sheet of paper, perspective-corrected from the original camera photo
/// with the paper corners the analyzer found. Only the paper region is ever
/// kept — never the full camera frame (faces, rooms, hands).
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../data/before_photo.dart';
import '../drawing_analysis/drawing_analyzer.dart'
    show DrawingAnalysisReport, Mask, PaperQuad, kPaperInset;

/// Longest side of the stored photo.
const int kBeforeMaxSide = 1280;

/// JPEG quality of the stored photo.
const int kBeforeJpegQuality = 85;

/// Longest side of the analyzer's working image (`kWorkingSize`).
const int _kAnalyzerWorkingSize = 512;

/// Without a detected sheet the photo is kept only when the analyzer is
/// this sure the background is paper (`DrawingFeatures.paperLikeness`).
const double kMinPaperLikenessWithoutQuad = 0.5;

/// Everything the extractor needs from one analysis, in plain data so it can
/// cross an isolate boundary.
class BeforePhotoInput {
  const BeforePhotoInput({
    required this.quad,
    required this.paperWidth,
    required this.paperHeight,
    required this.inkBox,
    required this.cutoutWidth,
    required this.cutoutHeight,
    required this.paperLikeness,
  });

  /// Paper corners (TL, TR, BR, BL; x, y pairs) in the analyzer's working
  /// image, or null when no sheet was detected.
  final List<double>? quad;

  /// Size of the analyzer's paper image (where [inkBox] lives).
  final int paperWidth;
  final int paperHeight;

  /// Bounding box of the character's silhouette in the paper image
  /// (left, top, right, bottom; inclusive), or null when empty.
  final List<int>? inkBox;

  /// Size of the cut-out PNG (same pixel scale as the paper image).
  final int cutoutWidth;
  final int cutoutHeight;

  final double paperLikeness;

  factory BeforePhotoInput.fromReport(DrawingAnalysisReport report) {
    final q = report.paperQuad;
    final png = report.result.cutoutPng;
    final (cw, ch) = pngSize(png) ?? (0, 0);
    return BeforePhotoInput(
      quad: q == null ? null : _quadList(q),
      paperWidth: report.silhouette.width,
      paperHeight: report.silhouette.height,
      inkBox: maskBox(report.silhouette),
      cutoutWidth: cw,
      cutoutHeight: ch,
      paperLikeness: report.features.paperLikeness,
    );
  }

  static List<double> _quadList(PaperQuad q) => [
    for (final p in q.corners) ...[p.x, p.y],
  ];
}

/// Runs [extractBeforePhotoSync] off the UI thread. Never throws: any
/// failure means "no Before photo" (the video then uses the fallback).
Future<BeforePhoto?> extractBeforePhoto(
  Uint8List original,
  BeforePhotoInput input,
) async {
  try {
    return await Isolate.run(() => extractBeforePhotoSync(original, input));
  } on Object {
    return null;
  }
}

/// Builds the Before photo from the [original] camera image, or null when
/// nothing safe can be kept (no sheet and not clearly paper).
BeforePhoto? extractBeforePhotoSync(
  Uint8List original,
  BeforePhotoInput input,
) {
  final decoded = img.decodeImage(original);
  if (decoded == null || decoded.width < 2 || decoded.height < 2) return null;
  final oriented = img.bakeOrientation(decoded);
  final w = oriented.width;
  final h = oriented.height;
  final rgb = oriented.getBytes(order: img.ChannelOrder.rgb);
  if (rgb.length != w * h * 3) return null;

  // Analyzer working image: longest side 512, same framing.
  final longest = math.max(w, h);
  final ww = math.max(1, (w * _kAnalyzerWorkingSize / longest).round());
  final wh = math.max(1, (h * _kAnalyzerWorkingSize / longest).round());
  final sx = w / ww;
  final sy = h / wh;

  final quad = input.quad;
  final _Warp warp;
  final int outW;
  final int outH;
  NormRect? ink;
  if (quad != null) {
    // Same geometry as the analyzer's warpPaper, sampled from the full
    // resolution photo.
    final c = [
      for (var i = 0; i < 4; i++)
        math.Point(
          (quad[i * 2] + 0.5) * sx - 0.5,
          (quad[i * 2 + 1] + 0.5) * sy - 0.5,
        ),
    ];
    final top = c[0].distanceTo(c[1]);
    final bottom = c[3].distanceTo(c[2]);
    final left = c[0].distanceTo(c[3]);
    final right = c[1].distanceTo(c[2]);
    final pw = (top + bottom) / 2 * (1 - 2 * kPaperInset);
    final ph = (left + right) / 2 * (1 - 2 * kPaperInset);
    final s = math.min(1.0, kBeforeMaxSide / math.max(pw, ph));
    outW = math.max(8, (pw * s).round());
    outH = math.max(8, (ph * s).round());
    final map = _SquareToQuad(c);
    const span = 1 - 2 * kPaperInset;
    warp = (x, y) => map.map(
      kPaperInset + span * (x + 0.5) / outW,
      kPaperInset + span * (y + 0.5) / outH,
    );
    ink = cutoutRectOnPaper(input);
  } else {
    // No sheet found: the paper fills the frame (or detection failed). Keep
    // only the area around the drawing, and only when it is clearly paper.
    final box = input.inkBox;
    if (box == null || input.paperLikeness < kMinPaperLikenessWithoutQuad) {
      return null;
    }
    // Paper image == working image here.
    final bw = box[2] - box[0] + 1;
    final bh = box[3] - box[1] + 1;
    final margin = math.max(24, (0.2 * math.max(bw, bh)).round());
    final l = math.max(0, box[0] - margin);
    final t = math.max(0, box[1] - margin);
    final r = math.min(input.paperWidth - 1, box[2] + margin);
    final b = math.min(input.paperHeight - 1, box[3] + margin);
    final cropW = (r - l + 1) * sx;
    final cropH = (b - t + 1) * sy;
    final s = math.min(1.0, kBeforeMaxSide / math.max(cropW, cropH));
    outW = math.max(8, (cropW * s).round());
    outH = math.max(8, (cropH * s).round());
    final ox = l * sx;
    final oy = t * sy;
    warp = (x, y) => math.Point(
      ox + (x + 0.5) * cropW / outW - 0.5,
      oy + (y + 0.5) * cropH / outH - 0.5,
    );
    final onPaper = cutoutRectOnPaper(input);
    if (onPaper != null) {
      final pw = input.paperWidth.toDouble();
      final ph = input.paperHeight.toDouble();
      final cw = (r - l + 1) / pw;
      final chh = (b - t + 1) / ph;
      ink = NormRect(
        (onPaper.left - l / pw) / cw,
        (onPaper.top - t / ph) / chh,
        onPaper.width / cw,
        onPaper.height / chh,
      );
    }
  }

  final out = Uint8List(outW * outH * 3);
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final p = warp(x, y);
      _sample(
        rgb,
        w,
        h,
        p.x.toDouble(),
        p.y.toDouble(),
        out,
        (y * outW + x) * 3,
      );
    }
  }
  _gentleWhiteBalance(out);
  final image = img.Image.fromBytes(
    width: outW,
    height: outH,
    bytes: out.buffer,
    numChannels: 3,
  );
  return BeforePhoto(
    jpeg: img.encodeJpg(image, quality: kBeforeJpegQuality),
    inkRect: ink,
  );
}

/// Where the cut-out PNG sits on the analyzer's paper image, normalised:
/// centred on the silhouette, sized like the PNG (same pixel scale).
NormRect? cutoutRectOnPaper(BeforePhotoInput input) {
  final box = input.inkBox;
  if (box == null || input.cutoutWidth <= 1 || input.cutoutHeight <= 1) {
    return null;
  }
  final pw = input.paperWidth.toDouble();
  final ph = input.paperHeight.toDouble();
  final cx = (box[0] + box[2] + 1) / 2 / pw;
  final cy = (box[1] + box[3] + 1) / 2 / ph;
  final nw = input.cutoutWidth / pw;
  final nh = input.cutoutHeight / ph;
  return NormRect(cx - nw / 2, cy - nh / 2, nw, nh);
}

/// Bounding box (l, t, r, b) of the set pixels of [m], or null when empty.
List<int>? maskBox(Mask m) {
  var l = m.width, t = m.height, r = -1, b = -1;
  for (var y = 0; y < m.height; y++) {
    final row = y * m.width;
    for (var x = 0; x < m.width; x++) {
      if (m.bits[row + x] == 0) continue;
      if (x < l) l = x;
      if (x > r) r = x;
      if (y < t) t = y;
      if (y > b) b = y;
    }
  }
  return r < 0 ? null : [l, t, r, b];
}

/// Width and height from a PNG header, or null.
(int, int)? pngSize(Uint8List png) {
  if (png.length < 24 || png[0] != 0x89 || png[1] != 0x50) return null;
  final d = ByteData.sublistView(png);
  return (d.getUint32(16), d.getUint32(20));
}

typedef _Warp = math.Point<double> Function(int x, int y);

void _sample(
  Uint8List src,
  int w,
  int h,
  double x,
  double y,
  Uint8List out,
  int o,
) {
  if (x < 0) x = 0;
  if (y < 0) y = 0;
  if (x > w - 1) x = (w - 1).toDouble();
  if (y > h - 1) y = (h - 1).toDouble();
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = math.min(x0 + 1, w - 1);
  final y1 = math.min(y0 + 1, h - 1);
  final fx = x - x0;
  final fy = y - y0;
  final i00 = (y0 * w + x0) * 3;
  final i10 = (y0 * w + x1) * 3;
  final i01 = (y1 * w + x0) * 3;
  final i11 = (y1 * w + x1) * 3;
  for (var c = 0; c < 3; c++) {
    final top = src[i00 + c] + (src[i10 + c] - src[i00 + c]) * fx;
    final bot = src[i01 + c] + (src[i11 + c] - src[i01 + c]) * fx;
    out[o + c] = (top + (bot - top) * fy).round().clamp(0, 255);
  }
}

/// Global per-channel gain so the paper (the bright end of the histogram)
/// looks white; never darkens and never more than ×1.6.
void _gentleWhiteBalance(Uint8List rgb) {
  final n = rgb.length ~/ 3;
  if (n == 0) return;
  final gains = List<double>.filled(3, 1);
  for (var c = 0; c < 3; c++) {
    final hist = Int32List(256);
    for (var i = c; i < rgb.length; i += 3) {
      hist[rgb[i]]++;
    }
    // 90th percentile ≈ paper on a drawing (ink covers well under 10%...
    // or the paper is still the brightest large group).
    var acc = 0;
    var p = 255;
    for (var v = 255; v >= 0; v--) {
      acc += hist[v];
      if (acc >= n * 0.10) {
        p = v;
        break;
      }
    }
    gains[c] = (248 / math.max(p, 1)).clamp(1.0, 1.6);
  }
  if (gains.every((g) => g == 1)) return;
  final lut = [
    for (var c = 0; c < 3; c++)
      Uint8List.fromList([
        for (var v = 0; v < 256; v++) (v * gains[c]).round().clamp(0, 255),
      ]),
  ];
  for (var i = 0; i < rgb.length; i += 3) {
    rgb[i] = lut[0][rgb[i]];
    rgb[i + 1] = lut[1][rgb[i + 1]];
    rgb[i + 2] = lut[2][rgb[i + 2]];
  }
}

/// Projective map of the unit square onto a quad (TL, TR, BR, BL).
class _SquareToQuad {
  factory _SquareToQuad(List<math.Point<double>> q) {
    final x0 = q[0].x, y0 = q[0].y;
    final x1 = q[1].x, y1 = q[1].y;
    final x2 = q[2].x, y2 = q[2].y;
    final x3 = q[3].x, y3 = q[3].y;
    final sx = x0 - x1 + x2 - x3;
    final sy = y0 - y1 + y2 - y3;
    if (sx.abs() < 1e-9 && sy.abs() < 1e-9) {
      return _SquareToQuad._(x1 - x0, x3 - x0, x0, y1 - y0, y3 - y0, y0, 0, 0);
    }
    final dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
    final den = dx1 * dy2 - dx2 * dy1;
    final g = (sx * dy2 - dx2 * sy) / den;
    final h = (dx1 * sy - sx * dy1) / den;
    return _SquareToQuad._(
      x1 - x0 + g * x1,
      x3 - x0 + h * x3,
      x0,
      y1 - y0 + g * y1,
      y3 - y0 + h * y3,
      y0,
      g,
      h,
    );
  }

  _SquareToQuad._(
    this.a,
    this.b,
    this.c,
    this.d,
    this.e,
    this.f,
    this.g,
    this.h,
  );

  final double a, b, c, d, e, f, g, h;

  math.Point<double> map(double u, double v) {
    final den = g * u + h * v + 1;
    return math.Point((a * u + b * v + c) / den, (d * u + e * v + f) / den);
  }
}
