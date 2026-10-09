import 'dart:math' as math;
import 'dart:typed_data';

import '../drawing_features.dart';
import 'edge_field.dart';
import 'morphology.dart';
import 'raster.dart';
import 'segmentation.dart';

const int _hueBins = 24; // 15° per bin

/// Computes [DrawingFeatures] from the white-balanced paper image and its
/// segmentation.
DrawingFeatures extractFeatures(
  RgbImage image,
  Segmentation seg, {
  required double paperLike,
  required bool paperDetected,
}) {
  final w = image.width;
  final h = image.height;
  final n = w * h;
  final ink = seg.ink;
  final sil = seg.silhouette;
  final inkArea = ink.count();
  final silArea = sil.count();

  if (inkArea == 0 || silArea == 0) {
    return DrawingFeatures(
      inkCoverage: 0,
      silhouetteCoverage: 0,
      bboxCoverage: 0,
      colorCount: 0,
      achromaticCount: 0,
      dominantHue: -1,
      dominantHueShare: 0,
      balancedHueCount: 0,
      chromaticShare: 0,
      redShare: 0,
      darkness: 0,
      strokeSmoothness: 0,
      edgeCoherence: 0,
      contourRoughness: 0,
      wobble: 0,
      symmetry: 0,
      shadingLevel: 0,
      gradientShare: 0,
      detailDensity: 0,
      coherentEdgeDensity: 0,
      fineLineRatio: 0,
      spikiness: 0,
      convexityDefects: 0,
      roundness: 0,
      solidity: 1,
      aspectRatio: 1,
      elongation: 1,
      lineThickness: 0,
      uniqueColors: 0,
      huePeakedness: 1,
      paperLikeness: paperLike,
      photoLikelihood: clamp01(1 - paperLike),
      paperDetected: paperDetected,
    );
  }

  final colour = _colourStats(image, ink, inkArea);
  final lum = image.luminance();
  final shading = _shading(ink, boxBlur(lum, w, h, 2), colour.pixelCluster);
  final shape = _shapeStats(sil);
  final b = sil.bounds()!;
  final edges = EdgeField.compute(lum, w, h);
  final es = edgeStats(edges, dilate(sil, 2));
  final contour = _contourStats(seg.inkLabels, ink);
  // Clean edges (coherence), little outline jitter, few wobbles.
  final smoothness = clamp01(
    0.5 * ramp(es.meanCoherence, 0.55, 0.85) +
        0.2 / (1 + math.pow(contour.roughness / 0.45, 2)) +
        0.3 * (1 - ramp(contour.wobble, 0.4, 2.5)),
  );
  final symmetry = 0.5 * _mirrorIoU(sil) + 0.5 * _mirrorIoU(dilate(ink, 2));
  final inkDt = chamferDistance(ink, target: 0);
  final thickness = _lineThickness(ink, inkDt);
  final coherentDensity = es.coherentEdgePixels / silArea;
  // Thin-line length relative to the character's size: how many "widths"
  // of fine line work were put into it.
  final fineLines =
      _thinLinePixels(lum, edges, dilate(sil, 2)) / 2 / math.sqrt(b.area);
  final smallParts = seg.inkLabels.components
      .where((c) => c.area < 0.004 * n)
      .length;
  final detail = clamp01(
    0.75 * ramp(fineLines, 4, 14) + 0.25 * ramp(smallParts.toDouble(), 3, 15),
  );

  final silCov = silArea / n;
  // Photographs / digital art: no paper, full frame, smooth gradients, many
  // colours spread continuously over the hue circle.
  final photo = clamp01(
    0.35 * (1 - paperLike) +
        0.20 * ramp(silCov, 0.5, 0.9) +
        0.20 * ramp(shading.gradientShare, 0.1, 0.4) +
        0.10 * ramp(colour.uniqueColors.toDouble(), 150, 500) +
        0.15 * ramp(1 - colour.peakedness, 0.1, 0.4),
  );

  return DrawingFeatures(
    inkCoverage: inkArea / n,
    silhouetteCoverage: silCov,
    bboxCoverage: b.area / n,
    colorCount: colour.colorCount,
    achromaticCount: colour.achromaticCount,
    dominantHue: colour.dominantHue,
    dominantHueShare: colour.dominantShare,
    balancedHueCount: colour.balancedCount,
    chromaticShare: colour.chromaticShare,
    redShare: colour.redShare,
    darkness: colour.darkness,
    strokeSmoothness: smoothness,
    edgeCoherence: es.meanCoherence,
    contourRoughness: contour.roughness,
    wobble: contour.wobble,
    symmetry: symmetry,
    shadingLevel: shading.level,
    gradientShare: shading.gradientShare,
    detailDensity: detail,
    coherentEdgeDensity: coherentDensity,
    fineLineRatio: fineLines,
    spikiness: shape.spikiness,
    convexityDefects: shape.defects,
    roundness: shape.roundness,
    solidity: shape.solidity,
    aspectRatio: b.width / b.height,
    elongation: shape.elongation,
    lineThickness: thickness,
    uniqueColors: colour.uniqueColors,
    huePeakedness: colour.peakedness,
    paperLikeness: paperLike,
    photoLikelihood: photo,
    paperDetected: paperDetected,
  );
}

