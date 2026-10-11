import 'dart:math' as math;
import 'dart:typed_data';

/// Names of the glTF animations every inflated character carries.
abstract final class RigClips {
  static const idle = 'idle';
  static const hop = 'hop';
  static const attack = 'attack';
  static const hit = 'hit';
  static const faint = 'faint';
  static const all = [idle, hop, attack, hit, faint];

  /// Clips that loop; the others play once (faint holds its last pose).
  static bool loops(String clip) => clip == idle;
}

/// Joint indices (skin order).
abstract final class RigJoints {
  static const root = 0;
  static const spine = 1;
  static const head = 2;
  static const names = ['rig_root', 'rig_spine', 'rig_head'];

  /// Bind heights relative to the character height.
  static const spineAt = 0.42;
  static const headAt = 0.72;
}

/// Local pose of one joint: translation (relative to bind), Euler rotation
/// (degrees, applied X then Z) and scale.
class JointPose {
  const JointPose({
    this.tx = 0,
    this.ty = 0,
    this.tz = 0,
    this.rx = 0,
    this.rz = 0,
    this.sx = 1,
    this.sy = 1,
  });
  final double tx, ty, tz, rx, rz, sx, sy;

  /// glTF quaternion (x, y, z, w) for rotation X then Z (R = Rz·Rx).
  List<double> get quaternion {
    final ax = rx * math.pi / 360, az = rz * math.pi / 360;
    final cx = math.cos(ax), sxx = math.sin(ax);
    final cz = math.cos(az), szz = math.sin(az);
    // q = qz * qx
    return [cz * sxx, szz * sxx, szz * cx, cz * cx];
  }
}

/// A sampled clip: per joint lists of poses at [times].
class RigClip {
  RigClip(this.name, this.times, this.poses);
  final String name;
  final List<double> times;

  /// poses[joint][key]
  final List<List<JointPose>> poses;
  double get duration => times.last;
}

