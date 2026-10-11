import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'auto_rig.dart';
import 'bin_mask.dart';
import 'rig.dart';

/// Everything needed to draw and animate one character with
/// `Canvas.drawVertices` (no 3D API): the texture, a triangle mesh over the
/// drawing, the bones and per-vertex linear-blend-skinning weights.
///
/// Pure Dart (no `dart:ui`) so it is built in an isolate and unit-tested.
class RiggedCharacter {
  RiggedCharacter({
    required this.rig,
    required this.bones,
    required this.textureRgba,
    required this.texW,
    required this.texH,
    required this.rest,
    required this.indices,
    required this.boneIdx,
    required this.boneW,
    required this.micros,
    this.simplified = false,
  });

  /// Rig in texture pixels (shifted by the sticker border).
  final CharacterRig rig;
  final List<Bone> bones;

  /// RGBA8 texture (the cut-out + white sticker border, or the posterised
  /// look of a simplified character).
  final Uint8List textureRgba;
  final int texW, texH;

  /// Rest positions (x, y) per vertex in texture pixels; also the UVs.
  final Float32List rest;
  final Uint16List indices;

  /// 4 bone indices / weights per vertex (weights sum to 1).
  final Uint8List boneIdx;
  final Float32List boneW;

  final bool simplified;
  final Map<String, int> micros;

  int get vertexCount => rest.length ~/ 2;
  int get triangleCount => indices.length ~/ 3;

  /// Approximate retained bytes (texture + mesh), for the memory budget.
  int get bytes =>
      textureRgba.lengthInBytes +
      rest.lengthInBytes +
      indices.lengthInBytes +
      boneIdx.lengthInBytes +
      boneW.lengthInBytes;
}

/// Options for [buildRiggedCharacter].
class BuildOptions {
  const BuildOptions({
    this.gridCells = 64,
    this.border = 6,
    this.weightRes = 128,
    this.weightPower = 4,
    this.simplified = false,
  });

  /// Mesh cells along the longest side (≈ 2–4k triangles at 64).
  final int gridCells;

  /// White "sticker" border baked into the texture (px), helps readability
  /// on busy backgrounds.
  final int border;

  /// Longest side of the grid used for geodesic skinning distances.
  final int weightRes;
  final double weightPower;

  /// Hidden late bloomer look before Lv50: 3 flat colours, coarse mesh,
  /// body-only rig (squash / hop / wobble). Never named in the UI.
  final bool simplified;
}

/// Decodes a cut-out PNG and builds the rigged character (auto-rig unless
/// [rig] is given, e.g. the stored / edited one).
RiggedCharacter buildRiggedCharacterFromPng(
  Uint8List png, {
  CharacterRig? rig,
  BuildOptions options = const BuildOptions(),
}) {
  final im = img.decodePng(png) ?? img.decodeImage(png);
  if (im == null) throw const FormatException('not an image');
  final rgba = im.convert(numChannels: 4, format: img.Format.uint8);
  return buildRiggedCharacter(
    Uint8List.fromList(rgba.getBytes(order: img.ChannelOrder.rgba)),
    im.width,
    im.height,
    rig: rig,
    options: options,
  );
}

