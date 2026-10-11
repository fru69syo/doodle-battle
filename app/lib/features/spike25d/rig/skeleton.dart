import 'dart:math' as math;
import 'dart:typed_data';

import 'bin_mask.dart';

/// Medial skeleton of a silhouette as a small graph (nodes = endpoints and
/// junctions, edges = 1-px pixel chains), built by Zhang–Suen thinning,
/// redundant-pixel removal and significance pruning. Because the rigger
/// fills holes first, the skeleton is a tree.
class SkeletonGraph {
  SkeletonGraph._(this.w, this.h, this.pixels, this.nodes, this.edges);

  final int w, h;

  /// 1 where the (pruned) skeleton is.
  final Uint8List pixels;
  final List<SkelNode> nodes;
  final List<SkelEdge> edges;

  Iterable<SkelEdge> edgesOf(int node) =>
      edges.where((e) => e.a == node || e.b == node);

  int degree(int node) => edgesOf(node).length;

  /// Builds the pruned skeleton of [mask]; [dist] is its inside distance.
  /// A leaf branch survives when it sticks out of its junction's inscribed
  /// circle by more than `max(minProtrusion, protrusionRatio·r_junction)`.
  static SkeletonGraph build(
    BinMask mask,
    Float64List dist, {
    double minProtrusion = 3,
    double protrusionRatio = 0.5,
  }) {
    final w = mask.w, h = mask.h;
    final px = zhangSuen(mask);
    _removeRedundant(px, w, h);
    var g = _graph(px, w, h, dist);
    // Prune the least significant leaf branch until all are significant.
    for (var iter = 0; iter < 400; iter++) {
      SkelEdge? worst;
      var worstScore = double.infinity;
      for (final e in g.edges) {
        final leafA = g.nodes[e.a].isEnd, leafB = g.nodes[e.b].isEnd;
        if (leafA == leafB) continue; // internal edge, or an isolated line
        final tip = leafA ? g.nodes[e.a] : g.nodes[e.b];
        final base = leafA ? g.nodes[e.b] : g.nodes[e.a];
        final p = protrusion(tip, base, dist, w);
        final need = math.max(minProtrusion, protrusionRatio * base.radius);
        final score = p / need;
        if (score < 1 && score < worstScore) {
          worstScore = score;
          worst = e;
        }
      }
      if (worst == null) break;
      final tipNode = g.nodes[worst.a].isEnd ? worst.a : worst.b;
      for (final i in worst.path) {
        px[i] = 0;
      }
      for (final i in g.nodes[tipNode].pix) {
        px[i] = 0;
      }
      _removeRedundant(px, w, h);
      g = _graph(px, w, h, dist);
    }
    return g;
  }

  /// How far the leaf at [tip] reaches out of the inscribed circle of
  /// [base]: |tip − base| + r(tip) − r(base).
  static double protrusion(
    SkelNode tip,
    SkelNode base,
    Float64List dist,
    int w,
  ) {
    final dx = tip.x - base.x, dy = tip.y - base.y;
    return math.sqrt(dx * dx + dy * dy) + tip.radius - base.radius;
  }

  /// Zhang–Suen thinning (1-px, 8-connected, topology preserving).
  static Uint8List zhangSuen(BinMask mask) {
    final w = mask.w, h = mask.h;
    final img = Uint8List.fromList(mask.data);
    final del = <int>[];
    var changed = true;
    while (changed) {
      changed = false;
      for (var pass = 0; pass < 2; pass++) {
        del.clear();
        for (var y = 1; y < h - 1; y++) {
          for (var x = 1; x < w - 1; x++) {
            final i = y * w + x;
            if (img[i] == 0) continue;
            final p2 = img[i - w], p3 = img[i - w + 1], p4 = img[i + 1];
            final p5 = img[i + w + 1], p6 = img[i + w], p7 = img[i + w - 1];
            final p8 = img[i - 1], p9 = img[i - w - 1];
            final b = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
            if (b < 2 || b > 6) continue;
            var a = 0;
            if (p2 == 0 && p3 == 1) a++;
            if (p3 == 0 && p4 == 1) a++;
            if (p4 == 0 && p5 == 1) a++;
            if (p5 == 0 && p6 == 1) a++;
            if (p6 == 0 && p7 == 1) a++;
            if (p7 == 0 && p8 == 1) a++;
            if (p8 == 0 && p9 == 1) a++;
            if (p9 == 0 && p2 == 1) a++;
            if (a != 1) continue;
            if (pass == 0) {
              if (p2 * p4 * p6 != 0 || p4 * p6 * p8 != 0) continue;
            } else {
              if (p2 * p4 * p8 != 0 || p2 * p6 * p8 != 0) continue;
            }
            del.add(i);
          }
        }
        for (final i in del) {
          img[i] = 0;
        }
        if (del.isNotEmpty) changed = true;
      }
    }
    return img;
  }

  static const _dx = [-1, 0, 1, 1, 1, 0, -1, -1];
  static const _dy = [-1, -1, -1, 0, 1, 1, 1, 0];

  static int _deg(Uint8List px, int w, int h, int i) {
    final x = i % w, y = i ~/ w;
    var n = 0;
    for (var k = 0; k < 8; k++) {
      final xx = x + _dx[k], yy = y + _dy[k];
      if (xx >= 0 && yy >= 0 && xx < w && yy < h && px[yy * w + xx] != 0) n++;
    }
    return n;
  }

