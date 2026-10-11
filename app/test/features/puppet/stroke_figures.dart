import 'dart:math' as math;
import 'dart:typed_data';

import 'package:doodle_battle/features/puppet/rig/bin_mask.dart';
import 'package:doodle_battle/features/puppet/rig/character_rig.dart';
import 'package:doodle_battle/features/puppet/rig/limb_hints.dart';

/// Arm poses of the synthetic stroke figures.
enum ArmPose { out, hips, along, up }

/// A synthetic in-app drawing: kid-like strokes (round head, oval body
/// outline, line or sausage limbs), the ground-truth hands and the mask.
class StrokeFigure {
  StrokeFigure(this.strokes, this.hands, this.mask, this.pose);
  final List<HintStroke> strokes;
  final List<P2> hands;
  final BinMask mask;
  final ArmPose pose;

  /// Straight-alpha RGBA: black ink on transparent (like a cut-out).
  Uint8List get rgba {
    final out = Uint8List(mask.w * mask.h * 4);
    for (var i = 0; i < mask.w * mask.h; i++) {
      if (mask.data[i] != 0) out[i * 4 + 3] = 255;
    }
    return out;
  }
}

List<P2> _ellipse(P2 c, double rx, double ry, math.Random r, {int n = 28}) => [
  for (var i = 0; i <= n; i++)
    P2(
      c.x + rx * math.cos(i / n * 2 * math.pi) * (1 + 0.04 * (r.nextDouble() - 0.5)),
      c.y + ry * math.sin(i / n * 2 * math.pi) * (1 + 0.04 * (r.nextDouble() - 0.5)),
    ),
];

List<P2> _line(P2 a, P2 b, math.Random r, {int n = 10}) => [
  for (var i = 0; i <= n; i++)
    a.lerp(b, i / n) + P2((r.nextDouble() - 0.5) * 2, (r.nextDouble() - 0.5) * 2),
];

/// Figure [seed]: sizes, line width and arm pose vary.
StrokeFigure strokeFigure(int seed, {ArmPose? pose}) {
  final r = math.Random(seed);
  const w = 300, h = 400;
  final lw = 6.0 + r.nextInt(6);
  final cx = 150.0 + (r.nextDouble() - 0.5) * 20;
  final headR = 38.0 + r.nextDouble() * 18;
  final headC = P2(cx, 30 + headR);
  final bodyTop = headC.y + headR + 4;
  final bodyRx = 42.0 + r.nextDouble() * 18;
  final bodyRy = 70.0 + r.nextDouble() * 20;
  final bodyC = P2(cx, bodyTop + bodyRy);
  final hipY = bodyC.y + bodyRy * 0.85;
  final p = pose ?? ArmPose.values[seed % ArmPose.values.length];
  final strokes = <HintStroke>[
    HintStroke(_ellipse(headC, headR, headR, r), lw),
    HintStroke(_ellipse(bodyC, bodyRx, bodyRy, r), lw),
  ];
  final hands = <P2>[];
  for (final side in [-1.0, 1.0]) {
    final shoulder = P2(cx + side * bodyRx * 0.8, bodyTop + bodyRy * 0.35);
    final List<P2> arm;
    switch (p) {
      case ArmPose.out:
        final hand = P2(cx + side * (bodyRx + 70), shoulder.y + 10);
        arm = _line(shoulder, hand, r);
        hands.add(hand);
      case ArmPose.up:
        final hand = P2(cx + side * (bodyRx + 40), shoulder.y - 80);
        arm = _line(shoulder, hand, r);
        hands.add(hand);
      case ArmPose.hips:
        // Elbow out, hand back on the hip: touches the body.
        final elbow = P2(cx + side * (bodyRx + 45), shoulder.y + 35);
        final hand = P2(cx + side * (bodyRx * 0.85), bodyC.y + bodyRy * 0.3);
        arm = [..._line(shoulder, elbow, r), ..._line(elbow, hand, r)];
        hands.add(hand);
      case ArmPose.along:
        // Hanging right next to the body.
        final hand = P2(cx + side * (bodyRx + lw * 0.6), bodyC.y + bodyRy * 0.55);
        arm = _line(shoulder + P2(side * 6, 0), hand, r);
        hands.add(hand);
    }
    strokes.add(HintStroke(arm, lw));
    strokes.add(
      HintStroke(
        _line(
          P2(cx + side * bodyRx * 0.4, hipY),
          P2(cx + side * (bodyRx * 0.5 + 10), h - 12.0),
          r,
        ),
        lw,
      ),
    );
  }
  final m = BinMask(w, h);
  for (final s in strokes) {
    for (var i = 1; i < s.points.length; i++) {
      final a = s.points[i - 1], b = s.points[i];
      m.line(a.x.round(), a.y.round(), b.x.round(), b.y.round(), (s.width / 2).round());
    }
  }
  return StrokeFigure(strokes, hands, m, p);
}

/// Hand error (normalised by the figure size, left/right matched), or
/// infinity when two hands were not found.
double handError(CharacterRig rig, StrokeFigure f) {
  final arms = rig.of(LimbKind.arm).map((l) => l.tip).toList();
  if (arms.length < 2) return double.infinity;
  final a = arms[0].dist(f.hands[0]) + arms[1].dist(f.hands[1]);
  final b = arms[0].dist(f.hands[1]) + arms[1].dist(f.hands[0]);
  return math.min(a, b) / 2 / 400;
}
