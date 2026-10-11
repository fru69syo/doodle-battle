import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../ar/glb/standee_textures.dart' show squaredDistanceTransform;

/// Which kind of body [buildInflatedMesh] makes.
enum InflateVariant {
  /// Puffy plush-like body: the silhouette of the drawing, inflated by the
  /// radius of the largest inscribed disc at every point (round tubes for
  /// limbs, a dome for the body), textured with the drawing.
  puffy,

  /// Very low-poly, flat-shaded blob in 3 flat colours taken from the
  /// drawing (SPEC §12.2 "とても簡素化したキャラ"). No texture.
  simplified,
}

/// Tunables for [buildInflatedMesh].
class InflateOptions {
  const InflateOptions({
    this.variant = InflateVariant.puffy,
    this.heightMeters = 1.0,
    this.workResolution = 128,
    this.gridCells = 56,
    this.depthScale = 0.7,
    this.maxTextureSize = 512,
    this.alphaThreshold = 128,
    this.smoothingPasses = 2,
  });

  /// Low-poly blob preset.
  const InflateOptions.simplified({this.heightMeters = 1.0})
    : variant = InflateVariant.simplified,
      workResolution = 96,
      gridCells = 9,
      depthScale = 0.8,
      maxTextureSize = 0,
      alphaThreshold = 128,
      smoothingPasses = 1;

  final InflateVariant variant;

  /// Height of the character (feet at y=0 to the top of the silhouette).
  final double heightMeters;

  /// Longest side (px) of the mask the geometry is computed on. The drawing
  /// texture keeps its own resolution (≤ [maxTextureSize]).
  final int workResolution;

  /// Grid cells along the longest side; controls the triangle count.
  final int gridCells;

  /// Depth of the inflation relative to a perfectly round cross-section.
  final double depthScale;

  /// Longest side of the embedded texture (0 = no texture).
  final int maxTextureSize;

  /// Alpha (0–255) at or above which a pixel belongs to the drawing.
  final int alphaThreshold;

  /// 3×3 smoothing passes on the height field.
  final int smoothingPasses;
}

/// Watertight, two-sided mesh made from a cut-out. Units are metres, +Y up,
/// facing +Z, origin at the bottom centre (between the feet).
class InflatedMesh {
  InflatedMesh({
    required this.positions,
    required this.normals,
    required this.uvs,
    required this.colors,
    required this.indices,
    required this.texture,
    required this.width,
    required this.height,
    required this.depth,
    required this.boundaryVertexCount,
    required this.flatShaded,
  });

  /// xyz per vertex.
  final Float32List positions;

  /// Unit normals, xyz per vertex.
  final Float32List normals;

  /// Texture coordinates (glTF convention, v down), uv per vertex.
  final Float32List uvs;

  /// Linear RGBA per vertex (front ≈ white, back darker; flat palette
  /// colours for [InflateVariant.simplified]).
  final Float32List colors;

  /// Triangle list, counter-clockwise seen from outside.
  final Uint32List indices;

  /// The drawing (cropped, colours bled into the transparent area, opaque)
  /// or null for the simplified variant.
  final img.Image? texture;

  final double width;
  final double height;

  /// Front-to-back thickness at the thickest point.
  final double depth;

  /// Vertices on the silhouette (z = 0, shared by front and back).
  final int boundaryVertexCount;

  /// True when every triangle has its own vertices (faceted look).
  final bool flatShaded;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
}

/// Thrown when the cut-out has no opaque pixels.
class EmptyCutoutException implements Exception {
  const EmptyCutoutException();
  @override
  String toString() => 'EmptyCutoutException: the cut-out is empty';
}