/// Builds from raw RGBA (straight alpha).
RiggedCharacter buildRiggedCharacter(
  Uint8List rgba,
  int w,
  int h, {
  CharacterRig? rig,
  BuildOptions options = const BuildOptions(),
}) {
  final micros = <String, int>{};
  final sw = Stopwatch()..start();
  void lap(String k) {
    micros[k] = sw.elapsedMicroseconds;
    sw.reset();
  }

  final mask = BinMask.fromRgba(rgba, w, h);
  var r = rig ?? autoRig(mask).rig;
  lap('rig');
  if (options.simplified) {
    // Body only: limbs are dropped so it moves like a simple blob.
    r = CharacterRig(
      width: r.width,
      height: r.height,
      root: V2(r.width / 2, r.groundY - 0.1 * r.height),
      chest: V2(r.width / 2, r.height * 0.4),
      limbs: [],
      ground: r.groundY,
      source: r.source,
    );
  }
  // Texture with a sticker border.
  final b = options.border;
  final tw = w + 2 * b, th = h + 2 * b;
  final tex = options.simplified
      ? _posterise(rgba, w, h, b)
      : _withBorder(rgba, w, h, b);
  final shifted = _shift(r, b.toDouble());
  lap('texture');
  final texMask = BinMask.fromRgba(tex, tw, th, threshold: 1);
  final cells = options.simplified ? 14 : options.gridCells;
  final mesh = _gridMesh(texMask, cells);
  lap('mesh');
  final bones = bonesOf(shifted);
  final (bi, bw) = _weights(
    texMask,
    mesh.rest,
    mesh.repPixel,
    bones,
    options.weightRes,
    options.weightPower,
  );
  lap('weights');
  return RiggedCharacter(
    rig: shifted,
    bones: bones,
    textureRgba: tex,
    texW: tw,
    texH: th,
    rest: mesh.rest,
    indices: mesh.indices,
    boneIdx: bi,
    boneW: bw,
    micros: micros,
    simplified: options.simplified,
  );
}

CharacterRig _shift(CharacterRig r, double d) {
  V2 s(V2 p) => V2(p.x + d, p.y + d);
  return CharacterRig(
    width: r.width + 2 * d,
    height: r.height + 2 * d,
    root: s(r.root),
    chest: s(r.chest),
    limbs: [
      for (final l in r.limbs)
        RigLimb(l.kind, s(l.base), s(l.mid), s(l.tip))..edited = l.edited,
    ],
    ground: r.ground == null ? null : r.ground! + d,
    source: r.source,
  );
}

/// Copies the drawing into a padded canvas and paints a soft white border
/// of [b] px around the opaque pixels (a "sticker" look).
Uint8List _withBorder(Uint8List rgba, int w, int h, int b) {
  final tw = w + 2 * b, th = h + 2 * b;
  final out = Uint8List(tw * th * 4);
  final m = BinMask(tw, th);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] >= 128) m.data[(y + b) * tw + x + b] = 1;
    }
  }
  if (b > 0) {
    final grown = m.dilate(b);
    for (var i = 0; i < tw * th; i++) {
      if (grown.data[i] == 0) continue;
      out[i * 4] = 255;
      out[i * 4 + 1] = 255;
      out[i * 4 + 2] = 255;
      out[i * 4 + 3] = 255;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final s = (y * w + x) * 4;
      final a = rgba[s + 3];
      if (a == 0) continue;
      final o = ((y + b) * tw + x + b) * 4;
      // Blend over the white border (straight alpha).
      final bgA = out[o + 3];
      for (var c = 0; c < 3; c++) {
        out[o + c] = ((rgba[s + c] * a + out[o + c] * (255 - a)) ~/ 255);
      }
      out[o + 3] = math.max(a, bgA);
    }
  }
  return out;
}

/// The simplified look: rounded silhouette in 3 flat colours (k-means on
/// the drawing), dark outline, no details.
Uint8List _posterise(Uint8List rgba, int w, int h, int b) {
  final tw = w + 2 * b, th = h + 2 * b;
  var m = BinMask(tw, th);
  final cols = <int>[];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final s = (y * w + x) * 4;
      if (rgba[s + 3] < 128) continue;
      m.data[(y + b) * tw + x + b] = 1;
      if ((x + y) % 3 == 0) {
        cols.add(rgba[s] << 16 | rgba[s + 1] << 8 | rgba[s + 2]);
      }
    }
  }
  // Rounded shape: close + open with a radius relative to the size.
  final rr = math.max(2, (math.max(w, h) * 0.04).round());
  m = m.close(rr).fillHoles().open(rr);
  final pal = _kmeans(cols, 3);
  // Lightest-but-saturated colour as the fill, darkest as outline.
  pal.sort((a, c) => _lum(c).compareTo(_lum(a)));
  final fill = pal.length > 1 ? pal[1] : 0x88AADD;
  final shade = pal.isNotEmpty ? pal.first : 0xAACCEE;
  final dist = m.insideDistance();
  var maxD = 1.0;
  for (final d in dist) {
    if (d > maxD) maxD = d;
  }
  final out = Uint8List(tw * th * 4);
  for (var i = 0; i < tw * th; i++) {
    if (m.data[i] == 0) continue;
    final d = dist[i];
    final y = i ~/ tw;
    final int c;
    if (d < 3) {
      c = 0x303040;
    } else if (y < th * 0.42 && d > maxD * 0.35) {
      c = shade;
    } else {
      c = fill;
    }
    out[i * 4] = c >> 16 & 255;
    out[i * 4 + 1] = c >> 8 & 255;
    out[i * 4 + 2] = c & 255;
    out[i * 4 + 3] = 255;
  }
  return out;
}

