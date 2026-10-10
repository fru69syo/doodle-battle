import 'dart:math' as math;
import 'dart:typed_data';

import 'normalize.dart';
import 'paper_detection.dart';
import 'raster.dart';
import 'segmentation.dart';

/// Low-level measurements for the "is this a photo of a hand drawing on
/// paper?" check (docs/TRUST.md). The decision itself lives in
/// `non_drawing_detector.dart` so it can be unit-tested without images.
class AuthenticityMeasurements {
  const AuthenticityMeasurements({
    required this.backgroundShare,
    required this.backgroundFlatness,
    required this.noiseLevel,
    required this.exactFlatShare,
    required this.lumaPeriodicity,
    required this.chromaPeriodicity,
    required this.periodicPatches,
    required this.patchCount,
  });

  /// Share of the (white-balanced) image that is not part of the drawing:
  /// neither ink nor enclosed by the character's silhouette.
  final double backgroundShare;

  /// Share of those background pixels whose 3×3 neighbourhood is flat (a
  /// sheet of paper, even tinted or dimly lit, is; a scene is not).
  final double backgroundFlatness;

  /// Median camera/paper noise (σ in 8-bit levels, Immerkær's estimator)
  /// over flat, unclipped pixels of native-resolution patches. Phone photos
  /// give ≳0.8 (≳0.25 even after heavy downscaling); digital images
  /// (painted on a tablet, AI-generated, screenshots) give ≈0. -1 when it
  /// could not be measured.
  final double noiseLevel;

  /// Share of unclipped patch pixels whose 3×3 neighbourhood has exactly the
  /// same RGB value: large for flat digital fills, ≈0 once a camera sensor
  /// (noise, demosaicing) was involved. -1 when not measurable.
  final double exactFlatShare;

  /// Strongest 2D periodic lattice (peak / ring median, see
  /// [periodicLattice]) in the luminance of drawing patches: halftone dots of
  /// a printed picture, pixel grid of a photographed screen.
  final double lumaPeriodicity;

  /// Same on the colour-difference channels (R−G, B−G): RGB sub-pixels of a
  /// screen, CMY halftone rosettes.
  final double chromaPeriodicity;

  /// Drawing patches whose luma or chroma lattice passed
  /// [kPeriodicPatchScore] (a print/screen covers the whole picture, so it
  /// repeats across patches; one odd patch does not count).
  final int periodicPatches;

  /// Number of native-resolution drawing patches examined for periodicity.
  final int patchCount;

  static const none = AuthenticityMeasurements(
    backgroundShare: 0,
    backgroundFlatness: 0,
    noiseLevel: -1,
    exactFlatShare: -1,
    lumaPeriodicity: 0,
    chromaPeriodicity: 0,
    periodicPatches: 0,
    patchCount: 0,
  );
}

/// Per-patch lattice score that counts a patch as "periodic".
const double kPeriodicPatchScore = 10;

/// Shortest period (px) searched for dots / pixel grids (close to Nyquist,
/// but above the 2 px Bayer/demosaicing pattern).
const double kMinPeriodPx = 2.4;

/// Longest period searched, as a fraction of the paper's longest side
/// (≈1.3 mm on an A4 sheet). Halftone screens (0.15-0.45 mm) and display
/// pixels are far finer; ruled and squared paper (≥5 mm) are excluded.
const double kMaxPeriodOfPaper = 0.0045;

