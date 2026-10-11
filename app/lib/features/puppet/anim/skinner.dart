import 'dart:math' as math;
import 'dart:typed_data';

import '../mesh/puppet_mesh.dart';
import '../rig/character_rig.dart';

/// 2D affine map: x' = a·x + c·y + e, y' = b·x + d·y + f.
class Affine {
  const Affine(this.a, this.b, this.c, this.d, this.e, this.f);
  const Affine.identity() : this(1, 0, 0, 1, 0, 0);

  factory Affine.translate(double x, double y) => Affine(1, 0, 0, 1, x, y);
  factory Affine.scale(double sx, double sy) => Affine(sx, 0, 0, sy, 0, 0);
  factory Affine.rotate(double r) {
    final cs = math.cos(r), sn = math.sin(r);
    return Affine(cs, sn, -sn, cs, 0, 0);
  }

  /// Rotation by [r] about ([px], [py]).
  factory Affine.rotateAbout(double r, double px, double py) =>
      Affine.translate(px, py) * Affine.rotate(r) * Affine.translate(-px, -py);

  /// Scale about ([px], [py]).
  factory Affine.scaleAbout(double sx, double sy, double px, double py) =>
      Affine(sx, 0, 0, sy, px - sx * px, py - sy * py);

  final double a, b, c, d, e, f;

  /// `this ∘ o` (apply [o] first).
  Affine operator *(Affine o) => Affine(
    a * o.a + c * o.b,
    b * o.a + d * o.b,
    a * o.c + c * o.d,
    b * o.c + d * o.d,
    a * o.e + c * o.f + e,
    b * o.e + d * o.f + f,
  );

  (double, double) apply(double x, double y) =>
      (a * x + c * y + e, b * x + d * y + f);
}

/// One frame's deformation of a rigged character (all clips produce one).
/// Distances are in units of the character's height so clips work for any
/// drawing size; angles in radians (screen space, y down: + is clockwise).
class Pose {
  Pose(int limbs) : a = Float64List(limbs), b = Float64List(limbs);

  /// Offset of the whole character (× height).
  double dx = 0, dy = 0;

  /// Body lean about the root (pelvis); legs stay planted.
  double lean = 0;

  /// Whole-body rotation about the ground point (faint, spins).
  double rot = 0;

  /// Squash & stretch about the ground point.
  double sx = 1, sy = 1;

  /// Per limb: rotation of the upper and lower segment.
  final Float64List a, b;

  /// Jelly wobble (× width) for blobs and the simplified look.
  double wobble = 0, wobblePhase = 0;

  /// Visual flags read by the renderer.
  double flash = 0, glow = 0, opacity = 1;

  void reset() {
    dx = dy = lean = rot = wobble = wobblePhase = flash = glow = 0;
    sx = sy = opacity = 1;
    a.fillRange(0, a.length, 0);
    b.fillRange(0, b.length, 0);
  }
}

/// Linear blend skinning on the CPU: bone transforms from a [Pose], then
/// every vertex = Σ wᵢ·Mᵢ·v (4 influences). The placement (screen scale,
/// mirror, position) is folded into the bone matrices, so the output is
/// ready for `Vertices.raw`.
class Skinner {
  Skinner(this.c)
    : _m = Float64List(c.bones.length * 6),
      out = Float32List(c.rest.length);

  final PuppetMesh c;
  final Float64List _m;

  /// Posed vertex positions (screen space) after [skin].
  final Float32List out;

  /// Bone matrices for the last [skin] (rest → screen).
  Affine bone(int i) => Affine(
    _m[i * 6],
    _m[i * 6 + 1],
    _m[i * 6 + 2],
    _m[i * 6 + 3],
    _m[i * 6 + 4],
    _m[i * 6 + 5],
  );

  void skin(Pose p, Affine place) {
    final rig = c.rig;
    final h = rig.height;
    final gx = rig.root.x, gy = rig.groundY;
    final global =
        place *
        Affine.translate(p.dx * h, p.dy * h) *
        Affine.rotateAbout(p.rot, gx, gy) *
        Affine.scaleAbout(p.sx, p.sy, gx, gy);
    final mats = List<Affine>.filled(c.bones.length, global);
    for (var i = 0; i < c.bones.length; i++) {
      final bn = c.bones[i];
      final parent = bn.parent < 0 ? global : mats[bn.parent];
      double r;
      if (i == 0) {
        r = 0;
      } else if (i == 1) {
        r = p.lean;
      } else {
        final l = bn.limb!;
        r = bn.segment == 0 ? p.a[l] : p.b[l];
      }
      mats[i] = r == 0
          ? parent
          : parent * Affine.rotateAbout(r, bn.from.x, bn.from.y);
      final m = mats[i];
      _m
        ..[i * 6] = m.a
        ..[i * 6 + 1] = m.b
        ..[i * 6 + 2] = m.c
        ..[i * 6 + 3] = m.d
        ..[i * 6 + 4] = m.e
        ..[i * 6 + 5] = m.f;
    }
    final rest = c.rest;
    final bi = c.boneIdx;
    final bw = c.boneW;
    final n = rest.length >> 1;
    final wob = p.wobble * rig.width;
    final top = gy - h * 0.95;
    final span = math.max(1.0, gy - top);
    for (var v = 0; v < n; v++) {
      var x = rest[v * 2];
      final y = rest[v * 2 + 1];
      if (wob != 0) {
        final t = ((gy - y) / span).clamp(0.0, 1.0); // 0 feet .. 1 top
        x += wob * t * math.sin(p.wobblePhase + 2.2 * t);
      }
      var ox = 0.0, oy = 0.0;
      for (var k = 0; k < 4; k++) {
        final w = bw[v * 4 + k];
        if (w == 0) continue;
        final o = bi[v * 4 + k] * 6;
        ox += w * (_m[o] * x + _m[o + 2] * y + _m[o + 4]);
        oy += w * (_m[o + 1] * x + _m[o + 3] * y + _m[o + 5]);
      }
      out[v * 2] = ox;
      out[v * 2 + 1] = oy;
    }
  }

  /// Where a rest-space point of limb [limb]'s tip ends up (for effects:
  /// a fist, a foot); falls back to the body.
  (double, double) limbTip(int limb, RigLimb l) {
    for (var i = 0; i < c.bones.length; i++) {
      final bn = c.bones[i];
      if (bn.limb == limb &&
          (bn.segment == 1 ||
              l.kind == LimbKind.head ||
              l.kind == LimbKind.item)) {
        return bone(i).apply(l.tip.x, l.tip.y);
      }
    }
    return bone(1).apply(l.tip.x, l.tip.y);
  }
}
