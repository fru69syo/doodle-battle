import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import '../inflate/procedural_rig.dart';
import 'atb.dart';

/// What a fighter is doing on stage.
enum StageMode { roam, dashIn, attack, recover, hitstun, fainted, victory }

/// Per-fighter state the renderer applies every frame.
class FighterView {
  FighterView(this.side, this.position);
  final int side;

  /// Feet position on the ground plane (y = 0).
  Vector3 position;

  /// Rotation about +Y; the model's +Z (its face) points along
  /// (sin yaw, 0, cos yaw).
  double yaw = 0;
  StageMode mode = StageMode.roam;

  /// Clip to play ([RigClips]); [clipToken] changes whenever it must restart.
  String clip = RigClips.idle;
  int clipToken = 0;
  double modeTime = 0;
}

/// Camera for this frame.
class CameraView {
  CameraView(this.eye, this.target, this.fovY);
  final Vector3 eye;
  final Vector3 target;
  final double fovY;
}

/// One-shot visual cue (the renderer spawns particles / numbers).
class ImpactCue {
  const ImpactCue(
    this.targetSide,
    this.damage,
    this.position, {
    this.ko = false,
  });
  final int targetSide;
  final int damage;
  final Vector3 position;
  final bool ko;
}

/// Turns ATB events into 3D choreography: auto-movement (approach / circle
/// / retreat), attack dashes timed to the clips, knock-back, and a dynamic
/// camera (3/4 side view that drifts, punches in on attacks, shakes on hits,
/// orbits the winner). Pure Dart and deterministic for a given seed, so it
/// is unit-tested without a GPU and could run unchanged against any
/// renderer (flutter_scene here; Filament/Unity would only re-implement the
/// "apply" step).
class BattleDirector {
  BattleDirector({int seed = 3, this.arenaRadius = 3.2})
    : _rng = math.Random(seed),
      fighters = [
        FighterView(0, Vector3(-1.4, 0, 0.3)),
        FighterView(1, Vector3(1.4, 0, -0.3)),
      ] {
    for (final f in fighters) {
      f.yaw = _yawTo(f, _other(f));
    }
    _snapCamera();
  }

  final double arenaRadius;
  final List<FighterView> fighters;
  final math.Random _rng;

  /// Seconds into the attack clip at which the lunge connects.
  static const impactAt = 0.3;
  static const roamSpeed = 1.1;
  static const dashSpeed = 4.5;
  static const contactDistance = 1.05;
  static const minDistance = 0.9;

  final _intent = [_Intent.approach, _Intent.circleLeft];
  final _intentLeft = [1.2, 1.6];
  final _pending = <_PendingHit>[];
  final _cues = <ImpactCue>[];
  final _actionQueue = <ActionStarted>[];
  int? _winner;
  double _time = 0;
  double _shake = 0;
  double _punch = 0; // 0..1 camera punch-in during attacks
  int? _focusSide;

  late Vector3 _eye;
  late Vector3 _target;
  double _fov = 52;

  /// Impact cues produced since the last [takeCues].
  List<ImpactCue> takeCues() {
    final c = List.of(_cues);
    _cues.clear();
    return c;
  }

  CameraView get camera => CameraView(_eye.clone(), _target.clone(), _fov);

  /// Feeds simulation events.
  void handle(AtbEvent e) {
    switch (e) {
      case ActionStarted():
        _actionQueue.add(e);
      case BattleOver(:final winner):
        _winner = winner;
      case GaugeFull():
        break;
    }
  }

  void update(double dt) {
    _time += dt;
    _startQueuedAction();
    for (final f in fighters) {
      f.modeTime += dt;
      _updateFighter(f, dt);
    }
    _separate();
    for (final p in _pending.toList()) {
      p.left -= dt;
      if (p.left <= 0) {
        _pending.remove(p);
        _impact(p);
      }
    }
    _updateCamera(dt);
  }

  // --- fighters -------------------------------------------------------------

  FighterView _other(FighterView f) => fighters[1 - f.side];

  double _yawTo(FighterView f, FighterView o) {
    final d = o.position - f.position;
    return math.atan2(d.x, d.z);
  }

  double _dist() => fighters[0].position.distanceTo(fighters[1].position);

  void _setMode(FighterView f, StageMode m, String clip) {
    f.mode = m;
    f.modeTime = 0;
    _play(f, clip);
  }

  void _play(FighterView f, String clip) {
    f.clip = clip;
    f.clipToken++;
  }

  bool _busy(FighterView f) =>
      f.mode == StageMode.dashIn ||
      f.mode == StageMode.attack ||
      f.mode == StageMode.hitstun;

