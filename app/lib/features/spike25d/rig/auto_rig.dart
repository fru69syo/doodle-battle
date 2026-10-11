import 'dart:math' as math;
import 'dart:typed_data';

import 'bin_mask.dart';
import 'rig.dart';
import 'skeleton.dart';

/// Tunables of the auto-rigger (defaults tuned on the Amateur Drawings
/// sample, docs/V2_25D_TECH.md §2).
class AutoRigOptions {
  const AutoRigOptions({
    this.workSize = 160,
    this.minCoverage = 0.3,
    this.minProtrusionFrac = 0.03,
    this.protrusionRatio = 0.25,
    this.fingerFrac = 0.12,
  });

  /// Longest side of the working mask (px).
  final int workSize;
  final double minCoverage;

  /// A leaf must stick out at least this fraction of the figure size...
  final double minProtrusionFrac;

  /// ...and this multiple of its junction's inscribed radius.
  final double protrusionRatio;

  /// Leaves shorter than this fraction of the size that share a junction
  /// with other short leaves are fingers/toes and get merged.
  final double fingerFrac;
}

/// Result plus diagnostics (for the editor overlay, tests and the
/// evaluation on real drawings).
class AutoRigResult {
  AutoRigResult({
    required this.rig,
    required this.work,
    required this.scale,
    required this.pad,
    required this.skeleton,
    required this.dist,
    required this.micros,
  });

  final CharacterRig rig;

  /// Working mask (hole-filled, largest component) and its geometry.
  final BinMask work;
  final double scale;
  final int pad;
  final SkeletonGraph skeleton;
  final Float64List dist;
  final int micros;

  /// Working-mask pixel → drawing pixels.
  V2 toDrawing(double x, double y) =>
      V2((x - pad + 0.5) * scale + offX, (y - pad + 0.5) * scale + offY);

  /// Offset of the cropped figure inside the drawing.
  double offX = 0, offY = 0;
}

/// Auto-rigs a drawing from its silhouette ([mask] at drawing resolution,
/// e.g. alpha ≥ 128 of the cut-out). Pure Dart, deterministic.
AutoRigResult autoRig(
  BinMask mask, {
  AutoRigOptions o = const AutoRigOptions(),
}) {
  final sw = Stopwatch()..start();
  // Work on the figure's own box so small figures get the full
  // resolution (the app's cut-out is already cropped).
  final fb = mask.bounds() ?? [0, 0, mask.w - 1, mask.h - 1];
  final fig = mask.crop(fb[0], fb[1], fb[2], fb[3]);
  final offX = fb[0].toDouble(), offY = fb[1].toDouble();
  final longest = math.max(fig.w, fig.h);
  final scale = math.max(0.25, longest / o.workSize);
  const pad = 2;
  final work = fig
      .downscale(scale, pad: pad, minCoverage: o.minCoverage)
      .close(1)
      .fillHoles()
      .largestComponents();
  final dist = work.insideDistance();
  final b = work.bounds();
  V2 d(double x, double y) =>
      V2((x - pad + 0.5) * scale + offX, (y - pad + 0.5) * scale + offY);
  if (b == null) {
    final rig = CharacterRig(
      width: mask.w.toDouble(),
      height: mask.h.toDouble(),
      root: V2(mask.w / 2, mask.h * 0.9),
      chest: V2(mask.w / 2, mask.h * 0.5),
      limbs: [],
    );
    return AutoRigResult(
      rig: rig,
      work: work,
      scale: scale,
      pad: pad,
      skeleton: SkeletonGraph.build(work, dist),
      dist: dist,
      micros: sw.elapsedMicroseconds,
    );
  }
  final size = math.max(b[2] - b[0] + 1, b[3] - b[1] + 1).toDouble();
  final skel = SkeletonGraph.build(
    work,
    dist,
    minProtrusion: math.max(2, o.minProtrusionFrac * size),
    protrusionRatio: o.protrusionRatio,
  );
  final rig = _assign(work, dist, skel, b, size, o, d)
    ..ground = (b[3] - pad + 1) * scale + offY;
  return AutoRigResult(
      rig: CharacterRig(
        width: mask.w.toDouble(),
        height: mask.h.toDouble(),
        root: rig.root,
        chest: rig.chest,
        limbs: rig.limbs,
        ground: rig.ground,
      ),
      work: work,
      scale: scale,
      pad: pad,
      skeleton: skel,
      dist: dist,
      micros: sw.elapsedMicroseconds,
    )
    ..offX = offX
    ..offY = offY;
}