/// Measures noise and periodic structure on native-resolution patches.
///
/// [paperImage]/[seg] are the (perspective-corrected) paper image and its
/// segmentation; [quad] maps them back into the working image, and
/// `norm.native` holds the original pixels.
AuthenticityMeasurements measureAuthenticity(
  NormalizedImage norm,
  PaperQuad? quad,
  RgbImage paperImage,
  RgbImage balanced,
  Segmentation seg, {
  List<String>? debug,
}) {
  final bg = _background(balanced, seg);
  final native = norm.native;
  if (native == null) {
    return AuthenticityMeasurements(
      backgroundShare: bg.share,
      backgroundFlatness: bg.flatness,
      noiseLevel: -1,
      exactFlatShare: -1,
      lumaPeriodicity: 0,
      chromaPeriodicity: 0,
      periodicPatches: 0,
      patchCount: 0,
    );
  }
  final pw = paperImage.width;
  final ph = paperImage.height;
  final ww = norm.working.width;
  final wh = norm.working.height;
  final ow = native.orientedWidth;
  final oh = native.orientedHeight;
  final map = quad == null ? null : SquareToQuad(quad);
  const span = 1 - 2 * kPaperInset;

  // Paper-image pixel → upright native pixel.
  ({double x, double y}) toNative(double px, double py) {
    double wx, wy;
    if (map == null) {
      wx = px;
      wy = py;
    } else {
      final p = map.map(
        kPaperInset + span * (px + 0.5) / pw,
        kPaperInset + span * (py + 0.5) / ph,
      );
      wx = p.x;
      wy = p.y;
    }
    return (x: (wx + 0.5) * ow / ww - 0.5, y: (wy + 0.5) * oh / wh - 0.5);
  }

  double dist(({double x, double y}) a, ({double x, double y}) b) =>
      math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  // Native pixels per paper pixel around the centre.
  final c0 = toNative(pw / 2, ph / 2);
  final scale = math.max(
    0.25,
    (dist(c0, toNative(pw / 2 + 8, ph / 2)) +
            dist(c0, toNative(pw / 2, ph / 2 + 8))) /
        16,
  );
  final n = scale >= 2.5 ? 128 : 64;
  if (native.width < n || native.height < n) {
    return AuthenticityMeasurements(
      backgroundShare: bg.share,
      backgroundFlatness: bg.flatness,
      noiseLevel: -1,
      exactFlatShare: -1,
      lumaPeriodicity: 0,
      chromaPeriodicity: 0,
      periodicPatches: 0,
      patchCount: 0,
    );
  }
  final maxPeriod = math.min(
    24.0,
    kMaxPeriodOfPaper * math.max(pw, ph) * scale,
  );
  final cell = math.max(6, (n / scale).round());
  final gw = pw ~/ cell;
  final gh = ph ~/ cell;
  if (gw < 1 || gh < 1) {
    return AuthenticityMeasurements(
      backgroundShare: bg.share,
      backgroundFlatness: bg.flatness,
      noiseLevel: -1,
      exactFlatShare: -1,
      lumaPeriodicity: 0,
      chromaPeriodicity: 0,
      periodicPatches: 0,
      patchCount: 0,
    );
  }

  // Per grid cell: share of the character (silhouette ∩ ink), and any ink.
  // The silhouette excludes components glued to the border, so a table
  // cloth or keyboard around the sheet is not mistaken for the drawing.
  final drawFrac = Float64List(gw * gh);
  final anyInk = Uint8List(gw * gh);
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      var c = 0, k = 0;
      for (var y = gy * cell; y < (gy + 1) * cell; y++) {
        final row = y * pw;
        for (var x = gx * cell; x < (gx + 1) * cell; x++) {
          final ink = seg.ink.bits[row + x];
          k |= ink;
          c += ink & seg.silhouette.bits[row + x];
        }
      }
      drawFrac[gy * gw + gx] = c / (cell * cell);
      anyInk[gy * gw + gx] = k;
    }
  }
  // Most drawing first (saturating at half a cell), then nearest the centre
  // (where the subject of a photo usually is).
  double centreDist(int i) {
    final dx = (i % gw + 0.5) / gw - 0.5, dy = (i ~/ gw + 0.5) / gh - 0.5;
    return dx * dx + dy * dy;
  }

  final order = List<int>.generate(gw * gh, (i) => i)
    ..sort((a, b) {
      final d = math
          .min(drawFrac[b], 0.5)
          .compareTo(math.min(drawFrac[a], 0.5));
      if (d != 0) return d;
      final c = centreDist(a).compareTo(centreDist(b));
      return c != 0 ? c : a.compareTo(b);
    });
  final drawCells = <int>[];
  for (final i in order) {
    if (drawFrac[i] < 0.12 || drawCells.length >= 6) break;
    final gx = i % gw, gy = i ~/ gw;
    final near = drawCells.any(
      (j) => (j % gw - gx).abs() <= 1 && (j ~/ gw - gy).abs() <= 1,
    );
    if (!near) drawCells.add(i);
  }
  // Blank paper cells (no ink in the cell or its neighbours), spread out.
  final blank = <int>[];
  for (var gy = 0; gy < gh; gy++) {
    for (var gx = 0; gx < gw; gx++) {
      var any = false;
      for (var dy = -1; dy <= 1 && !any; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final x = gx + dx, y = gy + dy;
          if (x < 0 || y < 0 || x >= gw || y >= gh) continue;
          if (anyInk[y * gw + x] != 0) {
            any = true;
            break;
          }
        }
      }
      if (!any) blank.add(gy * gw + gx);
    }
  }
  final paperCount = math.min(4, blank.length);
  final paperCells = <int>[
    for (var k = 0; k < paperCount; k++)
      blank[(k * blank.length) ~/ paperCount],
  ];

  final noise = <double>[];
  var flatSame = 0, flatAll = 0;
  var lumaBest = 0.0, chromaBest = 0.0;
  var periodic = 0;
  var drawPatches = 0;
  final rgb = [0, 0, 0];
  final packed = Int32List(n * n);
  final luma = Float64List(n * n);
  final cA = Float64List(n * n);
  final cB = Float64List(n * n);
  for (final (i, isDrawing) in [
    for (final i in drawCells) (i, true),
    for (final i in paperCells) (i, false),
  ]) {
    final centre = toNative(
      (i % gw + 0.5) * cell - 0.5,
      (i ~/ gw + 0.5) * cell - 0.5,
    );
    final s = native.storedFromOriented(centre.x, centre.y);
    final x0 = (s.x - n / 2).round().clamp(0, native.width - n);
    final y0 = (s.y - n / 2).round().clamp(0, native.height - n);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        native.rgbAt(x0 + x, y0 + y, rgb);
        final k = y * n + x;
        packed[k] = (rgb[0] << 16) | (rgb[1] << 8) | rgb[2];
        luma[k] = (rgb[0] * 77 + rgb[1] * 150 + rgb[2] * 29) / 256;
        cA[k] = (rgb[0] - rgb[1]).toDouble();
        cB[k] = (rgb[2] - rgb[1]).toDouble();
      }
    }
    final sigma = immerkaerNoise(luma, n);
    if (sigma >= 0) noise.add(sigma);
    final flat = exactFlatCounts(packed, luma, n);
    flatSame += flat.same;
    flatAll += flat.all;
    if (!isDrawing) continue;
    drawPatches++;
    debug?.add('patch @($x0,$y0) n=$n sigma=${sigma.toStringAsFixed(2)}');
    if (maxPeriod < kMinPeriodPx * 1.2) continue;
    final l = periodicLattice(luma, n, maxPeriod: maxPeriod, debug: debug);
    final c = math.max(
      periodicLattice(cA, n, maxPeriod: maxPeriod, debug: debug),
      periodicLattice(cB, n, maxPeriod: maxPeriod, debug: debug),
    );
    lumaBest = math.max(lumaBest, l);
    chromaBest = math.max(chromaBest, c);
    if (math.max(l, c) >= kPeriodicPatchScore) periodic++;
  }
  noise.sort();
  return AuthenticityMeasurements(
    backgroundShare: bg.share,
    backgroundFlatness: bg.flatness,
    noiseLevel: noise.isEmpty ? -1 : noise[noise.length ~/ 2],
    exactFlatShare: flatAll < 200 ? -1 : flatSame / flatAll,
    lumaPeriodicity: lumaBest,
    chromaPeriodicity: chromaBest,
    periodicPatches: periodic,
    patchCount: drawPatches,
  );
}