/// Builds the inflated mesh from a cut-out with a transparent background.
///
/// Pipeline (all pure Dart, deterministic):
/// 1. crop to the opaque bounding box and area-sample the alpha into a work
///    mask (≤ [InflateOptions.workResolution] px), keep the largest blob and
///    fill small holes;
/// 2. exact Euclidean distance transforms → signed distance to the outline
///    `sdf` and inside distance `d`;
/// 3. local radius `R` = radius of the largest inscribed disc covering each
///    pixel (splatted from the distance ridge), height
///    `h = depthScale·√(d(2R−d))` (a round cross-section), smoothed;
/// 4. marching-squares *fill* on the grid: interior grid corners get the
///    height, outline crossings get h = 0, so the front (+h) and back (−h)
///    sheets share the outline vertices and close into a watertight body;
/// 5. normals from area-weighted faces over the shared vertices.
InflatedMesh buildInflatedMesh(
  img.Image cutout, {
  InflateOptions options = const InflateOptions(),
}) {
  final src = cutout.numChannels == 4 ? cutout : cutout.convert(numChannels: 4);
  final simplified = options.variant == InflateVariant.simplified;

  // --- 1. Crop + work mask ------------------------------------------------
  final bbox = _alphaBounds(src, options.alphaThreshold);
  if (bbox == null) throw const EmptyCutoutException();
  final (sx0, sy0, sw, sh) = bbox;
  // Room around the drawing so the outline never touches the grid border
  // (the blob variant grows a little when its distance field is blurred).
  final pad = simplified ? 2 + (options.workResolution * 0.06 * 2.5).ceil() : 2;
  final k = math.min(1.0, (options.workResolution - 2 * pad) / math.max(sw, sh));
  final cw = math.max(1, (sw * k).ceil());
  final chh = math.max(1, (sh * k).ceil());
  final ww = cw + 2 * pad;
  final wh = chh + 2 * pad;
  var mask = Uint8List(ww * wh);
  for (var y = 0; y < chh; y++) {
    final y0 = sy0 + y / k;
    final y1 = math.min(sy0 + sh.toDouble(), sy0 + (y + 1) / k);
    for (var x = 0; x < cw; x++) {
      final x0 = sx0 + x / k;
      final x1 = math.min(sx0 + sw.toDouble(), sx0 + (x + 1) / k);
      final a = _areaAlpha(src, x0, y0, x1, y1);
      if (a >= options.alphaThreshold) mask[(y + pad) * ww + x + pad] = 1;
    }
  }
  mask = _largestComponent(mask, ww, wh);
  _fillSmallHoles(mask, ww, wh, maxArea: (ww * wh * 0.02).round());

  // --- 2. Distance fields -------------------------------------------------
  var sdf = _signedDistance(mask, ww, wh);
  if (simplified) {
    // Blob-ify: blur the signed distance so thin parts melt into the body.
    final sigma = math.max(ww, wh) * 0.06;
    sdf = _gaussianBlur(sdf, ww, wh, sigma);
    for (var i = 0; i < mask.length; i++) {
      mask[i] = sdf[i] > 0 ? 1 : 0;
    }
    mask = _largestComponent(mask, ww, wh);
    _fillSmallHoles(mask, ww, wh, maxArea: ww * wh);
    sdf = _signedDistance(mask, ww, wh);
  }
  final inside = Float64List(ww * wh);
  var dMax = 0.0;
  for (var i = 0; i < inside.length; i++) {
    final d = math.max(0.0, sdf[i]);
    inside[i] = d;
    if (d > dMax) dMax = d;
  }

  // --- 3. Height field ----------------------------------------------------
  final radius = simplified
      ? (Float64List(ww * wh)..fillRange(0, ww * wh, dMax))
      : _inscribedRadius(inside, mask, ww, wh);
  var height = Float64List(ww * wh);
  for (var i = 0; i < height.length; i++) {
    if (mask[i] == 0) continue;
    final d = inside[i];
    final r = math.max(radius[i], d);
    height[i] = options.depthScale * math.sqrt(math.max(0.0, d * (2 * r - d)));
  }
  for (var p = 0; p < options.smoothingPasses; p++) {
    height = _smoothInside(height, mask, ww, wh);
  }

  // --- 4. Marching-squares fill ------------------------------------------
  final cell = math.max(ww, wh) / options.gridCells;
  final gx = (ww / cell).ceil();
  final gy = (wh / cell).ceil();
  double field(double x, double y) => _bilinear(sdf, ww, wh, x - 0.5, y - 0.5);
  double heightAt(double x, double y) =>
      _bilinear(height, ww, wh, x - 0.5, y - 0.5);

  final cornerF = Float64List((gx + 1) * (gy + 1));
  for (var j = 0; j <= gy; j++) {
    for (var i = 0; i <= gx; i++) {
      final border = i == 0 || j == 0 || i == gx || j == gy;
      final f = field(i * cell, j * cell);
      // Border corners are always outside so the surface is closed.
      cornerF[j * (gx + 1) + i] = border ? math.min(f, -0.01) : f;
    }
  }

  // Shared 2D vertices: (work x, work y, height, isBoundary).
  final vx = <double>[];
  final vy = <double>[];
  final vh = <double>[];
  final vBoundary = <bool>[];
  final cornerId = <int, int>{};
  final edgeId = <int, int>{};
  int corner(int i, int j) => cornerId.putIfAbsent(j * (gx + 1) + i, () {
    final x = i * cell;
    final y = j * cell;
    vx.add(x);
    vy.add(y);
    vh.add(heightAt(x, y));
    vBoundary.add(false);
    return vx.length - 1;
  });
  // Edge from corner a to corner b (a inside, b outside or vice versa).
  int crossing(int ia, int ja, int ib, int jb) {
    final horizontal = ja == jb;
    final i0 = math.min(ia, ib);
    final j0 = math.min(ja, jb);
    final key = 2 * (j0 * (gx + 1) + i0) + (horizontal ? 0 : 1);
    return edgeId.putIfAbsent(key, () {
      final fa = cornerF[ja * (gx + 1) + ia];
      final fb = cornerF[jb * (gx + 1) + ib];
      final t = (fa / (fa - fb)).clamp(0.02, 0.98);
      vx.add((ia + (ib - ia) * t) * cell);
      vy.add((ja + (jb - ja) * t) * cell);
      vh.add(0);
      vBoundary.add(true);
      return vx.length - 1;
    });
  }

  final tris = <int>[];
  const ci = [0, 1, 1, 0];
  const cj = [0, 0, 1, 1];
  for (var j = 0; j < gy; j++) {
    for (var i = 0; i < gx; i++) {
      final ins = [
        for (var c = 0; c < 4; c++)
          cornerF[(j + cj[c]) * (gx + 1) + i + ci[c]] > 0,
      ];
      final first = ins.indexOf(true);
      if (first < 0) continue;
      final poly = <int>[];
      for (var s = 0; s < 4; s++) {
        final c = (first + s) % 4;
        final n = (c + 1) % 4;
        if (ins[c]) poly.add(corner(i + ci[c], j + cj[c]));
        if (ins[c] != ins[n]) {
          poly.add(crossing(i + ci[c], j + cj[c], i + ci[n], j + cj[n]));
        }
      }
      for (var t = 1; t + 1 < poly.length; t++) {
        // Corners walk clockwise on screen (y down) = clockwise seen from +Z
        // after flipping y; emit reversed so the front is CCW from +Z.
        tris
          ..add(poly[0])
          ..add(poly[t + 1])
          ..add(poly[t]);
      }
    }
  }

  // --- 5. Assemble front/back in metres -----------------------------------
  var minX = double.infinity, maxX = -double.infinity;
  var maxY = -double.infinity, minY = double.infinity;
  for (var v = 0; v < vx.length; v++) {
    if (!vBoundary[v]) continue;
    minX = math.min(minX, vx[v]);
    maxX = math.max(maxX, vx[v]);
    minY = math.min(minY, vy[v]);
    maxY = math.max(maxY, vy[v]);
  }
  final scale = options.heightMeters / (maxY - minY);
  final centreX = (minX + maxX) / 2;

  // Interior vertices are duplicated (front + back); boundary ones shared.
  final n2 = vx.length;
  final backId = Int32List(n2);
  var count = n2;
  for (var v = 0; v < n2; v++) {
    backId[v] = vBoundary[v] ? v : count++;
  }
  final pos = Float32List(count * 3);
  final uv = Float32List(count * 2);
  final isBack = Uint8List(count);
  for (var v = 0; v < n2; v++) {
    final x = (vx[v] - centreX) * scale;
    final y = (maxY - vy[v]) * scale;
    final z = vh[v] * scale;
    // Work coords → source crop texture coords.
    final u = ((vx[v] - pad) / k / sw).clamp(0.0, 1.0);
    final t = ((vy[v] - pad) / k / sh).clamp(0.0, 1.0);
    for (final (id, zz) in [(v, z), (backId[v], 0.0 - z)]) {
      pos[id * 3] = x;
      pos[id * 3 + 1] = y;
      pos[id * 3 + 2] = zz;
      uv[id * 2] = u;
      uv[id * 2 + 1] = t;
    }
    if (!vBoundary[v]) isBack[backId[v]] = 1;
  }
  final idx = <int>[...tris];
  for (var t = 0; t < tris.length; t += 3) {
    idx
      ..add(backId[tris[t]])
      ..add(backId[tris[t + 2]])
      ..add(backId[tris[t + 1]]);
  }

  var depth = 0.0;
  for (var v = 0; v < n2; v++) {
    depth = math.max(depth, 2 * vh[v] * scale);
  }
  final width = (maxX - minX) * scale;
  final texture = options.maxTextureSize > 0
      ? _bledTexture(src, sx0, sy0, sw, sh, options.maxTextureSize)
      : null;

  if (simplified) {
    final palette = _palette(src, options.alphaThreshold, 3);
    return _flatShaded(
      pos,
      Uint32List.fromList(idx),
      uv,
      isBack,
      src,
      sx0,
      sy0,
      sw,
      sh,
      palette,
      width: width,
      height: options.heightMeters,
      depth: depth,
      boundary: vBoundary.where((b) => b).length,
    );
  }

  final colors = Float32List(count * 4);
  for (var v = 0; v < count; v++) {
    final c = isBack[v] == 1 ? 0.55 : (v < n2 && vBoundary[v] ? 0.85 : 1.0);
    colors[v * 4] = c;
    colors[v * 4 + 1] = c;
    colors[v * 4 + 2] = c * 1.05 > 1 ? 1 : c * 1.05;
    colors[v * 4 + 3] = 1;
  }
  final indices = Uint32List.fromList(idx);
  return InflatedMesh(
    positions: pos,
    normals: _vertexNormals(pos, indices),
    uvs: uv,
    colors: colors,
    indices: indices,
    texture: texture,
    width: width,
    height: options.heightMeters,
    depth: depth,
    boundaryVertexCount: vBoundary.where((b) => b).length,
    flatShaded: false,
  );
}