double _smooth(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Ease between keyed (time, value) pairs with smoothstep segments.
double _keys(List<(double, double)> k, double t) {
  if (t <= k.first.$1) return k.first.$2;
  for (var i = 1; i < k.length; i++) {
    if (t <= k[i].$1) {
      return _lerp(k[i - 1].$2, k[i].$2, _smooth(k[i - 1].$1, k[i].$1, t));
    }
  }
  return k.last.$2;
}

/// The procedural animation set, in units of the character [height].
///
/// All motion lives on three joints (feet pivot, spine, head) so the same
/// clips drive any drawing; squash & stretch is a root scale that keeps the
/// volume roughly constant (sx = 1/√sy).
List<RigClip> buildRigClips(double height, {double fps = 30}) {
  final h = height;
  List<JointPose> Function(double) idle(double dur) => (t) {
    final ph = 2 * math.pi * t / dur;
    final bob = 0.02 * h * (1 - math.cos(ph)) / 2;
    final sy = 1 + 0.025 * math.cos(ph);
    return [
      JointPose(ty: bob, sy: sy, sx: 1 / math.sqrt(sy)),
      JointPose(rz: 3 * math.sin(ph)),
      JointPose(rz: -2 * math.sin(ph), rx: 2 * math.sin(ph * 2)),
    ];
  };
  List<JointPose> hop(double t) {
    final air = t > 0.15 && t < 0.45;
    final u = ((t - 0.15) / 0.3).clamp(0.0, 1.0);
    final y = air ? 0.3 * h * 4 * u * (1 - u) : 0.0;
    final sy = _keys(
      [(0, 1), (0.13, 0.82), (0.2, 1.14), (0.4, 1.05), (0.47, 0.8), (0.53, 1.06), (0.6, 1)],
      t,
    );
    return [
      JointPose(ty: y, sy: sy, sx: 1 / math.sqrt(sy)),
      JointPose(rx: _keys([(0, 0), (0.13, 8), (0.25, -6), (0.47, 6), (0.6, 0)], t)),
      const JointPose(),
    ];
  }

  List<JointPose> attack(double t) {
    final tz = _keys([(0, 0), (0.2, -0.06 * h), (0.32, 0.42 * h), (0.45, 0.38 * h), (0.7, 0)], t);
    final sy = _keys([(0, 1), (0.2, 0.9), (0.32, 1.1), (0.45, 0.95), (0.7, 1)], t);
    return [
      JointPose(tz: tz, sy: sy, sx: 1 / math.sqrt(sy)),
      JointPose(rx: _keys([(0, 0), (0.2, -16), (0.32, 30), (0.45, 22), (0.7, 0)], t)),
      JointPose(rx: _keys([(0, 0), (0.2, -8), (0.32, 14), (0.45, 6), (0.7, 0)], t)),
    ];
  }

  List<JointPose> hit(double t) {
    // Snap back, then a damped wobble home.
    final snap = _smooth(0, 0.07, t);
    final decay = t < 0.07 ? 1.0 : math.exp(-(t - 0.07) * 9) * math.cos((t - 0.07) * 22);
    final k = snap * decay * (1 - _smooth(0.38, 0.5, t));
    final sy = 1 - 0.15 * k;
    return [
      JointPose(tz: -0.18 * h * k, sy: sy, sx: 1 / math.sqrt(sy)),
      JointPose(rx: -22 * k),
      JointPose(rx: -14 * k),
    ];
  }

  List<JointPose> faint(double t) {
    final wob = t < 0.35 ? 10 * math.sin(t / 0.35 * 2 * math.pi) * (1 - t / 0.35) : 0.0;
    final fall = _keys([(0.3, 0), (0.85, -84), (0.97, -76), (1.1, -82), (1.2, -80)], t);
    final sy = _keys([(0, 1), (0.3, 0.93), (0.85, 0.9), (1.2, 0.85)], t);
    return [
      JointPose(rz: wob, rx: fall, ty: 0.04 * h * math.sin(_smooth(0.3, 0.85, t) * math.pi) , sy: sy, sx: 1 / math.sqrt(sy)),
      JointPose(rx: _keys([(0, 0), (0.3, 10), (0.85, -10), (1.2, -4)], t)),
      JointPose(rx: _keys([(0, 0), (0.85, -14), (1.2, -10)], t)),
    ];
  }

  RigClip sample(String name, double dur, List<JointPose> Function(double) f) {
    final n = (dur * fps).round();
    final times = [for (var i = 0; i <= n; i++) dur * i / n];
    final poses = List.generate(3, (_) => <JointPose>[]);
    for (final t in times) {
      final p = f(t);
      for (var j = 0; j < 3; j++) {
        poses[j].add(p[j]);
      }
    }
    return RigClip(name, times, poses);
  }

  return [
    sample(RigClips.idle, 1.2, idle(1.2)),
    sample(RigClips.hop, 0.6, hop),
    sample(RigClips.attack, 0.7, attack),
    sample(RigClips.hit, 0.5, hit),
    sample(RigClips.faint, 1.2, faint),
  ];
}

/// Skin weights by height: feet follow the root, the belly blends into the
/// spine, the top of the drawing follows the head. At most 2 influences.
/// Returns (joints as 4×u8, weights as 4×f32) per vertex.
(Uint8List, Float32List) skinWeights(Float32List positions, double height) {
  final n = positions.length ~/ 3;
  final joints = Uint8List(n * 4);
  final weights = Float32List(n * 4);
  for (var v = 0; v < n; v++) {
    final f = positions[v * 3 + 1] / height;
    int a, b;
    double s;
    if (f < 0.3) {
      (a, b, s) = (RigJoints.root, RigJoints.spine, 0.0);
    } else if (f < 0.5) {
      (a, b, s) = (RigJoints.root, RigJoints.spine, _smooth(0.3, 0.5, f));
    } else if (f < 0.62) {
      (a, b, s) = (RigJoints.spine, RigJoints.head, 0.0);
    } else {
      (a, b, s) = (RigJoints.spine, RigJoints.head, _smooth(0.62, 0.8, f));
    }
    // Unused influences must be joint 0 with weight 0 (glTF validator).
    if (s <= 0) {
      joints[v * 4] = a;
      weights[v * 4] = 1;
    } else if (s >= 1) {
      joints[v * 4] = b;
      weights[v * 4] = 1;
    } else {
      joints[v * 4] = a;
      joints[v * 4 + 1] = b;
      weights[v * 4] = 1 - s;
      weights[v * 4 + 1] = s;
    }
  }
  return (joints, weights);
}