  /// Removes pixels whose skeleton neighbours stay 8-connected without them
  /// (staircase corners, fat junctions), so degree counts are meaningful.
  static void _removeRedundant(Uint8List px, int w, int h) {
    var changed = true;
    while (changed) {
      changed = false;
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < w - 1; x++) {
          final i = y * w + x;
          if (px[i] == 0) continue;
          // Ring of the 8 neighbours in circular order.
          final ring = List<int>.generate(
            8,
            (k) => px[(y + _dy[k]) * w + x + _dx[k]],
          );
          final count = ring.fold<int>(0, (s, v) => s + v);
          if (count < 2) continue;
          if (_ringConnected(ring)) {
            px[i] = 0;
            changed = true;
          }
        }
      }
    }
  }

  /// Whether the set neighbours of a ring are one 8-connected group
  /// (without the centre pixel).
  static bool _ringConnected(List<int> ring) {
    // Neighbour positions.
    final pos = <int>[
      for (var k = 0; k < 8; k++)
        if (ring[k] != 0) k,
    ];
    final seen = <int>{pos.first};
    final stack = [pos.first];
    while (stack.isNotEmpty) {
      final k = stack.removeLast();
      for (final m in pos) {
        if (seen.contains(m)) continue;
        final ddx = (_dx[k] - _dx[m]).abs(), ddy = (_dy[k] - _dy[m]).abs();
        if (ddx <= 1 && ddy <= 1) {
          seen.add(m);
          stack.add(m);
        }
      }
    }
    return seen.length == pos.length;
  }

  static SkeletonGraph _graph(Uint8List px, int w, int h, Float64List dist) {
    final nodeOf = Int32List(w * h)..fillRange(0, w * h, -1);
    final nodes = <SkelNode>[];
    // Nodes: endpoint pixels and clusters of junction pixels.
    for (var i = 0; i < w * h; i++) {
      if (px[i] == 0 || nodeOf[i] >= 0) continue;
      final d = _deg(px, w, h, i);
      if (d == 2) continue;
      final id = nodes.length;
      final pix = <int>[i];
      nodeOf[i] = id;
      if (d >= 3) {
        // Grow the junction cluster through adjacent junction pixels.
        for (var k = 0; k < pix.length; k++) {
          final j = pix[k];
          final x = j % w, y = j ~/ w;
          for (var n = 0; n < 8; n++) {
            final xx = x + _dx[n], yy = y + _dy[n];
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            final q = yy * w + xx;
            if (px[q] != 0 && nodeOf[q] < 0 && _deg(px, w, h, q) >= 3) {
              nodeOf[q] = id;
              pix.add(q);
            }
          }
        }
      }
      var sx = 0.0, sy = 0.0;
      for (final j in pix) {
        sx += j % w;
        sy += j ~/ w;
      }
      var r = 0.0;
      for (final j in pix) {
        r = math.max(r, dist[j]);
      }
      nodes.add(
        SkelNode(id, sx / pix.length, sy / pix.length, pix, isEnd: d <= 1)
          ..radius = r,
      );
    }
    // Edges: walk from each node through degree-2 pixels.
    final edges = <SkelEdge>[];
    final used = Uint8List(w * h);
    for (final n in nodes) {
      for (final start in n.pix) {
        final sx = start % w, sy = start ~/ w;
        for (var k = 0; k < 8; k++) {
          final xx = sx + _dx[k], yy = sy + _dy[k];
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          final q = yy * w + xx;
          if (px[q] == 0 || nodeOf[q] == n.id) continue;
          if (nodeOf[q] >= 0) {
            // Directly adjacent nodes: zero-length edge (store once).
            if (nodeOf[q] > n.id &&
                !edges.any(
                  (e) =>
                      (e.a == n.id && e.b == nodeOf[q]) ||
                      (e.b == n.id && e.a == nodeOf[q]),
                )) {
              edges.add(SkelEdge(n.id, nodeOf[q], const []));
            }
            continue;
          }
          if (used[q] != 0) continue;
          final path = <int>[];
          var prev = start, cur = q;
          var end = -1;
          while (true) {
            path.add(cur);
            used[cur] = 1;
            final cx = cur % w, cy = cur ~/ w;
            var next = -1;
            for (var m = 0; m < 8; m++) {
              final ax = cx + _dx[m], ay = cy + _dy[m];
              if (ax < 0 || ay < 0 || ax >= w || ay >= h) continue;
              final r = ay * w + ax;
              if (px[r] == 0 || r == prev) continue;
              if (nodeOf[r] >= 0 && nodeOf[r] != n.id ||
                  nodeOf[r] == n.id && path.length > 1) {
                end = nodeOf[r];
                break;
              }
              if (nodeOf[r] < 0 && used[r] == 0) next = r;
            }
            if (end >= 0 || next < 0) break;
            prev = cur;
            cur = next;
          }
          if (end < 0) continue; // dangling loop remnant
          edges.add(SkelEdge(n.id, end, path));
        }
      }
    }
    // An isolated closed loop or a lone line is handled by its end nodes;
    // a single pixel skeleton (a disc) is one end node with no edge.
    return SkeletonGraph._(w, h, px, nodes, edges);
  }
}

class SkelNode {
  SkelNode(this.id, this.x, this.y, this.pix, {required this.isEnd});
  final int id;
  final double x, y;
  final List<int> pix;
  final bool isEnd;

  /// Inscribed-circle radius at the node.
  double radius = 0;
}

class SkelEdge {
  SkelEdge(this.a, this.b, this.path);
  final int a, b;

  /// Pixel indices strictly between the two nodes, ordered from [a] to [b].
  final List<int> path;
  int other(int n) => n == a ? b : a;
}