// ---------------------------------------------------------------------------

(int, int, int, int)? _alphaBounds(img.Image im, int threshold) {
  var x0 = im.width, y0 = im.height, x1 = -1, y1 = -1;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).a >= threshold) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return null;
  return (x0, y0, x1 - x0 + 1, y1 - y0 + 1);
}

/// Mean alpha of the source pixels whose centres fall in [x0,x1)×[y0,y1).
double _areaAlpha(img.Image im, double x0, double y0, double x1, double y1) {
  var sum = 0.0;
  var n = 0;
  final xa = (x0 - 0.5).ceil(), xb = (x1 - 0.5).ceil();
  final ya = (y0 - 0.5).ceil(), yb = (y1 - 0.5).ceil();
  for (var y = ya; y < math.max(yb, ya + 1); y++) {
    for (var x = xa; x < math.max(xb, xa + 1); x++) {
      final cx = x.clamp(0, im.width - 1);
      final cy = y.clamp(0, im.height - 1);
      sum += im.getPixel(cx, cy).a;
      n++;
    }
  }
  return sum / n;
}

Uint8List _largestComponent(Uint8List mask, int w, int h) {
  final label = Int32List(w * h);
  var best = 0, bestSize = 0, next = 0;
  final stack = <int>[];
  for (var s = 0; s < mask.length; s++) {
    if (mask[s] == 0 || label[s] != 0) continue;
    next++;
    var size = 0;
    stack.add(s);
    label[s] = next;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      size++;
      final x = p % w, y = p ~/ w;
      for (final q in [
        if (x > 0) p - 1,
        if (x < w - 1) p + 1,
        if (y > 0) p - w,
        if (y < h - 1) p + w,
      ]) {
        if (mask[q] != 0 && label[q] == 0) {
          label[q] = next;
          stack.add(q);
        }
      }
    }
    if (size > bestSize) {
      bestSize = size;
      best = next;
    }
  }
  final out = Uint8List(w * h);
  for (var i = 0; i < out.length; i++) {
    out[i] = label[i] == best && best != 0 ? 1 : 0;
  }
  return out;
}