  void _startQueuedAction() {
    if (_actionQueue.isEmpty) return;
    final a = _actionQueue.first;
    final att = fighters[a.side];
    if (_busy(att) || _busy(_other(att)) || att.mode == StageMode.fainted) {
      return;
    }
    _actionQueue.removeAt(0);
    _focusSide = a.side;
    _setMode(att, StageMode.dashIn, RigClips.hop);
    _pending.add(
      _PendingHit(
        a,
        // Dash time is estimated; the hit is re-timed when the clip starts.
        double.infinity,
      ),
    );
  }

  void _updateFighter(FighterView f, double dt) {
    final o = _other(f);
    switch (f.mode) {
      case StageMode.fainted:
        return;
      case StageMode.victory:
        f.yaw = _approachAngle(
          f.yaw,
          math.atan2(_eye.x - f.position.x, _eye.z - f.position.z),
          dt * 4,
        );
        if (f.modeTime > 0.75) {
          f.modeTime = 0;
          _play(f, RigClips.hop);
        }
        return;
      case StageMode.dashIn:
        final d = o.position - f.position
          ..y = 0;
        final dist = d.length;
        f.yaw = _yawTo(f, o);
        if (dist > contactDistance && f.modeTime < 0.6) {
          f.position +=
              d.normalized() * math.min(dashSpeed * dt, dist - contactDistance);
        } else {
          _setMode(f, StageMode.attack, RigClips.attack);
          for (final p in _pending) {
            if (p.action.side == f.side && p.left == double.infinity) {
              p.left = impactAt;
            }
          }
        }
        return;
      case StageMode.attack:
        f.yaw = _yawTo(f, o);
        if (f.modeTime > 0.7) {
          _setMode(f, StageMode.recover, RigClips.hop);
        }
        return;
      case StageMode.hitstun:
        // Knock-back slides away from the attacker, easing out.
        final away = (f.position - o.position)..y = 0;
        if (away.length2 > 1e-6) {
          final speed = 2.2 * math.max(0, 1 - f.modeTime / 0.3);
          f.position += away.normalized() * speed * dt;
        }
        if (f.modeTime > 0.5) {
          if (f.side != _winner && _winner != null) {
            _setMode(f, StageMode.fainted, RigClips.faint);
          } else {
            _setMode(f, StageMode.roam, RigClips.idle);
          }
        }
        _clampArena(f);
        return;
      case StageMode.recover:
        // Back off to a comfortable distance, then roam again.
        f.yaw = _yawTo(f, o);
        final away = (f.position - o.position)..y = 0;
        if (away.length < 2.2 && f.modeTime < 0.8) {
          f.position += away.normalized() * roamSpeed * 1.4 * dt;
          if (f.modeTime % 0.6 < dt) _play(f, RigClips.hop);
          _clampArena(f);
        } else {
          _setMode(
            f,
            _winner == f.side ? StageMode.victory : StageMode.roam,
            RigClips.idle,
          );
        }
        return;
      case StageMode.roam:
        _roam(f, o, dt);
    }
  }

  void _roam(FighterView f, FighterView o, double dt) {
    if (_winner != null) {
      if (_winner == f.side && !_busy(o)) {
        _setMode(f, StageMode.victory, RigClips.hop);
      }
      return;
    }
    _intentLeft[f.side] -= dt;
    if (_intentLeft[f.side] <= 0) {
      final r = _rng.nextDouble();
      final dist = _dist();
      _intent[f.side] = dist > 2.8
          ? _Intent.approach
          : dist < 1.6
          ? _Intent.retreat
          : r < 0.3
          ? _Intent.approach
          : r < 0.5
          ? _Intent.retreat
          : r < 0.75
          ? _Intent.circleLeft
          : r < 0.9
          ? _Intent.circleRight
          : _Intent.idle;
      _intentLeft[f.side] = 1.0 + _rng.nextDouble() * 1.5;
    }
    final toO = (o.position - f.position)..y = 0;
    final dist = toO.length;
    final dir = dist > 1e-6 ? toO / dist : Vector3(1, 0, 0);
    final tangent = Vector3(-dir.z, 0, dir.x);
    Vector3 v;
    switch (_intent[f.side]) {
      case _Intent.approach:
        v = dist > 1.7 ? dir : Vector3.zero();
      case _Intent.retreat:
        v = dist < 3.0 ? -dir : Vector3.zero();
      case _Intent.circleLeft:
        v = tangent + dir * (dist - 2.2) * 0.5;
      case _Intent.circleRight:
        v = -tangent + dir * (dist - 2.2) * 0.5;
      case _Intent.idle:
        v = Vector3.zero();
    }
    // Stay inside the ring: steer back when near the edge.
    final r = f.position.length;
    if (r > arenaRadius * 0.8) {
      v += -f.position.normalized() * ((r - arenaRadius * 0.8) * 3);
    }
    final moving = v.length2 > 1e-4;
    if (moving) {
      f.position += v.normalized() * roamSpeed * dt;
      // Hop-hop locomotion.
      if (f.clip != RigClips.hop || f.modeTime > 0.6) {
        f.modeTime = 0;
        _play(f, RigClips.hop);
      }
    } else if (f.clip != RigClips.idle && f.modeTime > 0.6) {
      _play(f, RigClips.idle);
    }
    f.yaw = _approachAngle(f.yaw, _yawTo(f, o), dt * 8);
    _clampArena(f);
  }