class _ColourStats {
  _ColourStats({
    required this.colorCount,
    required this.achromaticCount,
    required this.dominantHue,
    required this.dominantShare,
    required this.balancedCount,
    required this.chromaticShare,
    required this.redShare,
    required this.darkness,
    required this.uniqueColors,
    required this.peakedness,
    required this.pixelCluster,
  });
  final int colorCount;
  final int achromaticCount;
  final double dominantHue;
  final double dominantShare;
  final int balancedCount;
  final double chromaticShare;
  final double redShare;
  final double darkness;
  final int uniqueColors;

  /// Share of chromatic ink within ±1 bin of a significant cluster's peak.
  final double peakedness;

  /// Per pixel: hue-cluster id (0..), -2 black, -3 grey, -1 not ink.
  final Int16List pixelCluster;
}

_ColourStats _colourStats(RgbImage image, Mask ink, int inkArea) {
  final d = image.data;
  final n = image.pixelCount;
  final hueHist = Float64List(_hueBins);
  final pixelBin = Int16List(n)..fillRange(0, n, -1);
  final hueOf = Float32List(n);
  var chromatic = 0, black = 0, grey = 0, red = 0;
  var darkSum = 0.0;
  final colourBins = Int32List(4096);
  for (var i = 0; i < n; i++) {
    if (ink.bits[i] == 0) continue;
    final r = d[i * 3], g = d[i * 3 + 1], b = d[i * 3 + 2];
    colourBins[(r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)]++;
    final hsv = rgbToHsv(r, g, b);
    darkSum += 1 - hsv.v;
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    if (hsv.h >= 0 && hsv.s >= 0.28 && hsv.v >= 0.2 && mx - mn >= 40) {
      chromatic++;
      final bin = (hsv.h / (360 / _hueBins)).floor() % _hueBins;
      hueHist[bin]++;
      pixelBin[i] = bin;
      hueOf[i] = hsv.h;
      if (hsv.h < 20 || hsv.h > 340) red++;
    } else if (hsv.v < 0.45) {
      black++;
      pixelBin[i] = -2;
    } else {
      grey++;
      pixelBin[i] = -3;
    }
  }
  var unique = 0;
  final minBin = math.max(1, (inkArea * 0.0002).round());
  for (final c in colourBins) {
    if (c >= minBin) unique++;
  }

  // Cluster hues: smooth the circular histogram, then hill-climb every bin
  // to its local maximum.
  final smooth = Float64List(_hueBins);
  for (var k = 0; k < _hueBins; k++) {
    smooth[k] =
        (hueHist[(k + _hueBins - 1) % _hueBins] +
            2 * hueHist[k] +
            hueHist[(k + 1) % _hueBins]) /
        4;
  }
  final peakOf = Int32List(_hueBins);
  for (var k = 0; k < _hueBins; k++) {
    var cur = k;
    for (var guard = 0; guard < _hueBins; guard++) {
      final l = (cur + _hueBins - 1) % _hueBins;
      final r = (cur + 1) % _hueBins;
      var next = cur;
      if (smooth[l] > smooth[next]) next = l;
      if (smooth[r] > smooth[next]) next = r;
      if (next == cur) break;
      cur = next;
    }
    peakOf[k] = cur;
  }
  final clusterMass = Float64List(_hueBins); // indexed by peak bin
  for (var k = 0; k < _hueBins; k++) {
    clusterMass[peakOf[k]] += hueHist[k];
  }
  final peaks =
      [
        for (var k = 0; k < _hueBins; k++)
          if (clusterMass[k] > 0) k,
      ]..sort((a, b) {
        final c = clusterMass[b].compareTo(clusterMass[a]);
        return c != 0 ? c : a.compareTo(b);
      });
  var colorCount = 0;
  var balanced = 0;
  final nearPeak = Uint8List(_hueBins);
  for (final p in peaks) {
    if (clusterMass[p] >= 0.03 * inkArea &&
        clusterMass[p] >= 0.04 * chromatic) {
      colorCount++;
      for (var k = -1; k <= 1; k++) {
        nearPeak[(p + k + _hueBins) % _hueBins] = 1;
      }
    }
    if (chromatic > 0 && clusterMass[p] >= 0.12 * chromatic) balanced++;
  }

  // Map each chromatic pixel to the rank of its cluster.
  final rankOfPeak = Int32List(_hueBins)..fillRange(0, _hueBins, -1);
  for (var r = 0; r < peaks.length; r++) {
    rankOfPeak[peaks[r]] = r;
  }
  var domSin = 0.0, domCos = 0.0;
  final cluster = Int16List(n)..fillRange(0, n, -1);
  for (var i = 0; i < n; i++) {
    final bin = pixelBin[i];
    if (bin >= 0) {
      final rank = rankOfPeak[peakOf[bin]];
      cluster[i] = rank;
      if (rank == 0) {
        final a = hueOf[i] * math.pi / 180;
        domSin += math.sin(a);
        domCos += math.cos(a);
      }
    } else {
      cluster[i] = bin;
    }
  }
  var domHue = -1.0;
  if (peaks.isNotEmpty) {
    domHue = math.atan2(domSin, domCos) * 180 / math.pi;
    if (domHue < 0) domHue += 360;
  }
  var peaked = 0.0;
  for (var k = 0; k < _hueBins; k++) {
    if (nearPeak[k] == 1) peaked += hueHist[k];
  }
  final achromatic =
      (black >= 0.05 * inkArea ? 1 : 0) + (grey >= 0.05 * inkArea ? 1 : 0);
  return _ColourStats(
    colorCount: colorCount,
    achromaticCount: achromatic,
    dominantHue: domHue,
    dominantShare: peaks.isEmpty ? 0 : clusterMass[peaks.first] / chromatic,
    balancedCount: balanced,
    chromaticShare: chromatic / inkArea,
    redShare: red / inkArea,
    darkness: darkSum / inkArea,
    uniqueColors: unique,
    peakedness: chromatic == 0 ? 1 : peaked / chromatic,
    pixelCluster: cluster,
  );
}