/// Fills background regions that do not touch the border and are at most
/// [maxArea] pixels (specks inside the drawing).
void _fillSmallHoles(Uint8List mask, int w, int h, {required int maxArea}) {
  final seen = Uint8List(w * h);
  final stack = <int>[];
  for (var s = 0; s < mask.length; s++) {
    if (mask[s] != 0 || seen[s] != 0) continue;
    final region = <int>[];
    var touchesBorder = false;
    stack.add(s);
    seen[s] = 1;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      region.add(p);
      final x = p % w, y = p ~/ w;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) touchesBorder = true;
      for (final q in [
        if (x > 0) p - 1,
        if (x < w - 1) p + 1,
        if (y > 0) p - w,
        if (y < h - 1) p + w,
      ]) {
        if (mask[q] == 0 && seen[q] == 0) {
          seen[q] = 1;
          stack.add(q);
        }
      }
    }
    if (!touchesBorder && region.length <= maxArea) {
      for (final p in region) {
        mask[p] = 1;
      }
    }
  }
}

/// Signed distance (px) to the outline: >0 inside, <0 outside.
Float64List _signedDistance(Uint8List mask, int w, int h) {
  final bg = Uint8List(w * h);
  for (var i = 0; i < bg.length; i++) {
    bg[i] = mask[i] == 0 ? 1 : 0;
  }
  final toBg = squaredDistanceTransform(bg, w, h);
  final toFg = squaredDistanceTransform(mask, w, h);
  final out = Float64List(w * h);
  for (var i = 0; i < out.length; i++) {
    out[i] = mask[i] != 0
        ? math.sqrt(toBg[i]) - 0.5
        : -(math.sqrt(toFg[i]) - 0.5);
  }
  return out;
}

