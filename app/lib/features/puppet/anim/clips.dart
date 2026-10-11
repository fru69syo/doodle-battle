import 'dart:math' as math;

import '../rig/character_rig.dart';
import 'skinner.dart';

/// Procedural clips. Every clip works on any rig: limbs move by kind, and
/// a drawing without limbs (a blob, a car) falls back to whole-body
/// squash / stretch / hop / lean plus a jelly wobble.
enum Anim {
  idle,
  walk,

  /// Bouncy hop in place (happy, waiting to act).
  hop,

  /// Arm swing (punch / slap); kick when there are legs but no arms;
  /// tackle for blobs.
  swing,
  kick,
  tackle,

  /// Jump in an arc and land on the target.
  jump,

  /// Charge: arms up, glow (heal, power-up, barrier, the cast time of a
  /// move).
  cast,

  /// Point / throw forward (beams, projectiles, status moves).
  shoot,
  hit,
  faint,
  victory,

  /// Limbless / simple look: squash down and spring back (a "boing").
  squash,

  /// Limbless / simple look: jelly wobble in place.
  wobble,
}

/// Lengths (s) and the moment the blow lands.
const kAnimLength = {
  Anim.swing: 0.7,
  Anim.kick: 0.7,
  Anim.tackle: 0.7,
  Anim.jump: 0.8,
  Anim.shoot: 0.7,
  Anim.hit: 0.5,
  Anim.faint: 1.1,
  Anim.squash: 0.6,
};
const kAnimImpact = {
  Anim.swing: 0.3,
  Anim.kick: 0.3,
  Anim.tackle: 0.32,
  Anim.jump: 0.42,
  Anim.shoot: 0.3,
};

/// Per-character data the clips need (rest directions, which arm is in
/// front...). [fwd] is where the opponent is, in drawing space (+1 right).
class AnimContext {
  AnimContext(this.rig, {this.limited = false})
    : restAngle = [
        for (final l in rig.limbs)
          math.atan2(l.tip.y - l.base.y, l.tip.x - l.base.x),
      ];

  final CharacterRig rig;
  final List<double> restAngle;

  /// Simplified look: smaller, stiffer motion.
  final bool limited;

  bool get hasArms => rig.of(LimbKind.arm).isNotEmpty;
  bool get hasLegs => rig.of(LimbKind.leg).isNotEmpty;

  /// Attack style for a physical move.
  Anim physicalClip(int variant) {
    if (limited || rig.isBlob) return variant.isEven ? Anim.tackle : Anim.jump;
    if (hasArms) return variant % 3 == 2 ? Anim.jump : Anim.swing;
    if (hasLegs) return variant.isEven ? Anim.kick : Anim.tackle;
    return Anim.tackle;
  }

  /// Index of the limb of [kind] on the [fwd] side (or the first one).
  int? front(LimbKind kind, int fwd) {
    int? first;
    int? best;
    var bestDx = -double.infinity;
    for (final (i, l) in rig.limbs.indexed) {
      if (l.kind != kind) continue;
      first ??= i;
      final dx = (l.tip.x - rig.root.x) * fwd;
      if (dx > bestDx) {
        bestDx = dx;
        best = i;
      }
    }
    return best ?? first;
  }
}