class _Shading {
  _Shading(this.level, this.gradientShare);
  final double level;
  final double gradientShare;
}

/// Tonal gradation inside colour areas.
///
/// Interior ink pixels (2px away from the stroke edge) are classified on a
/// lightly blurred luminance image using first and second differences over
/// ±3 px:
/// * flat     — slope < 0.4 / px and nearly no curvature (a flat fill)
/// * gentle   — slope 0.4..6 / px and locally planar (a smooth gradient /
///              airbrush / blended shading)
/// * textured — anything else (crayon grain, hatching, noise)
///
/// `gradientShare` is gentle / interior. The level count is the number of
/// 1/16 brightness steps occupied by non-textured pixels within one colour
/// cluster (flat fills use 1-2, shaded areas many).
_Shading _shading(Mask ink, Uint8List lum, Int16List cluster) {
  final w = ink.width;
  final h = ink.height;
  final interior = erode(ink, 2);
  const o = 3;
  var total = 0, gentle = 0;
  final levels = <int, Int32List>{};
  for (var y = o; y < h - o; y++) {
    for (var x = o; x < w - o; x++) {
      final i = y * w + x;
      if (interior.bits[i] == 0) continue;
      total++;
      final l = lum[i];
      final ax = lum[i - o], bx = lum[i + o];
      final ay = lum[i - o * w], by = lum[i + o * w];
      final slope = ((bx - ax).abs() + (by - ay).abs()) / (2 * o);
      final curv = (ax + bx - 2 * l).abs() + (ay + by - 2 * l).abs();
      final bool smooth;
      if (slope < 0.4) {
        smooth = curv <= 4;
      } else if (slope <= 6) {
        smooth = curv <= 4 + slope;
        if (smooth) gentle++;
      } else {
        smooth = false;
      }
      if (!smooth) continue;
      final bins = levels.putIfAbsent(cluster[i], () => Int32List(16));
      bins[l >> 4]++;
    }
  }
  if (total < 50) return _Shading(0, 0);
  var weighted = 0.0;
  var mass = 0;
  final keys = levels.keys.toList()..sort();
  for (final key in keys) {
    final bins = levels[key]!;
    final m = bins.fold<int>(0, (a, b) => a + b);
    if (m < 30) continue;
    var occupied = 0;
    for (final c in bins) {
      if (c >= 0.02 * m) occupied++;
    }
    weighted += occupied * m;
    mass += m;
  }
  final meanLevels = mass == 0 ? 1.0 : weighted / mass;
  final gradientShare = gentle / total;
  final level = clamp01(
    0.5 * ramp(meanLevels, 2, 6) + 0.5 * ramp(gradientShare, 0.05, 0.35),
  );
  return _Shading(level, gradientShare);
}