/// Radius of the largest inscribed disc that covers each pixel, splatted
/// from the ridge (local maxima) of the inside distance.
Float64List _inscribedRadius(Float64List d, Uint8List mask, int w, int h) {
  final r = Float64List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p = y * w + x;
      final dp = d[p];
      if (mask[p] == 0 || dp <= 0) continue;
      var ridge = true;
      for (var dy = -1; dy <= 1 && ridge; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (d[p + dy * w + dx] > dp + 1e-9) {
            ridge = false;
            break;
          }
        }
      }
      if (!ridge) continue;
      final rad = dp + 0.5;
      final r2 = rad * rad;
      final ri = rad.ceil();
      for (var yy = math.max(0, y - ri); yy <= math.min(h - 1, y + ri); yy++) {
        final ddy = (yy - y) * (yy - y);
        for (var xx = math.max(0, x - ri); xx <= math.min(w - 1, x + ri); xx++) {
          if (ddy + (xx - x) * (xx - x) > r2) continue;
          final q = yy * w + xx;
          if (r[q] < dp) r[q] = dp;
        }
      }
    }
  }
  return r;
}

Float64List _smoothInside(Float64List f, Uint8List mask, int w, int h) {
  final out = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = y * w + x;
      if (mask[p] == 0) continue;
      var s = 0.0;
      var n = 0;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final q = yy * w + xx;
          if (mask[q] == 0) continue;
          s += f[q];
          n++;
        }
      }
      out[p] = s / n;
    }
  }
  return out;
}

Float64List _gaussianBlur(Float64List f, int w, int h, double sigma) {
  final rad = (sigma * 2.5).ceil();
  final kern = Float64List(2 * rad + 1);
  var ks = 0.0;
  for (var i = -rad; i <= rad; i++) {
    kern[i + rad] = math.exp(-(i * i) / (2 * sigma * sigma));
    ks += kern[i + rad];
  }
  for (var i = 0; i < kern.length; i++) {
    kern[i] /= ks;
  }
  final tmp = Float64List(w * h);
  final out = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var i = -rad; i <= rad; i++) {
        s += kern[i + rad] * f[y * w + (x + i).clamp(0, w - 1)];
      }
      tmp[y * w + x] = s;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var i = -rad; i <= rad; i++) {
        s += kern[i + rad] * tmp[(y + i).clamp(0, h - 1) * w + x];
      }
      out[y * w + x] = s;
    }
  }
  return out;
}

double _bilinear(Float64List f, int w, int h, double x, double y) {
  final xc = x.clamp(0.0, w - 1.0);
  final yc = y.clamp(0.0, h - 1.0);
  final x0 = xc.floor(), y0 = yc.floor();
  final x1 = math.min(x0 + 1, w - 1), y1 = math.min(y0 + 1, h - 1);
  final tx = xc - x0, ty = yc - y0;
  final a = f[y0 * w + x0] * (1 - tx) + f[y0 * w + x1] * tx;
  final b = f[y1 * w + x0] * (1 - tx) + f[y1 * w + x1] * tx;
  return a * (1 - ty) + b * ty;
}