  void _clampArena(FighterView f) {
    final r = f.position.length;
    if (r > arenaRadius) f.position.scale(arenaRadius / r);
  }

  void _separate() {
    final a = fighters[0], b = fighters[1];
    final d = (b.position - a.position)..y = 0;
    final dist = d.length;
    if (dist >= minDistance || dist < 1e-6) return;
    final push = d.normalized() * ((minDistance - dist) / 2);
    a.position -= push;
    b.position += push;
  }

  void _impact(_PendingHit p) {
    final att = fighters[p.action.side];
    final tgt = _other(att);
    final ko = _winner == att.side && _actionQueue.isEmpty;
    final at = (att.position + tgt.position) * 0.5
      ..y = 0.55;
    _cues.add(ImpactCue(tgt.side, p.action.damage, at, ko: ko));
    _setMode(tgt, StageMode.hitstun, RigClips.hit);
    _shake = ko ? 1.0 : 0.6;
  }

  static double _approachAngle(double from, double to, double k) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return from + d * math.min(1, k);
  }

  // --- camera ---------------------------------------------------------------

  /// Portrait-friendly 3/4 view from behind the player: the fighters'
  /// axis runs diagonally up the screen (player lower-left, CPU upper-right)
  /// so both fit a tall phone screen without a very wide FOV.
  (Vector3, Vector3, double) _desiredCamera() {
    final a = fighters[0].position, b = fighters[1].position;
    // Aim a little toward the player, who is closer to the lens.
    final mid = a + (b - a) * 0.46;
    final axis = (b - a)..y = 0;
    if (axis.length2 < 1e-6) axis.setValues(1, 0, 0);
    axis.normalize();
    // screen-right = up × forward; with forward = perp·cosθ + axis·sinθ the
    // CPU (further along the axis) is to the right of the player.
    final perp = Vector3(-axis.z, 0, axis.x);
    final sep = a.distanceTo(b);
    var theta = 1.2 + 0.08 * math.sin(_time * 0.25);
    var dist = (3.8 + sep * 1.45).clamp(6.0, 9.5);
    var pitch = 0.5; // radians above the horizon
    var fov = 52.0;
    final target = mid.clone()..y = 0.45;
    Vector3 forward;

    if (_winner != null) {
      // Slow orbit around the winner.
      final w = fighters[_winner!];
      target.setValues(w.position.x, 0.5, w.position.z);
      forward = Vector3(math.sin(_time * 0.5), 0, math.cos(_time * 0.5));
      dist = 3.6;
      pitch = 0.3;
    } else {
      if (_punch > 0 && _focusSide != null) {
        // Swing toward the attacker's back and move in.
        theta += (_focusSide == 0 ? 0.25 : -0.45) * _punch;
        dist *= 1 - 0.1 * _punch;
        fov -= 3 * _punch;
        pitch -= 0.12 * _punch;
      }
      forward = perp * math.cos(theta) + axis * math.sin(theta);
    }
    final eye = target - forward * (dist * math.cos(pitch))
      ..y = target.y + dist * math.sin(pitch);
    return (eye, target, fov);
  }

  void _snapCamera() {
    final (e, t, f) = _desiredCamera();
    _eye = e;
    _target = t;
    _fov = f;
  }

  void _updateCamera(double dt) {
    final attacking = fighters.any(
      (f) => f.mode == StageMode.dashIn || f.mode == StageMode.attack,
    );
    _punch += ((attacking ? 1.0 : 0.0) - _punch) * (1 - math.exp(-dt / 0.18));
    final (e, t, f) = _desiredCamera();
    final k = 1 - math.exp(-dt / 0.35);
    _eye += (e - _eye) * k;
    _target += (t - _target) * k;
    _fov += (f - _fov) * k;
    if (_shake > 0) {
      _shake = math.max(0, _shake - dt * 3);
      final a = 0.07 * _shake * _shake;
      _eye.x += a * math.sin(_time * 61);
      _eye.y += a * math.sin(_time * 47 + 1);
      _target.x += a * 0.5 * math.sin(_time * 53 + 2);
    }
  }
}

enum _Intent { approach, retreat, circleLeft, circleRight, idle }

class _PendingHit {
  _PendingHit(this.action, this.left);
  final ActionStarted action;
  double left;
}