double _wrap(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

double _ease(double t) {
  t = t.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// 0→1→0 bump over [a, b].
double _bump(double t, double a, double b) =>
    t <= a || t >= b ? 0 : math.sin(math.pi * (t - a) / (b - a));

/// Rotation that turns limb [i] toward screen angle [target] by [amount].
double _toward(AnimContext c, int i, double target, double amount) =>
    _wrap(target - c.restAngle[i]) * amount;

double _dirAngle(double x, double y) => math.atan2(y, x);

/// Writes clip [clip] at time [t] (s) into [p] (which is reset first).
void evaluateAnim(Anim clip, double t, AnimContext c, int fwd, Pose p) {
  p.reset();
  final rig = c.rig;
  final k = c.limited ? 0.45 : 1.0; // motion amplitude
  final blob = rig.isBlob || c.limited;
  final limbs = rig.limbs;
  // Secondary motion common to every clip: tails wag, extras jiggle.
  for (final (i, l) in limbs.indexed) {
    if (l.kind == LimbKind.tail) {
      p.a[i] = 0.3 * math.sin(2 * math.pi * t / 0.7);
      p.b[i] = 0.35 * math.sin(2 * math.pi * t / 0.7 - 0.9);
    } else if (l.kind == LimbKind.extra) {
      p.a[i] = 0.1 * math.sin(2 * math.pi * t / 0.9 + i);
      p.b[i] = 0.14 * math.sin(2 * math.pi * t / 0.9 + i - 0.7);
    } else if (l.kind == LimbKind.wing) {
      // Flap away from the body: the rotation sign follows the side.
      final side = l.tip.x < rig.root.x ? 1.0 : -1.0;
      final fast = clip == Anim.jump || clip == Anim.victory ? 0.28 : 0.5;
      p.a[i] = side * 0.35 * (0.5 + 0.5 * math.sin(2 * math.pi * t / fast));
      p.b[i] = side * 0.2 * math.sin(2 * math.pi * t / fast - 0.8);
    } else if (l.kind == LimbKind.item) {
      p.a[i] = 0.06 * math.sin(2 * math.pi * t / 1.1 + i);
    }
  }
  final up = -math.pi / 2;
  final fwdAngle = fwd > 0 ? 0.0 : math.pi;

  switch (clip) {
    case Anim.idle:
      final w = 2 * math.pi * t / 1.4;
      p.sy = 1 + (blob ? 0.05 : 0.03) * k * math.sin(w);
      p.sx = 1 / math.sqrt(p.sy);
      for (final (i, l) in limbs.indexed) {
        if (l.kind == LimbKind.arm) {
          p.a[i] = 0.1 * k * math.sin(w + i);
          p.b[i] = 0.08 * k * math.sin(w + i + 1);
        } else if (l.kind == LimbKind.head) {
          p.a[i] = 0.06 * k * math.sin(w * 0.5);
        }
      }
      if (blob) {
        p.wobble = 0.025 * k;
        p.wobblePhase = w;
      }

    case Anim.walk:
      const period = 0.5;
      final ph = 2 * math.pi * t / period;
      if (blob || !c.hasLegs) {
        // Hop: squash on contact, stretch in the air.
        final s = (math.sin(math.pi * t / (period / 2))).abs();
        p.dy = -0.16 * k * s;
        final contact = 1 - s;
        p.sy = 1 - 0.14 * k * contact * contact + 0.08 * k * s;
        p.sx = 1 / math.sqrt(p.sy);
        p.lean = 0.12 * fwd * k;
        p.wobble = 0.03 * k;
        p.wobblePhase = ph;
      } else {
        p.dy = -0.035 * (math.sin(ph)).abs();
        p.lean = 0.07 * fwd;
        var legN = 0;
        for (final (i, l) in limbs.indexed) {
          if (l.kind == LimbKind.leg) {
            final s = legN.isEven ? 1.0 : -1.0;
            p.a[i] = 0.42 * s * math.sin(ph) * fwd;
            p.b[i] = 0.35 * math.max(0, -s * math.sin(ph)) * fwd;
            legN++;
          } else if (l.kind == LimbKind.arm) {
            final s = (l.tip.x < rig.root.x) ? 1.0 : -1.0;
            p.a[i] = 0.4 * s * math.sin(ph);
          } else if (l.kind == LimbKind.head) {
            p.a[i] = 0.05 * math.sin(2 * ph);
          }
        }
      }

    case Anim.swing:
      final arm = c.front(LimbKind.arm, fwd);
      final wind = _ease(t / 0.2);
      final strike = _ease((t - 0.2) / 0.1);
      final back = _ease((t - 0.36) / 0.3);
      final upBack = _dirAngle(-0.6 * fwd, -1);
      final down = _dirAngle(1.0 * fwd, 0.25);
      p.lean = (-0.14 * wind + 0.4 * strike) * fwd * (1 - back);
      p.dx = 0.12 * fwd * strike * (1 - back);
      p.sy = 1 + 0.06 * wind * (1 - strike) - 0.05 * strike * (1 - back);
      p.sx = 1 / math.sqrt(p.sy);
      if (arm != null) {
        final wa = _toward(c, arm, upBack, 1);
        final sa = _toward(c, arm, down, 1);
        p.a[arm] = (wa * wind * (1 - strike) + sa * strike) * (1 - back);
        p.b[arm] = (-0.6 * wind * (1 - strike)) * fwd * (1 - back);
        for (final (i, l) in limbs.indexed) {
          if (l.kind == LimbKind.arm && i != arm) {
            p.a[i] =
                _toward(c, i, _dirAngle(-fwd * 1.0, 0.6), 0.5) *
                strike *
                (1 - back);
          }
        }
      }
      p.flash = 0;

    case Anim.kick:
      final leg = c.front(LimbKind.leg, fwd);
      final wind = _ease(t / 0.2);
      final strike = _ease((t - 0.2) / 0.1);
      final back = _ease((t - 0.36) / 0.3);
      p.lean = (0.1 * wind - 0.3 * strike) * fwd * (1 - back);
      if (leg != null) {
        final kickDir = _dirAngle(fwd * 1.0, -0.15);
        p.a[leg] =
            (_toward(c, leg, _dirAngle(-0.4 * fwd, 1), 0.6) *
                    wind *
                    (1 - strike) +
                _toward(c, leg, kickDir, 0.9) * strike) *
            (1 - back);
        p.b[leg] = 0.5 * fwd * wind * (1 - strike) * (1 - back);
      }
      p.dx = 0.1 * fwd * strike * (1 - back);

    case Anim.tackle:
      final wind = _ease(t / 0.22);
      final go = _ease((t - 0.22) / 0.1);
      final back = _ease((t - 0.4) / 0.3);
      p.sy = 1 - 0.18 * k * wind * (1 - go) - 0.12 * go * (1 - back);
      p.sx = (1 + 0.14 * k * wind * (1 - go) + 0.25 * go * (1 - back));
      p.lean = (-0.12 * wind * (1 - go) + 0.38 * k * go) * fwd * (1 - back);
      p.dx = (-0.05 * wind * (1 - go) + 0.3 * go) * fwd * (1 - back);
      if (blob) {
        p.wobble = 0.05 * (go - back).clamp(0.0, 1.0);
        p.wobblePhase = t * 30;
      }

    case Anim.jump:
      final crouch = _bump(t, 0, 0.16);
      final air = t > 0.12 && t < kAnimImpact[Anim.jump]!
          ? (t - 0.12) / 0.3
          : 0.0;
      final land = _bump(t, kAnimImpact[Anim.jump]!, 0.62);
      p.dy = -0.55 * k * math.sin(math.pi * air);
      p.dx =
          0.35 * fwd * air +
          (t >= kAnimImpact[Anim.jump]!
              ? 0.35 * fwd * (1 - _ease((t - 0.45) / 0.35))
              : 0);
      p.sy = 1 - 0.2 * crouch + 0.12 * math.sin(math.pi * air) - 0.22 * land;
      p.sx = 1 / math.sqrt(p.sy);
      p.rot = 0.25 * fwd * math.sin(math.pi * air);
      for (final (i, l) in limbs.indexed) {
        if (l.kind == LimbKind.arm) {
          p.a[i] = _toward(c, i, up, 0.7) * math.sin(math.pi * air);
        } else if (l.kind == LimbKind.leg) {
          p.b[i] = 0.6 * fwd * math.sin(math.pi * air);
        }
      }

    case Anim.cast:
      final pulse = math.sin(2 * math.pi * t / 0.6);
      p.dy = -0.04 - 0.02 * pulse;
      p.glow = 0.65 + 0.35 * pulse;
      p.sy = 1 + 0.04 * pulse * k;
      p.sx = 1 / math.sqrt(p.sy);
      for (final (i, l) in limbs.indexed) {
        if (l.kind == LimbKind.arm) {
          final side = l.tip.x < rig.root.x ? -1.0 : 1.0;
          p.a[i] =
              _toward(c, i, _dirAngle(0.45 * side, -1), 0.9 * k) + 0.08 * pulse;
          p.b[i] = 0.1 * pulse;
        } else if (l.kind == LimbKind.head) {
          p.a[i] = -0.12 * fwd;
        }
      }
      if (blob) {
        p.wobble = 0.03;
        p.wobblePhase = t * 12;
      }

    case Anim.shoot:
      final arm = c.front(LimbKind.arm, fwd);
      final aim = _ease(t / 0.18);
      final recoil = _bump(t, 0.3, 0.5);
      final back = _ease((t - 0.45) / 0.25);
      p.lean = (0.12 * aim - 0.2 * recoil) * fwd * (1 - back);
      p.dx = -0.05 * recoil * fwd;
      p.glow = 0.8 * aim * (1 - back);
      if (arm != null) {
        p.a[arm] = _toward(c, arm, fwdAngle - 0.1 * fwd, 1) * aim * (1 - back);
        p.b[arm] = -0.1 * fwd * recoil;
      } else {
        p.sy = 1 - 0.12 * aim * (1 - back) + 0.1 * recoil;
        p.sx = 1 / math.sqrt(p.sy);
      }

    case Anim.hit:
      final decay = math.exp(-6 * t);
      p.lean = -0.35 * fwd * decay * math.cos(14 * t);
      p.dx = -0.08 * fwd * (1 - math.exp(-10 * t));
      p.sy = 1 - 0.14 * math.exp(-10 * t);
      p.sx = 1 / math.sqrt(p.sy);
      p.flash = t < 0.12 ? 1 : (t < 0.2 ? 0.4 : 0);
      for (final (i, l) in limbs.indexed) {
        if (l.kind == LimbKind.arm || l.kind == LimbKind.leg) {
          p.a[i] += 0.35 * decay * math.sin(22 * t + i);
        }
      }
      if (blob) {
        p.wobble = 0.08 * decay;
        p.wobblePhase = t * 25;
      }

    case Anim.faint:
      final hop = _bump(t, 0, 0.25);
      final fall = _ease((t - 0.22) / 0.45);
      final bounce = _bump(t, 0.67, 0.85);
      p.dy = -0.12 * hop - 0.04 * bounce;
      p.rot = -fwd * (math.pi / 2) * fall;
      p.sy = 1 - 0.08 * fall;
      p.sx = 1 / math.sqrt(p.sy);
      for (final (i, l) in limbs.indexed) {
        if (l.kind == LimbKind.arm) p.a[i] = 0.5 * fall * (i.isEven ? 1 : -1);
        if (l.kind == LimbKind.head) p.a[i] = 0.3 * fall * -fwd;
      }

    case Anim.hop:
      const period = 0.42;
      final s = (math.sin(math.pi * t / period)).abs();
      p.dy = -0.1 * k * s;
      final contact = 1 - s;
      p.sy = 1 - 0.1 * contact * contact + 0.05 * s;
      p.sx = 1 / math.sqrt(p.sy);
      for (final (i, l) in limbs.indexed) {
        if (l.kind == LimbKind.arm) {
          p.a[i] = 0.25 * k * s * (l.tip.x < rig.root.x ? 1 : -1);
        } else if (l.kind == LimbKind.leg) {
          p.b[i] = 0.25 * contact * fwd;
        }
      }
      if (blob) {
        p.wobble = 0.03;
        p.wobblePhase = t * 14;
      }

    case Anim.squash:
      final dn = _bump(t, 0, 0.22);
      final up = _bump(t, 0.18, 0.48);
      final settle = math.exp(-8 * math.max(0, t - 0.4)) *
          math.sin(30 * math.max(0, t - 0.4));
      p.sy = 1 - 0.28 * k * dn + 0.16 * k * up + 0.05 * settle;
      p.sx = 1 / math.sqrt(p.sy);
      p.dy = -0.12 * k * up;
      p.wobble = 0.05 * (dn + up);
      p.wobblePhase = t * 20;

    case Anim.wobble:
      final w = 2 * math.pi * t / 0.9;
      p.wobble = 0.07 * k;
      p.wobblePhase = w;
      p.sy = 1 + 0.06 * k * math.sin(2 * w);
      p.sx = 1 / math.sqrt(p.sy);
      p.lean = 0.06 * math.sin(w);

    case Anim.victory:
      const period = 0.55;
      final s = (math.sin(math.pi * t / period)).abs();
      p.dy = -0.14 * s * k;
      p.sy = 1 + 0.06 * s - 0.1 * (1 - s) * (1 - s);
      p.sx = 1 / math.sqrt(p.sy);
      for (final (i, l) in limbs.indexed) {
        if (l.kind == LimbKind.arm) {
          final side = l.tip.x < rig.root.x ? -1.0 : 1.0;
          p.a[i] =
              _toward(c, i, _dirAngle(0.5 * side, -1), 0.95) +
              0.25 * math.sin(2 * math.pi * t / 0.4 + i);
        }
      }
      if (blob) {
        p.wobble = 0.04;
        p.wobblePhase = t * 10;
      }
  }
}