class _Shape {
  _Shape(
    this.spikiness,
    this.defects,
    this.roundness,
    this.solidity,
    this.elongation,
  );
  final double spikiness;
  final int defects;
  final double roundness;
  final double solidity;
  final double elongation;
}

/// Shape descriptors of the largest silhouette component.
_Shape _shapeStats(Mask sil) {
  final lab = labelComponents(sil);
  Component? main;
  for (final c in lab.components) {
    if (main == null || c.area > main.area) main = c;
  }
  final comp = main!;
  final raw = toPoints(
    traceContour(
      sil,
      comp.firstIndex,
      labels: lab.labels,
      labelValue: comp.label,
    ),
  );
  final contour = smoothClosed(raw, 2);
  final perimeter = math.max(1.0, closedLength(contour));
  final hull = convexHull(raw);
  final hullPerimeter = closedLength(hull);
  final hullArea = math.max(1.0, polygonArea(hull));
  final area = comp.area.toDouble();

  // Convexity defects: hull edges whose contour detour is deep.
  var defects = 0;
  if (hull.length >= 3 && raw.length > 8) {
    final depthLimit = math.max(4.0, 0.12 * math.sqrt(area));
    // Index contour points by nearest hull vertex order.
    final hullIdx = <int>[];
    for (final hv in hull) {
      var bi = 0;
      var bd = double.infinity;
      for (var i = 0; i < raw.length; i++) {
        final dd = (raw[i] - hv).length;
        if (dd < bd) {
          bd = dd;
          bi = i;
        }
      }
      hullIdx.add(bi);
    }
    hullIdx.sort();
    for (var k = 0; k < hullIdx.length; k++) {
      final a = hullIdx[k];
      final b = k + 1 < hullIdx.length
          ? hullIdx[k + 1]
          : hullIdx[0] + raw.length;
      final pa = raw[a];
      final pb = raw[b % raw.length];
      final seg = pb - pa;
      final len = seg.length;
      if (len < 1e-6 || b - a < 3) continue;
      var maxDepth = 0.0;
      for (var j = a + 1; j < b; j++) {
        final p = raw[j % raw.length] - pa;
        final depth = (p.x * seg.y - p.y * seg.x).abs() / len;
        if (depth > maxDepth) maxDepth = depth;
      }
      if (maxDepth > depthLimit) defects++;
    }
  }

  // Principal axes of the component's pixels.
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  final cx = comp.cx, cy = comp.cy;
  final w = sil.width;
  for (var y = comp.minY; y <= comp.maxY; y++) {
    for (var x = comp.minX; x <= comp.maxX; x++) {
      if (lab.labels[y * w + x] != comp.label) continue;
      final dx = x - cx, dy = y - cy;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }
  }
  sxx /= area;
  syy /= area;
  sxy /= area;
  final tr = sxx + syy;
  final det = sxx * syy - sxy * sxy;
  final disc = math.sqrt(math.max(0, tr * tr / 4 - det));
  final l1 = tr / 2 + disc;
  final l2 = math.max(1e-6, tr / 2 - disc);
  final elongation = math.min(10.0, math.sqrt(l1 / l2));

  return _Shape(
    clamp01(1 - hullPerimeter / perimeter),
    defects,
    clamp01(4 * math.pi * area / (perimeter * perimeter)),
    clamp01(area / hullArea),
    elongation,
  );
}