double _lum(int c) =>
    0.3 * (c >> 16 & 255) + 0.59 * (c >> 8 & 255) + 0.11 * (c & 255);

List<int> _kmeans(List<int> cols, int k) {
  if (cols.isEmpty) return [0x88AADD];
  final cs = <List<double>>[
    for (var i = 0; i < k; i++)
      () {
        final c = cols[(i * cols.length) ~/ k];
        return [(c >> 16 & 255) * 1.0, (c >> 8 & 255) * 1.0, (c & 255) * 1.0];
      }(),
  ];
  for (var it = 0; it < 8; it++) {
    final sum = List.generate(k, (_) => [0.0, 0.0, 0.0, 0.0]);
    for (final c in cols) {
      final r = (c >> 16 & 255) * 1.0, g = (c >> 8 & 255) * 1.0;
      final bl = (c & 255) * 1.0;
      var best = 0;
      var bd = double.infinity;
      for (var j = 0; j < k; j++) {
        final d = math.pow(r - cs[j][0], 2) +
            math.pow(g - cs[j][1], 2) +
            math.pow(bl - cs[j][2], 2);
        if (d < bd) {
          bd = d.toDouble();
          best = j;
        }
      }
      sum[best][0] += r;
      sum[best][1] += g;
      sum[best][2] += bl;
      sum[best][3] += 1;
    }
    for (var j = 0; j < k; j++) {
      if (sum[j][3] == 0) continue;
      for (var c = 0; c < 3; c++) {
        cs[j][c] = sum[j][c] / sum[j][3];
      }
    }
  }
  return [
    for (final c in cs)
      c[0].round().clamp(0, 255) << 16 |
          c[1].round().clamp(0, 255) << 8 |
          c[2].round().clamp(0, 255),
  ];
}

class _Mesh {
  _Mesh(this.rest, this.indices, this.repPixel);
  final Float32List rest;
  final Uint16List indices;

  /// A mask pixel (index) that belongs to each vertex's cluster.
  final Int32List repPixel;
}