Float32List _vertexNormals(Float32List pos, Uint32List idx) {
  final n = Float64List(pos.length);
  for (var t = 0; t < idx.length; t += 3) {
    final a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
    final ux = pos[b] - pos[a], uy = pos[b + 1] - pos[a + 1];
    final uz = pos[b + 2] - pos[a + 2];
    final wx = pos[c] - pos[a], wy = pos[c + 1] - pos[a + 1];
    final wz = pos[c + 2] - pos[a + 2];
    final nx = uy * wz - uz * wy;
    final ny = uz * wx - ux * wz;
    final nz = ux * wy - uy * wx;
    for (final v in [a, b, c]) {
      n[v] += nx;
      n[v + 1] += ny;
      n[v + 2] += nz;
    }
  }
  final out = Float32List(pos.length);
  for (var v = 0; v < pos.length; v += 3) {
    final l = math.sqrt(n[v] * n[v] + n[v + 1] * n[v + 1] + n[v + 2] * n[v + 2]);
    if (l < 1e-12) {
      out[v + 2] = 1;
      continue;
    }
    out[v] = n[v] / l;
    out[v + 1] = n[v + 1] / l;
    out[v + 2] = n[v + 2] / l;
  }
  return out;
}

/// Cropped drawing with RGB bled outward (so texture filtering at the
/// silhouette does not pick up the transparent background) and alpha = 255.
img.Image _bledTexture(
  img.Image src,
  int sx0,
  int sy0,
  int sw,
  int sh,
  int maxSize,
) {
  var crop = img.copyCrop(src, x: sx0, y: sy0, width: sw, height: sh);
  if (math.max(sw, sh) > maxSize) {
    crop = img.copyResize(
      crop,
      width: sw >= sh ? maxSize : null,
      height: sh > sw ? maxSize : null,
      interpolation: img.Interpolation.average,
    );
  }
  final w = crop.width, h = crop.height;
  final rgb = Int32List(w * h * 3);
  final known = Uint8List(w * h);
  var sr = 0, sg = 0, sb = 0, sn = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = crop.getPixel(x, y);
      final i = y * w + x;
      if (p.a >= 128) {
        rgb[i * 3] = p.r.toInt();
        rgb[i * 3 + 1] = p.g.toInt();
        rgb[i * 3 + 2] = p.b.toInt();
        known[i] = 1;
        sr += p.r.toInt();
        sg += p.g.toInt();
        sb += p.b.toInt();
        sn++;
      }
    }
  }
  // A few dilation passes cover the rim; the rest gets the mean colour.
  for (var pass = 0; pass < 6; pass++) {
    final add = <int>[];
    final vals = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (known[i] == 1) continue;
        var r = 0, g = 0, b = 0, n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            final q = yy * w + xx;
            if (known[q] != 1) continue;
            r += rgb[q * 3];
            g += rgb[q * 3 + 1];
            b += rgb[q * 3 + 2];
            n++;
          }
        }
        if (n > 0) {
          add.add(i);
          vals
            ..add(r ~/ n)
            ..add(g ~/ n)
            ..add(b ~/ n);
        }
      }
    }
    for (var a = 0; a < add.length; a++) {
      final i = add[a];
      rgb[i * 3] = vals[a * 3];
      rgb[i * 3 + 1] = vals[a * 3 + 1];
      rgb[i * 3 + 2] = vals[a * 3 + 2];
      known[i] = 1;
    }
  }
  final out = img.Image(width: w, height: h, numChannels: 3);
  final mr = sn == 0 ? 128 : sr ~/ sn;
  final mg = sn == 0 ? 128 : sg ~/ sn;
  final mb = sn == 0 ? 128 : sb ~/ sn;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (known[i] == 1) {
        out.setPixelRgb(x, y, rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]);
      } else {
        out.setPixelRgb(x, y, mr, mg, mb);
      }
    }
  }
  return out;
}