/// Background share and flatness on the white-balanced paper image.
({double share, double flatness}) _background(
  RgbImage image,
  Segmentation seg,
) {
  final w = image.width, h = image.height;
  final lum = image.luminance();
  var bg = 0, flat = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      if (seg.ink.bits[i] != 0 || seg.silhouette.bits[i] != 0) continue;
      bg++;
      var lo = 255, hi = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final v = lum[i + dy * w + dx];
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
      }
      if (hi - lo <= 6) flat++;
    }
  }
  final total = (w - 2) * (h - 2);
  return (
    share: total <= 0 ? 0 : bg / total,
    flatness: bg == 0 ? 0 : flat / bg,
  );
}

/// Counts unclipped interior pixels (`all`) and those whose 3×3 RGB
/// neighbourhood is exactly uniform (`same`).
({int same, int all}) exactFlatCounts(Int32List rgb, Float64List luma, int n) {
  var same = 0, all = 0;
  for (var y = 1; y < n - 1; y++) {
    for (var x = 1; x < n - 1; x++) {
      final k = y * n + x;
      final l = luma[k];
      if (l < 6 || l > 249) continue;
      all++;
      final v = rgb[k];
      if (rgb[k - 1] == v &&
          rgb[k + 1] == v &&
          rgb[k - n] == v &&
          rgb[k + n] == v &&
          rgb[k - n - 1] == v &&
          rgb[k - n + 1] == v &&
          rgb[k + n - 1] == v &&
          rgb[k + n + 1] == v) {
        same++;
      }
    }
  }
  return (same: same, all: all);
}

