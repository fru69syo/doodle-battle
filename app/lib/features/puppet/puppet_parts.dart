import 'dart:math' as math;

import '../../domain/cosmetics.dart';
import '../drawing_loop/parts/part_geometry.dart';
import 'rig/character_rig.dart';

/// A drawn part (docs/LOOP.md) as it sits in the composite display picture,
/// in composite pixels.
class PartPlacement {
  const PartPlacement({
    required this.id,
    required this.type,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Where part [t] (a `partW × partH` image) lands in a composite whose
  /// base drawing (`baseW × baseH`) was drawn into [baseLeft], [baseTop]
  /// with scale [k] (CompositeImage.baseRect / base size).
  factory PartPlacement.fromTransform({
    required String id,
    required PartType type,
    required PartTransform t,
    required int baseW,
    required int baseH,
    required int partW,
    required int partH,
    required double baseLeft,
    required double baseTop,
    required double k,
    double scaleBoost = 1,
  }) {
    final b = partToBase(
      t,
      baseW: baseW,
      baseH: baseH,
      partW: partW,
      partH: partH,
      scaleBoost: scaleBoost,
    ).boundsOf(partW.toDouble(), partH.toDouble());
    return PartPlacement(
      id: id,
      type: type,
      left: baseLeft + b.left * k,
      top: baseTop + b.top * k,
      right: baseLeft + b.right * k,
      bottom: baseTop + b.bottom * k,
    );
  }

  final String id;
  final PartType type;
  final double left, top, right, bottom;

  P2 get centre => P2((left + right) / 2, (top + bottom) / 2);

  P2 _clampIn(P2 p) => P2(p.x.clamp(left, right), p.y.clamp(top, bottom));

  /// The point of the part farthest from [p] (its free end).
  P2 _farFrom(P2 p) {
    final c = centre;
    final d = c - p;
    final len = d.length;
    if (len < 1e-6) return P2(c.x, top);
    final hw = (right - left) / 2, hh = (bottom - top) / 2;
    // Ray from the centre away from p, to the box edge.
    final tx = d.x.abs() < 1e-6 ? double.infinity : hw / d.x.abs();
    final ty = d.y.abs() < 1e-6 ? double.infinity : hh / d.y.abs();
    final t = math.min(tx, ty);
    return c + d * (0.85 * t);
  }
}

/// Adds one limb per drawn part to [base] (a rig of the base drawing in
/// its own pixels), returning a rig of the composite picture: hats and
/// horns follow the head, a held item follows the front hand, wings flap
/// from the back, tails wag from the hips, other decorations ride the body.
/// [baseLeft], [baseTop], [k] place the base drawing in the composite.
CharacterRig rigWithParts(
  CharacterRig base, {
  required List<PartPlacement> parts,
  required double compositeW,
  required double compositeH,
  required double baseLeft,
  required double baseTop,
  required double k,
}) {
  P2 m(P2 p) => P2(baseLeft + p.x * k, baseTop + p.y * k);
  final out = CharacterRig(
    width: compositeW,
    height: compositeH,
    root: m(base.root),
    chest: m(base.chest),
    ground: base.ground == null ? null : baseTop + base.ground! * k,
    source: base.source,
    limbs: [
      for (final l in base.limbs)
        RigLimb(
          l.kind,
          m(l.base),
          m(l.mid),
          m(l.tip),
          edited: l.edited,
          attach: l.attach,
          part: l.part,
        ),
    ],
  );
  // The ground must not move up because a part hangs below the feet.
  out.ground ??= baseTop + base.groundY * k;
  final headIdx = out.limbs.indexWhere((l) => l.kind == LimbKind.head);
  for (final p in parts) {
    if (out.limbs.length >= CharacterRig.maxLimbs) break;
    final c = p.centre;
    int? attach;
    P2 anchor;
    LimbKind kind;
    switch (p.type) {
      case PartType.hat || PartType.horn:
        kind = LimbKind.extra;
        attach = headIdx >= 0 ? headIdx : null;
        anchor = headIdx >= 0 ? out.limbs[headIdx].tip : out.chest;
      case PartType.wings:
        kind = LimbKind.wing;
        anchor = out.chest;
      case PartType.tail:
        kind = LimbKind.tail;
        anchor = out.root;
      case PartType.weapon:
        kind = LimbKind.item;
        // The hand nearest to the part holds it.
        var best = -1;
        var bd = double.infinity;
        for (final (i, l) in out.limbs.indexed) {
          if (l.kind != LimbKind.arm) continue;
          final d = l.tip.dist(c);
          if (d < bd) {
            bd = d;
            best = i;
          }
        }
        attach = best >= 0 ? best : null;
        anchor = best >= 0 ? out.limbs[best].tip : out.chest;
      case PartType.accessory:
        kind = LimbKind.extra;
        anchor = out.chest;
    }
    final b = p._clampIn(anchor);
    final tip = p._farFrom(anchor);
    if (b.dist(tip) < 2) continue;
    out.limbs.add(
      RigLimb(kind, b, b.lerp(tip, 0.5), tip, attach: attach, part: p.id),
    );
  }
  return out;
}