/// Outline statistics over all ink components:
/// * roughness — mean displacement (px) between the outline smoothed at a
///   small scale (removes pixel staircase) and at a larger scale (removes
///   hand wobble but keeps the shape);
/// * wobble — curvature sign changes (inflections) per 100 px of outline,
///   ignoring the two that every open stroke has at its ends. A steady hand
///   draws few inflections; a shaky one draws many.
({double roughness, double wobble}) _contourStats(Labeling labels, Mask ink) {
  var weighted = 0.0;
  var totalLen = 0.0;
  var inflections = 0;
  var wobbleLen = 0.0;
  for (final c in labels.components) {
    if (c.area < 30) continue;
    final raw = toPoints(
      traceContour(
        ink,
        c.firstIndex,
        labels: labels.labels,
        labelValue: c.label,
      ),
    );
    if (raw.length < 40) continue;
    final fine = smoothClosed(raw, 2);
    final coarse = smoothClosed(raw, 8);
    final dev = <double>[
      for (var i = 0; i < raw.length; i++) (fine[i] - coarse[i]).length,
    ]..sort();
    // Trim the top 15% (corners legitimately deviate).
    final keep = (dev.length * 0.85).floor();
    var s = 0.0;
    for (var i = 0; i < keep; i++) {
      s += dev[i];
    }
    weighted += s / math.max(1, keep) * raw.length;
    totalLen += raw.length;

    if (raw.length < 100) continue;
    final sm = smoothClosed(raw, 3);
    const k = 5;
    const tau = 0.12;
    final m = sm.length;
    var state = 0;
    var count = 0;
    for (var i = 0; i < m; i++) {
      final a = sm[(i - k + m) % m], p = sm[i], q = sm[(i + k) % m];
      final v1 = p - a, v2 = q - p;
      final turn = math.atan2(
        v1.x * v2.y - v1.y * v2.x,
        v1.x * v2.x + v1.y * v2.y,
      );
      if (turn > tau) {
        if (state == -1) count++;
        state = 1;
      } else if (turn < -tau) {
        if (state == 1) count++;
        state = -1;
      }
    }
    inflections += math.max(0, count - 2);
    wobbleLen += m;
  }
  return (
    roughness: totalLen == 0 ? 0.0 : weighted / totalLen,
    wobble: wobbleLen == 0 ? 0.0 : inflections * 100 / wobbleLen,
  );
}

/// Best mirror IoU around a vertical axis near the shape's centroid.
double _mirrorIoU(Mask m) {
  final w = m.width;
  final h = m.height;
  var sumX = 0.0;
  var area = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (m.bits[y * w + x] != 0) {
        sumX += x;
        area++;
      }
    }
  }
  if (area == 0) return 0;
  final axis2 = (2 * sumX / area).round(); // mirrored x = axis2 - x
  var best = 0.0;
  for (var s = -6; s <= 6; s++) {
    final a2 = axis2 + s;
    var inter = 0;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        if (m.bits[row + x] == 0) continue;
        final mx = a2 - x;
        if (mx >= 0 && mx < w && m.bits[row + mx] != 0) inter++;
      }
    }
    final iou = inter / (2 * area - inter);
    if (iou > best) best = iou;
  }
  return best;
}

/// Median stroke width from distance-transform ridge pixels.
double _lineThickness(Mask ink, Int32List dt) {
  final w = ink.width;
  final h = ink.height;
  final hist = Int32List(256);
  var count = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      final v = dt[i];
      if (ink.bits[i] == 0) continue;
      var ridge = true;
      for (var dy = -1; dy <= 1 && ridge; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= w || (dx == 0 && dy == 0)) continue;
          if (dt[ny * w + nx] > v) {
            ridge = false;
            break;
          }
        }
      }
      if (!ridge) continue;
      hist[math.min(255, v)]++;
      count++;
    }
  }
  if (count == 0) return 0;
  var acc = 0;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc * 2 >= count) {
      // v is in thirds of a pixel; width ≈ 2 * distance - 1.
      return math.min(60.0, math.max(1.0, 2 * v / 3 - 1));
    }
  }
  return 60;
}

/// Pixels on thin dark lines (width <= ~3 px) inside [region], on paper or
/// on top of colour: darker than both neighbours 2 px away in some direction
/// by at least 28 levels, on a coherent edge structure, and part of a
/// connected run of at least 12 such pixels (rejects crayon grain / noise).
int _thinLinePixels(Uint8List lum, EdgeField f, Mask region) {
  final w = f.width;
  final h = f.height;
  const dirs = [2, 0, 0, 2, 2, 2, 2, -2];
  final valley = Mask(w, h);
  for (var y = 2; y < h - 2; y++) {
    for (var x = 2; x < w - 2; x++) {
      final i = y * w + x;
      if (region.bits[i] == 0 || f.coherence[i] < 0.6) continue;
      final l = lum[i];
      for (var d = 0; d < dirs.length; d += 2) {
        final o = dirs[d + 1] * w + dirs[d];
        if (math.min(lum[i - o], lum[i + o]) - l >= 28) {
          valley.bits[i] = 1;
          break;
        }
      }
    }
  }
  var count = 0;
  for (final c in labelComponents(valley).components) {
    if (c.area >= 12) count += c.area;
  }
  return count;
}