/// Grid mesh: every cell that touches the drawing becomes 2 triangles.
/// Cells that touch only locally-unconnected parts (an arm passing close
/// to a leg) do **not** share corner vertices, so limbs separate cleanly
/// when they move. The exact outline comes from the texture's alpha.
_Mesh _gridMesh(BinMask m, int gridCells) {
  final w = m.w, h = m.h;
  final c = math.max(2, (math.max(w, h) / gridCells).ceil());
  final gx = (w / c).ceil(), gy = (h / c).ceil();
  final cellOn = Uint8List(gx * gy);
  final cellCount = Int32List(gx * gy);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (m.data[y * w + x] != 0) {
        cellOn[(y ~/ c) * gx + x ~/ c] = 1;
        cellCount[(y ~/ c) * gx + x ~/ c]++;
      }
    }
  }
  // A cell is "full" when every pixel is set (and it lies inside the
  // image): full cells around a vertex are always connected.
  bool full(int cid) {
    final cx = cid % gx, cy = cid ~/ gx;
    final cw = math.min(c, w - cx * c), chh = math.min(c, h - cy * c);
    return cw == c && chh == c && cellCount[cid] == c * c;
  }

  // corner[cell*4 + k] = vertex index, k: 0 TL, 1 TR, 2 BR, 3 BL.
  final corner = Int32List(gx * gy * 4)..fillRange(0, gx * gy * 4, -1);
  final rest = <double>[];
  final rep = <int>[];
  final lab = Int32List(4 * c * c);
  final stack = <int>[];
  for (var vy = 0; vy <= gy; vy++) {
    for (var vx = 0; vx <= gx; vx++) {
      // The 4 cells around this grid vertex: TL, TR, BL, BR.
      final cellIds = <int>[];
      final cornerK = <int>[];
      for (final (dx, dy, k) in const [
        (-1, -1, 2),
        (0, -1, 3),
        (-1, 0, 1),
        (0, 0, 0),
      ]) {
        final cx = vx + dx, cy = vy + dy;
        if (cx < 0 || cy < 0 || cx >= gx || cy >= gy) continue;
        if (cellOn[cy * gx + cx] == 0) continue;
        cellIds.add(cy * gx + cx);
        cornerK.add(k);
      }
      if (cellIds.isEmpty) continue;
      if (cellIds.every(full)) {
        final v = rest.length ~/ 2;
        rest
          ..add((vx * c).toDouble())
          ..add((vy * c).toDouble());
        final cid = cellIds.first;
        final px = math.min(w - 1, vx * c), py = math.min(h - 1, vy * c);
        rep.add(m.data[py * w + px] != 0
            ? py * w + px
            : ((cid ~/ gx) * c) * w + (cid % gx) * c);
        for (var s = 0; s < cellIds.length; s++) {
          corner[cellIds[s] * 4 + cornerK[s]] = v;
        }
        continue;
      }
      // Label mask pixels of the 2c×2c block around the vertex.
      final x0 = (vx - 1) * c, y0 = (vy - 1) * c;
      final bw = 2 * c;
      lab.fillRange(0, lab.length, 0);
      var next = 0;
      for (var by = 0; by < bw; by++) {
        for (var bx = 0; bx < bw; bx++) {
          final px = x0 + bx, py = y0 + by;
          if (px < 0 || py < 0 || px >= w || py >= h) continue;
          if (m.data[py * w + px] == 0 || lab[by * bw + bx] != 0) continue;
          next++;
          lab[by * bw + bx] = next;
          stack.add(by * bw + bx);
          while (stack.isNotEmpty) {
            final q = stack.removeLast();
            final qx = q % bw, qy = q ~/ bw;
            for (var ny = qy - 1; ny <= qy + 1; ny++) {
              for (var nx = qx - 1; nx <= qx + 1; nx++) {
                if (nx < 0 || ny < 0 || nx >= bw || ny >= bw) continue;
                final ax = x0 + nx, ay = y0 + ny;
                if (ax < 0 || ay < 0 || ax >= w || ay >= h) continue;
                if (m.data[ay * w + ax] == 0 || lab[ny * bw + nx] != 0) {
                  continue;
                }
                lab[ny * bw + nx] = next;
                stack.add(ny * bw + nx);
              }
            }
          }
        }
      }
      // Union-find over cells through shared labels.
      final parent = List<int>.generate(cellIds.length, (i) => i);
      int find(int i) {
        while (parent[i] != i) {
          i = parent[i] = parent[parent[i]];
        }
        return i;
      }

      final labelOwner = <int, int>{};
      final repOf = <int, int>{}; // cell slot → a pixel index
      for (var s = 0; s < cellIds.length; s++) {
        final cid = cellIds[s];
        final cx = cid % gx, cy = cid ~/ gx;
        // Block-local origin of this cell.
        final ox = cx * c - x0, oy = cy * c - y0;
        var bestD = 1 << 30;
        for (var yy = 0; yy < c; yy++) {
          for (var xx = 0; xx < c; xx++) {
            final l = lab[(oy + yy) * bw + ox + xx];
            if (l == 0) continue;
            final owner = labelOwner[l];
            if (owner == null) {
              labelOwner[l] = s;
            } else {
              final a = find(owner), b2 = find(s);
              if (a != b2) parent[a] = b2;
            }
            // Representative pixel nearest the vertex.
            final ddx = (ox + xx) - c, ddy = (oy + yy) - c;
            final dd = ddx * ddx + ddy * ddy;
            if (dd < bestD) {
              bestD = dd;
              repOf[s] = (y0 + oy + yy) * w + x0 + ox + xx;
            }
          }
        }
      }
      final vertexOfRoot = <int, int>{};
      for (var s = 0; s < cellIds.length; s++) {
        final root = find(s);
        var v = vertexOfRoot[root];
        if (v == null) {
          v = rest.length ~/ 2;
          vertexOfRoot[root] = v;
          rest
            ..add((vx * c).toDouble())
            ..add((vy * c).toDouble());
          rep.add(repOf[s] ?? -1);
        } else if (rep[v] < 0 && repOf[s] != null) {
          rep[v] = repOf[s]!;
        }
        corner[cellIds[s] * 4 + cornerK[s]] = v;
      }
    }
  }
  final idx = <int>[];
  for (var cid = 0; cid < gx * gy; cid++) {
    if (cellOn[cid] == 0) continue;
    final tl = corner[cid * 4], tr = corner[cid * 4 + 1];
    final br = corner[cid * 4 + 2], bl = corner[cid * 4 + 3];
    idx.addAll([tl, tr, br, tl, br, bl]);
  }
  if (rest.length ~/ 2 > 65535) {
    throw StateError('mesh too large: ${rest.length ~/ 2} vertices');
  }
  return _Mesh(
    Float32List.fromList(rest),
    Uint16List.fromList(idx),
    Int32List.fromList(rep),
  );
}