/// k-means (deterministic init) palette of the opaque pixels, sRGB 0–255.
List<List<double>> _palette(img.Image src, int threshold, int k) {
  final samples = <List<double>>[];
  final step = math.max(1, (math.max(src.width, src.height) / 64).floor());
  for (var y = 0; y < src.height; y += step) {
    for (var x = 0; x < src.width; x += step) {
      final p = src.getPixel(x, y);
      if (p.a >= threshold) {
        samples.add([p.r.toDouble(), p.g.toDouble(), p.b.toDouble()]);
      }
    }
  }
  if (samples.isEmpty) return [List.filled(3, 128.0)];
  samples.sort((a, b) => (a[0] + a[1] + a[2]).compareTo(b[0] + b[1] + b[2]));
  final centres = [
    for (var c = 0; c < k; c++)
      List<double>.of(samples[((c + 0.5) * samples.length / k).floor()]),
  ];
  for (var iter = 0; iter < 8; iter++) {
    final sums = List.generate(k, (_) => [0.0, 0.0, 0.0, 0.0]);
    for (final s in samples) {
      final c = _nearest(centres, s);
      sums[c][0] += s[0];
      sums[c][1] += s[1];
      sums[c][2] += s[2];
      sums[c][3] += 1;
    }
    for (var c = 0; c < k; c++) {
      if (sums[c][3] == 0) continue;
      for (var ch = 0; ch < 3; ch++) {
        centres[c][ch] = sums[c][ch] / sums[c][3];
      }
    }
  }
  // Most common colour first (used where the blob extends past the drawing).
  final counts = List.filled(k, 0);
  for (final s in samples) {
    counts[_nearest(centres, s)]++;
  }
  final order = List.generate(k, (i) => i)
    ..sort((a, b) => counts[b].compareTo(counts[a]));
  return [for (final i in order) centres[i]];
}

int _nearest(List<List<double>> centres, List<double> s) {
  var best = 0;
  var bd = double.infinity;
  for (var c = 0; c < centres.length; c++) {
    final dr = centres[c][0] - s[0];
    final dg = centres[c][1] - s[1];
    final db = centres[c][2] - s[2];
    final d = dr * dr + dg * dg + db * db;
    if (d < bd) {
      bd = d;
      best = c;
    }
  }
  return best;
}

double _srgbToLinear(double c) {
  final v = c / 255;
  return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

/// Un-welds the mesh (one vertex per corner, face normals) and colours each
/// triangle with the palette entry nearest to the drawing under its centre.
InflatedMesh _flatShaded(
  Float32List pos,
  Uint32List idx,
  Float32List uv,
  Uint8List isBack,
  img.Image src,
  int sx0,
  int sy0,
  int sw,
  int sh,
  List<List<double>> palette, {
  required double width,
  required double height,
  required double depth,
  required int boundary,
}) {
  final n = idx.length;
  final p = Float32List(n * 3);
  final u = Float32List(n * 2);
  final col = Float32List(n * 4);
  final out = Uint32List(n);
  for (var t = 0; t < n; t += 3) {
    var cu = 0.0, cv = 0.0;
    var back = false;
    for (var c = 0; c < 3; c++) {
      final v = idx[t + c];
      cu += uv[v * 2] / 3;
      cv += uv[v * 2 + 1] / 3;
      back = back || isBack[v] == 1;
      for (var a = 0; a < 3; a++) {
        p[(t + c) * 3 + a] = pos[v * 3 + a];
      }
      u[(t + c) * 2] = uv[v * 2];
      u[(t + c) * 2 + 1] = uv[v * 2 + 1];
      out[t + c] = t + c;
    }
    final px = (sx0 + cu * (sw - 1)).round().clamp(0, src.width - 1);
    final py = (sy0 + cv * (sh - 1)).round().clamp(0, src.height - 1);
    final s = src.getPixel(px, py);
    final colour = s.a >= 128
        ? palette[_nearest(palette, [s.r.toDouble(), s.g.toDouble(), s.b.toDouble()])]
        : palette[0];
    final shade = back ? 0.6 : 1.0;
    for (var c = 0; c < 3; c++) {
      final o = (t + c) * 4;
      col[o] = _srgbToLinear(colour[0]) * shade;
      col[o + 1] = _srgbToLinear(colour[1]) * shade;
      col[o + 2] = _srgbToLinear(colour[2]) * shade;
      col[o + 3] = 1;
    }
  }
  final normals = _vertexNormals(p, out);
  return InflatedMesh(
    positions: p,
    normals: normals,
    uvs: u,
    colors: col,
    indices: out,
    texture: null,
    width: width,
    height: height,
    depth: depth,
    boundaryVertexCount: boundary,
    flatShaded: true,
  );
}