class _Leaf {
  _Leaf(this.tip, this.junction, this.path, this.length);
  final SkelNode tip;
  final SkelNode junction;

  /// Pixel positions (work px) from the junction to the tip, inclusive.
  final List<(double, double)> path;
  final double length;

  double get tx => tip.x;
  double get ty => tip.y;
}

CharacterRig _assign(
  BinMask work,
  Float64List dist,
  SkeletonGraph g,
  List<int> b,
  double size,
  AutoRigOptions o,
  V2 Function(double, double) d,
) {
  final w = work.w;
  final bw = (b[2] - b[0] + 1).toDouble();
  final bh = (b[3] - b[1] + 1).toDouble();
  // Mask centroid.
  var cx = 0.0, cy = 0.0, n = 0;
  for (var i = 0; i < work.data.length; i++) {
    if (work.data[i] == 0) continue;
    cx += i % w;
    cy += i ~/ w;
    n++;
  }
  cx /= n;
  cy /= n;

  // Leaf branches (endpoint → first junction).
  var leaves = <_Leaf>[];
  for (final e in g.edges) {
    final na = g.nodes[e.a], nb = g.nodes[e.b];
    if (na.isEnd == nb.isEnd) continue;
    final tip = na.isEnd ? na : nb;
    final jn = na.isEnd ? nb : na;
    final pix = na.isEnd ? e.path.reversed.toList() : e.path;
    final path = <(double, double)>[
      (jn.x, jn.y),
      for (final i in pix) ((i % w).toDouble(), (i ~/ w).toDouble()),
      (tip.x, tip.y),
    ];
    var len = 0.0;
    for (var k = 1; k < path.length; k++) {
      len += _dist(path[k - 1], path[k]);
    }
    leaves.add(_Leaf(tip, jn, path, len));
  }

  // Fingers / toes: several short leaves on one junction whose other edge
  // is long → collapse them into the junction (the hand).
  final byJunction = <int, List<_Leaf>>{};
  for (final l in leaves) {
    byJunction.putIfAbsent(l.junction.id, () => []).add(l);
  }
  final collapsed = <_Leaf>[];
  for (final entry in byJunction.entries) {
    final ls = entry.value;
    final deg = g.degree(entry.key);
    final short = ls.where((l) => l.length < o.fingerFrac * size).toList();
    if (short.length >= 2 && deg - short.length == 1 && ls.length == deg) {
      // The junction is a hand: replace it by one leaf following the
      // remaining edge back to the next junction.
      final j = g.nodes[entry.key];
      final e = g
          .edgesOf(entry.key)
          .firstWhere(
            (e) => !g.nodes[e.other(entry.key)].isEnd,
            orElse: () => g.edgesOf(entry.key).first,
          );
      final other = g.nodes[e.other(entry.key)];
      final pix = e.a == other.id ? e.path : e.path.reversed.toList();
      final path = <(double, double)>[
        (other.x, other.y),
        for (final i in pix) ((i % w).toDouble(), (i ~/ w).toDouble()),
        (j.x, j.y),
      ];
      var len = 0.0;
      for (var k = 1; k < path.length; k++) {
        len += _dist(path[k - 1], path[k]);
      }
      collapsed.add(_Leaf(j, other, path, len));
      leaves.removeWhere((l) => ls.contains(l));
    }
  }
  leaves = [...leaves, ...collapsed];

  final landscape = bw > bh * 1.25;
  final used = <_Leaf>{};
  double ang(_Leaf l) =>
      math.atan2(l.tx - cx, -(l.ty - cy)) * 180 / math.pi; // 0 = up

  // Legs: tips low in the bounding box, pointing down.
  final legCands =
      leaves
          .where(
            (l) => l.ty > cy && ang(l).abs() > 95 && l.ty > b[1] + 0.6 * bh,
          )
          .toList()
        ..sort((a, c) => c.ty.compareTo(a.ty));
  final legs = legCands.take(landscape ? 4 : 2).toList();
  used.addAll(legs);

  // Head (upright figures): the biggest inscribed circle in the upper
  // part of the figure, favouring height and the centre line. Kids draw
  // big round heads, so this beats "the topmost leaf" (hair, hats, ears).
  final maxR = dist.reduce(math.max);
  (double, double, double)? headDisc; // x, y, r
  if (!landscape) {
    var bestS = 0.0;
    for (var y = b[1]; y <= b[1] + 0.6 * bh; y++) {
      for (var x = b[0]; x <= b[2]; x++) {
        final r = dist[y * w + x];
        if (r <= 0) continue;
        final s =
            r * (1.15 - 0.5 * (y - b[1]) / bh) -
            0.35 * maxR * (x - cx).abs() / bw;
        if (s > bestS) {
          bestS = s;
          headDisc = (x.toDouble(), y.toDouble(), r);
        }
      }
    }
    if (headDisc != null) {
      final (hx, hy, hr) = headDisc;
      // A single round blob is not a head on a body.
      final tooBig = hr > 0.42 * math.min(bw, bh) && hy > b[1] + 0.3 * bh;
      if (tooBig || hr < 0.04 * size) headDisc = null;
    }
  }
  bool inHead(_Leaf l) {
    if (headDisc == null) return false;
    final (hx, hy, hr) = headDisc;
    double dd(double x, double y) =>
        math.sqrt((x - hx) * (x - hx) + (y - hy) * (y - hy));
    // Ends inside the head (the neck branch), or sticks out of the top of
    // the head (hair, ears, hats). Arms of "tadpole" figures leave the
    // head sideways and stay candidates.
    if (dd(l.tx, l.ty) < 1.05 * hr) return true;
    final near =
        dd(l.tx, l.ty) < 1.6 * hr || dd(l.junction.x, l.junction.y) < hr;
    return near && l.ty < hy - 0.3 * hr;
  }

  final headExtras = <_Leaf>[
    if (headDisc != null)
      for (final l in leaves)
        if (!used.contains(l) && inHead(l)) l,
  ];
  used.addAll(headExtras);

  _Leaf? head;
  var headScore = -1e9;
  for (final l in headDisc != null ? const <_Leaf>[] : leaves) {
    if (used.contains(l)) continue;
    final up = (cy - l.ty) / bh;
    final side = (l.tx - cx).abs() / bw;
    final blob = l.tip.radius / maxR;
    final s = landscape
        ? 1.2 * blob + 0.6 * up + 0.3 * side
        : 1.2 * up - 1.4 * side + 0.8 * blob;
    final ok = landscape ? (up > -0.1 || blob > 0.45) : ang(l).abs() < 60;
    if (ok && s > headScore) {
      headScore = s;
      head = l;
    }
  }
  if (head != null) used.add(head);

  // Arms: the best sideways leaf on each side (by reach).
  _Leaf? bestOn(bool left) {
    _Leaf? best;
    var bs = 0.0;
    for (final l in leaves) {
      if (used.contains(l)) continue;
      if ((l.tx < cx) != left) continue;
      if (landscape && l.ty > cy) continue; // animals: low leaves are legs
      // Straight up on the centre line: a hat / antenna, not an arm.
      if (ang(l).abs() < 25 && (l.tx - cx).abs() < 0.12 * bw) continue;
      // Hanging arms are fine, but not leaves at the feet.
      if (!landscape && l.ty > b[1] + 0.88 * bh) continue;
      final s = (l.tx - cx).abs() + 0.5 * l.length;
      if (s > bs) {
        bs = s;
        best = l;
      }
    }
    return best;
  }

  final arms = <_Leaf>[];
  // Four-legged animals in profile have no arms (the leaf on the far side
  // of the head becomes the tail below).
  final quadruped = landscape && legs.length >= 3;
  for (final left in quadruped ? const <bool>[] : [true, false]) {
    final a = bestOn(left);
    if (a != null) {
      arms.add(a);
      used.add(a);
    }
  }

  // Tail: (profile drawings) a leaf on the side opposite the head.
  _Leaf? tail;
  if (landscape && head != null) {
    final headLeft = head.tx < cx;
    for (final l in leaves) {
      if (used.contains(l)) continue;
      if ((l.tx < cx) == headLeft) continue;
      if (tail == null || (l.tx - cx).abs() > (tail.tx - cx).abs()) tail = l;
    }
    if (tail != null) used.add(tail);
  }

  // Root / chest.
  V2 avgJ(List<_Leaf> ls) {
    var x = 0.0, y = 0.0;
    for (final l in ls) {
      final (bx, by) = _exit(l, dist, w, 0.0);
      x += bx;
      y += by;
    }
    return V2(x / ls.length, y / ls.length);
  }

  V2 rootW;
  if (legs.isNotEmpty && !landscape) {
    rootW = avgJ(legs);
  } else {
    // Bottom-centre of the body (blobs, animals): above the leg tops.
    rootW = V2(cx, math.min(b[3] - 0.15 * bh, cy + 0.25 * bh));
    if (legs.isNotEmpty) {
      final j = avgJ(legs);
      rootW = V2(cx, math.min(rootW.y, j.y));
    }
  }
  V2 chestW;
  if (arms.isNotEmpty && !landscape) {
    chestW = avgJ(arms);
    chestW = V2((chestW.x + cx) / 2, chestW.y);
  } else if (head != null && !landscape) {
    chestW = avgJ([head]);
  } else if (headDisc != null) {
    final (hx, hy, hr) = headDisc;
    chestW = V2(hx, hy + 1.3 * hr);
  } else {
    chestW = V2(cx, cy - 0.15 * bh);
  }
  if (chestW.y > rootW.y - 0.05 * bh) {
    chestW = V2(chestW.x, rootW.y - 0.2 * bh);
  }

  RigLimb limb(LimbKind k, _Leaf l) {
    final (bx, by) = _exit(l, dist, w, 0.85);
    // Mid point halfway along the path from the exit point to the tip.
    final startIdx = _indexNear(l.path, bx, by);
    var total = 0.0;
    for (var k2 = startIdx + 1; k2 < l.path.length; k2++) {
      total += _dist(l.path[k2 - 1], l.path[k2]);
    }
    var acc = 0.0;
    var mid = l.path.last;
    for (var k2 = startIdx + 1; k2 < l.path.length; k2++) {
      acc += _dist(l.path[k2 - 1], l.path[k2]);
      if (acc >= total / 2) {
        mid = l.path[k2];
        break;
      }
    }
    return RigLimb(k, d(bx, by), d(mid.$1, mid.$2), d(l.tx, l.ty));
  }

  RigLimb? headLimb;
  if (headDisc != null) {
    final (hx, hy, hr) = headDisc;
    final tip = V2(hx, hy);
    final dir = chestW - tip;
    final len = dir.length;
    final base = len < 1e-6
        ? V2(hx, hy + hr)
        : tip + dir * (math.min(0.9 * hr, 0.8 * len) / len);
    headLimb = RigLimb(
      LimbKind.head,
      d(base.x, base.y),
      d((base.x + hx) / 2, (base.y + hy) / 2),
      d(hx, hy),
    );
  }
  final limbs = <RigLimb>[
    ?headLimb,
    if (head != null) limb(LimbKind.head, head),
    for (final a in arms) limb(LimbKind.arm, a),
    for (final l in legs) limb(LimbKind.leg, l),
    if (tail != null) limb(LimbKind.tail, tail),
    for (final l in leaves)
      if (!used.contains(l)) limb(LimbKind.extra, l),
    // Hair, ears, hats: stick out of the head disc (the neck branch that
    // ends inside the head is dropped).
    for (final l in headExtras)
      if (_reach(l, headDisc!) > 1.05) limb(LimbKind.extra, l),
  ];
  return CharacterRig(
    width: 0,
    height: 0,
    root: d(rootW.x, rootW.y),
    chest: d(chestW.x, chestW.y),
    limbs: limbs,
  );
}