/// Linear-blend-skinning weights from geodesic (inside-the-drawing)
/// distances to each bone: w ∝ 1/(1 + d)^p, best 4, normalised. Geodesic
/// distance keeps an arm's weight from leaking into a nearby leg.
(Uint8List, Float32List) _weights(
  BinMask m,
  Float32List rest,
  Int32List rep,
  List<Bone> bones,
  int res,
  double power,
) {
  final n = rest.length ~/ 2;
  final bi = Uint8List(n * 4);
  final bw = Float32List(n * 4);
  final skinned = [
    for (var i = 0; i < bones.length; i++)
      if (bones[i].skinned) i,
  ];
  if (skinned.length <= 1) {
    for (var v = 0; v < n; v++) {
      bi[v * 4] = skinned.isEmpty ? 0 : skinned.first;
      bw[v * 4] = 1;
    }
    return (bi, bw);
  }
  // Coarse grid for distances.
  final s = math.max(1.0, math.max(m.w, m.h) / res);
  final cw = (m.w / s).ceil(), ch = (m.h / s).ceil();
  final coarse = Uint8List(cw * ch);
  for (var y = 0; y < m.h; y++) {
    for (var x = 0; x < m.w; x++) {
      if (m.data[y * m.w + x] != 0) {
        coarse[(y / s).floor() * cw + (x / s).floor()] = 1;
      }
    }
  }
  final fields = <Float64List>[];
  for (final b in skinned) {
    fields.add(_geodesic(coarse, cw, ch, bones[b], s));
  }
  final d = Float64List(skinned.length);
  final order = List<int>.generate(skinned.length, (i) => i);
  for (var v = 0; v < n; v++) {
    final p = rep[v];
    final px = p >= 0 ? (p % m.w).toDouble() : rest[v * 2];
    final py = p >= 0 ? (p ~/ m.w).toDouble() : rest[v * 2 + 1];
    final ci = (py / s).floor().clamp(0, ch - 1) * cw +
        (px / s).floor().clamp(0, cw - 1);
    for (var k = 0; k < skinned.length; k++) {
      var dist = fields[k][ci];
      if (!dist.isFinite) {
        // Detached part: Euclidean distance to the bone (×2 penalty).
        dist = 2 * _segDist(px, py, bones[skinned[k]]) / s;
      }
      d[k] = dist;
    }
    order.sort((a, b) => d[a].compareTo(d[b]));
    var sum = 0.0;
    final top = math.min(4, skinned.length);
    final ws = List<double>.filled(top, 0);
    for (var k = 0; k < top; k++) {
      ws[k] = 1 / math.pow(1 + d[order[k]], power);
      sum += ws[k];
    }
    for (var k = 0; k < top; k++) {
      bi[v * 4 + k] = skinned[order[k]];
      bw[v * 4 + k] = ws[k] / sum;
    }
  }
  return (bi, bw);
}