/// Immerkær's fast noise estimate (σ, 8-bit levels) over the flat, unclipped
/// interior of an [n]×[n] patch. Edges (strong local contrast) and pixels
/// near black/white clipping are skipped; returns -1 when fewer than 20% of
/// the pixels qualify.
double immerkaerNoise(Float64List p, int n) {
  var sum = 0.0;
  var count = 0;
  for (var y = 1; y < n - 1; y++) {
    for (var x = 1; x < n - 1; x++) {
      final k = y * n + x;
      var lo = 255.0, hi = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final v = p[k + dy * n + dx];
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
      }
      if (lo < 8 || hi > 247 || hi - lo > 24) continue;
      final r =
          p[k - n - 1] -
          2 * p[k - n] +
          p[k - n + 1] -
          2 * p[k - 1] +
          4 * p[k] -
          2 * p[k + 1] +
          p[k + n - 1] -
          2 * p[k + n] +
          p[k + n + 1];
      sum += r.abs();
      count++;
    }
  }
  if (count < 0.2 * (n - 2) * (n - 2)) return -1;
  return math.sqrt(math.pi / 2) * sum / (6 * count);
}

/// Strength of the most prominent isolated *2D lattice* in an [n]×[n]
/// patch with a period between [kMinPeriodPx] and [maxPeriod] px: halftone
/// dot screens and display pixel grids repeat along two non-parallel
/// directions.
///
/// The Hann-windowed spectrum magnitude of each frequency is divided by the
/// median magnitude of its frequency ring, so smooth 1/f content and
/// broadband texture (crayon grain, paper fibre, sensor noise) score ≈3-6.
/// Peaks that belong to a radial streak (a straight edge) or that are
/// harmonics of a coarser pattern are ignored; the score is the weaker of
/// the two best peaks of similar period whose directions differ by ≥55°.
double periodicLattice(
  Float64List patch,
  int n, {
  required double maxPeriod,
  List<String>? debug,
}) {
  final re = Float64List(n * n);
  final im = Float64List(n * n);
  var mean = 0.0;
  for (final v in patch) {
    mean += v;
  }
  mean /= patch.length;
  var energy = 0.0;
  for (var y = 0; y < n; y++) {
    final wy = 0.5 - 0.5 * math.cos(2 * math.pi * (y + 0.5) / n);
    for (var x = 0; x < n; x++) {
      final wx = 0.5 - 0.5 * math.cos(2 * math.pi * (x + 0.5) / n);
      final v = (patch[y * n + x] - mean) * wx * wy;
      re[y * n + x] = v;
      energy += v * v;
    }
  }
  // A flat patch (e.g. a uniform colour fill) has no structure at all.
  if (energy / (n * n) < 0.25) return 0;
  fft2d(re, im, n);
  final mag = Float64List(n * n);
  for (var i = 0; i < n * n; i++) {
    mag[i] = math.sqrt(re[i] * re[i] + im[i] * im[i]);
  }
  double at(int kx, int ky) => mag[(ky % n) * n + (kx % n)];

  final rMin = math.max(2, (n / maxPeriod).ceil());
  final rMax = math.min(n ~/ 2 - 2, (n / kMinPeriodPx).floor());
  if (rMax <= rMin) return 0;
  final rings = List<List<double>>.generate(rMax + 2, (_) => <double>[]);
  for (var ky = -n ~/ 2; ky < n ~/ 2; ky++) {
    for (var kx = 0; kx < n ~/ 2; kx++) {
      final r = math.sqrt(kx * kx + ky * ky).round();
      if (r < rMin - 1 || r > rMax + 1) continue;
      rings[r].add(at(kx, ky));
    }
  }
  final ringMedian = Float64List(rMax + 2);
  for (var r = 0; r < rings.length; r++) {
    final ring = rings[r]..sort();
    ringMedian[r] = ring.isEmpty ? 0 : ring[ring.length ~/ 2];
  }

  // Candidate peaks: local maxima in the half plane kx >= 0.
  final cands = <(double, int, int)>[];
  for (var ky = -n ~/ 2 + 1; ky < n ~/ 2 - 1; ky++) {
    for (var kx = 0; kx < n ~/ 2 - 1; kx++) {
      final r = math.sqrt(kx * kx + ky * ky).round();
      if (r < rMin || r > rMax) continue;
      final m = at(kx, ky);
      final med = ringMedian[r];
      if (med <= 0 || m < 4 * med) continue;
      var isMax = true;
      for (var dy = -1; dy <= 1 && isMax; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if ((dx != 0 || dy != 0) && at(kx + dx, ky + dy) > m) {
            isMax = false;
            break;
          }
        }
      }
      if (isMax) cands.add((m / med, kx, ky));
    }
  }
  cands.sort((a, b) => b.$1.compareTo(a.$1));

  final peaks = <(double, double, double)>[]; // (ratio, radius, angle)
  for (final (ratio, kx, ky) in cands.take(16)) {
    final rr = math.sqrt(kx * kx + ky * ky);
    final m = at(kx, ky);
    // Radial streak (a straight edge): comparable magnitude along the same
    // direction a few rings in/out.
    double along(double f) => at((kx * f).round(), (ky * f).round());
    if (math.max(along((rr - 3) / rr), along((rr + 3) / rr)) > m / 2.5) {
      continue;
    }
    // Harmonic of a coarser periodic pattern (stripes, ruled lines).
    var harmonic = false;
    for (final d in [2, 3, 4]) {
      final hx = (kx / d).round(), hy = (ky / d).round();
      if (hx * hx + hy * hy < 4) continue;
      if (at(hx, hy) > m * 0.6) {
        harmonic = true;
        break;
      }
    }
    if (harmonic) continue;
    peaks.add((ratio, rr, math.atan2(ky.toDouble(), kx.toDouble())));
  }
  var best = 0.0;
  for (var a = 0; a < peaks.length; a++) {
    for (var b = a + 1; b < peaks.length; b++) {
      final (ra, rad, ta) = peaks[a];
      final (rb, rbd, tb) = peaks[b];
      if ((rad - rbd).abs() > 0.15 * math.max(rad, rbd)) continue;
      var d = (ta - tb).abs() % math.pi;
      if (d > math.pi / 2) d = math.pi - d;
      if (d < 55 * math.pi / 180) continue;
      final s = math.min(ra, rb);
      if (s > best) {
        best = s;
        debug?.add(
          'lattice period=${(n / rad).toStringAsFixed(2)}px '
          'score=${s.toStringAsFixed(1)}',
        );
      }
    }
  }
  return best;
}

/// In-place 2D FFT of an [n]×[n] complex array (n a power of two).
void fft2d(Float64List re, Float64List im, int n) {
  final rr = Float64List(n);
  final ii = Float64List(n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      rr[x] = re[y * n + x];
      ii[x] = im[y * n + x];
    }
    fft1d(rr, ii);
    for (var x = 0; x < n; x++) {
      re[y * n + x] = rr[x];
      im[y * n + x] = ii[x];
    }
  }
  for (var x = 0; x < n; x++) {
    for (var y = 0; y < n; y++) {
      rr[y] = re[y * n + x];
      ii[y] = im[y * n + x];
    }
    fft1d(rr, ii);
    for (var y = 0; y < n; y++) {
      re[y * n + x] = rr[y];
      im[y * n + x] = ii[y];
    }
  }
}

/// In-place iterative radix-2 FFT.
void fft1d(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wr = math.cos(ang), wi = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final a = i + k, b = a + len ~/ 2;
        final xr = re[b] * cr - im[b] * ci;
        final xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final t = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = t;
      }
    }
  }
}