/// Tip distance from the head centre in head radii.
double _reach(_Leaf l, (double, double, double) disc) {
  final (hx, hy, hr) = disc;
  return math.sqrt((l.tx - hx) * (l.tx - hx) + (l.ty - hy) * (l.ty - hy)) / hr;
}

double _dist((double, double) a, (double, double) b) {
  final dx = a.$1 - b.$1, dy = a.$2 - b.$2;
  return math.sqrt(dx * dx + dy * dy);
}

int _indexNear(List<(double, double)> path, double x, double y) {
  var best = 0;
  var bd = double.infinity;
  for (var i = 0; i < path.length; i++) {
    final dd = _dist(path[i], (x, y));
    if (dd < bd) {
      bd = dd;
      best = i;
    }
  }
  return best;
}

/// Where the leaf leaves its junction's inscribed circle (× [k]); capped
/// at 45 % of the branch so short limbs keep a lower segment.
(double, double) _exit(_Leaf l, Float64List dist, int w, double k) {
  final r = l.junction.radius * k;
  var acc = 0.0;
  for (var i = 1; i < l.path.length; i++) {
    acc += _dist(l.path[i - 1], l.path[i]);
    final fromJ = _dist(l.path[i], l.path.first);
    if (fromJ >= r || acc >= 0.45 * l.length) return l.path[i];
  }
  return l.path.first;
}