double _segDist(double x, double y, Bone b) {
  final ax = b.from.x, ay = b.from.y;
  final dx = b.to.x - ax, dy = b.to.y - ay;
  final l2 = dx * dx + dy * dy;
  var t = l2 == 0 ? 0.0 : ((x - ax) * dx + (y - ay) * dy) / l2;
  t = t.clamp(0.0, 1.0);
  final ex = ax + t * dx - x, ey = ay + t * dy - y;
  return math.sqrt(ex * ex + ey * ey);
}

/// Dijkstra (8-neighbour) distance inside the coarse mask from the bone's
/// segment; infinity where unreachable.
Float64List _geodesic(Uint8List mask, int w, int h, Bone b, double s) {
  final dist = Float64List(w * h)..fillRange(0, w * h, double.infinity);
  final heap = _Heap();
  final ax = b.from.x / s, ay = b.from.y / s;
  final bx = b.to.x / s, by = b.to.y / s;
  final steps = math.max(1, (math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)) * 2).ceil());
  var seeded = false;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final x = (ax + (bx - ax) * t).floor(), y = (ay + (by - ay) * t).floor();
    if (x < 0 || y < 0 || x >= w || y >= h) continue;
    final q = y * w + x;
    if (mask[q] == 0 || dist[q] == 0) continue;
    dist[q] = 0;
    heap.push(0, q);
    seeded = true;
  }
  if (!seeded) {
    // Bone outside the drawing (edited badly): seed the nearest pixel.
    final mx = ((ax + bx) / 2), my = ((ay + by) / 2);
    var best = -1;
    var bd = double.infinity;
    for (var q = 0; q < w * h; q++) {
      if (mask[q] == 0) continue;
      final dx = q % w - mx, dy = q ~/ w - my;
      final dd = dx * dx + dy * dy;
      if (dd < bd) {
        bd = dd;
        best = q;
      }
    }
    if (best < 0) return dist;
    dist[best] = math.sqrt(bd);
    heap.push(dist[best], best);
  }
  const diag = 1.41421356;
  while (heap.isNotEmpty) {
    final (dq, q) = heap.pop();
    if (dq > dist[q]) continue;
    final x = q % w, y = q ~/ w;
    for (var ny = y - 1; ny <= y + 1; ny++) {
      if (ny < 0 || ny >= h) continue;
      for (var nx = x - 1; nx <= x + 1; nx++) {
        if (nx < 0 || nx >= w || (nx == x && ny == y)) continue;
        final r = ny * w + nx;
        if (mask[r] == 0) continue;
        final nd = dq + (nx != x && ny != y ? diag : 1.0);
        if (nd < dist[r]) {
          dist[r] = nd;
          heap.push(nd, r);
        }
      }
    }
  }
  return dist;
}

class _Heap {
  final _k = <double>[];
  final _v = <int>[];
  bool get isNotEmpty => _k.isNotEmpty;

  void push(double k, int v) {
    _k.add(k);
    _v.add(v);
    var i = _k.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_k[p] <= _k[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  (double, int) pop() {
    final k = _k.first, v = _v.first;
    final lk = _k.removeLast(), lv = _v.removeLast();
    if (_k.isNotEmpty) {
      _k[0] = lk;
      _v[0] = lv;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _k.length && _k[l] < _k[m]) m = l;
        if (r < _k.length && _k[r] < _k[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return (k, v);
  }

  void _swap(int a, int b) {
    final tk = _k[a];
    _k[a] = _k[b];
    _k[b] = tk;
    final tv = _v[a];
    _v[a] = _v[b];
    _v[b] = tv;
  }
}
