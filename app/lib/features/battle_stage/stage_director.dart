import 'dart:math' as math;

import '../puppet/anim/clips.dart';
import 'stage_camera.dart';
import 'stage_events.dart';

export 'stage_camera.dart';

enum _Intent { approach, circle, retreat, wait }

enum FighterMode { roam, dash, act, back, hurt, down, win }

/// What the renderer needs for one fighter this frame.
class StageFighter {
  StageFighter(this.side, this.x, this.z);
  final int side;
  double x, z;

  /// Height above the ground (world units), e.g. knock-back arcs.
  double lift = 0;
  Anim anim = Anim.idle;
  double animT = 0;

  /// +1: faces right on screen.
  int dir = 1;
  FighterMode mode = FighterMode.roam;

  /// HP shown on screen (drops at the visual impact, not at the engine
  /// tick).
  double shownHp = 0;

  /// Status visuals (from engine state each frame).
  bool poisoned = false, paralyzed = false;
  double shield = 0;

  /// Aura while charging a cast.
  bool charging = false;
}

/// A visual effect cue for the renderer (positions in world units).
class Fx {
  Fx(
    this.kind,
    this.x,
    this.z, {
    this.y = 0.6,
    this.tx,
    this.tz,
    this.colour = 'yellow',
    this.text,
    this.value = 0,
    this.duration = 0.6,
    this.side = 0,
    this.big = false,
    this.scale = 1,
    this.drawn = false,
  });
  final String
  kind; // vfx name, or 'number', 'heal', 'miss', 'crit', 'status', 'ko'
  final double x, z, y;
  final double? tx, tz; // projectile target
  final String colour;
  final String? text;
  final int value;
  final double duration;
  final int side;
  final bool big;

  /// Effect intensity (simple look 0.5, normal 1, でんせつ 1.4, ×1.25
  /// for ひっさつ).
  final double scale;

  /// Use the side's drawn move effect (docs/LOOP.md) when there is one.
  final bool drawn;
  double age = 0;
}

class _Action {
  _Action(this.e, {required this.fast});
  final StageAction e;
  final bool fast;
  double t = 0;
  int hitsShown = 0;
  late double impactAt;
  late double length;
  late Anim anim;
  bool resultsShown = false;
  int get side => e.side;
  StageMove get move => e.move;
}

/// Turns stage events (from an engine adapter, [StageFeed]) into 2.5D choreography: auto-movement with
/// depth, dashes, clip choice per move template, impacts timed to the clip,
/// per-move effects, a camera that pans/zooms/shakes. Pure Dart and
/// deterministic per seed; the renderer only draws what it says. Online,
/// the same director consumes the server's event stream (delayed 150–250
/// ms), so nothing here is authoritative.
class StageDirector {
  StageDirector({
    required this.contexts,
    int seed = 1,
    this.fxScale = const [1, 1],
    this.halfWidth = const [0.4, 0.4],
  }) : _rng = math.Random(seed),
       fighters = [StageFighter(0, -1.2, 0.5), StageFighter(1, 1.2, 1.9)] {
    fighters[0].dir = 1;
    fighters[1].dir = -1;
    _frame(snap: true);
  }

  /// Per side: what the character's rig can do (arms? blob?).
  final List<AnimContext> contexts;

  /// Per side effect intensity (0.5 simplified look, 1 normal, 1.4 Lv50+).
  final List<double> fxScale;

  /// Per side half width of the drawing (world units): wide animals and
  /// cars need more room to be hit without overlapping.
  final List<double> halfWidth;
  final List<StageFighter> fighters;
  final math.Random _rng;
  final camera = StageCamera();
  final List<Fx> fx = [];
  final _queue = <_Action>[];
  _Action? _current;
  final _intent = [_Intent.approach, _Intent.circle];
  final _intentLeft = [0.8, 1.4];
  final _home = <int, (double, double)>{};
  int? winner;
  int? _pendingWinner;
  double time = 0;
  double _shake = 0;
  double _focus = 0; // 0..1 camera punch-in
  int _variant = 0;

  /// Camera shake strength (0 turns it off, e.g. for reduced motion).
  double shakeScale = 1;

  static const xMin = -2.2, xMax = 2.2;

  /// Screen size the camera frames for (set by the painter).
  double viewW = 393, viewH = 851;
  static const zNear = [0.15, 1.2], zFar = [1.4, 2.8];

  /// Feeds one event (in order).
  void handle(StageEvent e) {
    switch (e) {
      case StageChoose(:final side, :final castSeconds):
        if (castSeconds > 0) fighters[side].charging = true;
      case StageAction():
        fighters[e.side].charging = false;
        _queue.add(_Action(e, fast: _queue.isNotEmpty || _current != null));
      case StagePoisonTick(:final target, :final amount, :final hpAfter):
        final f = fighters[target];
        f.shownHp = hpAfter.toDouble();
        fx.add(
          Fx(
            'number',
            f.x,
            f.z,
            y: 1.1,
            value: amount,
            colour: 'purple',
            duration: 0.8,
            side: target,
          ),
        );
      case StageEnd(:final winner):
        // Shown once the last action has played out.
        _pendingWinner = winner;
      case StageReady():
        break;
    }
  }

  /// Per-frame status mirror (status visuals, shield bubble).
  void syncStatus(List<StageFighterState> states) {
    for (var i = 0; i < 2; i++) {
      final f = states[i];
      fighters[i].poisoned = f.poisoned;
      fighters[i].paralyzed = f.paralyzed;
      fighters[i].shield = f.shield;
    }
  }

  /// True while an action is playing or queued.
  bool get busy => _current != null || _queue.isNotEmpty;

  void update(double dt) {
    time += dt;
    for (final f in fighters) {
      f.animT += dt;
    }
    if (_current == null && _queue.isNotEmpty) _start(_queue.removeAt(0));
    if (_current != null) _runAction(_current!, dt);
    if (_pendingWinner != null && _current == null && _queue.isEmpty) {
      winner = _pendingWinner;
      _pendingWinner = null;
      final l = fighters[1 - winner!];
      fx.add(
        Fx(
          'ko',
          l.x,
          l.z,
          y: 1.0,
          text: 'K.O.',
          duration: 1.6,
          side: l.side,
          big: true,
        ),
      );
      _shake = 16;
    }
    for (final f in fighters) {
      _updateFighter(f, dt);
    }
    _separate();
    for (final e in fx) {
      e.age += dt;
    }
    fx.removeWhere((e) => e.age > e.duration);
    _frame(dt: dt);
  }

  // --- movement ------------------------------------------------------------

  void _updateFighter(StageFighter f, double dt) {
    final o = fighters[1 - f.side];
    if (f.lift > 0 && f.mode != FighterMode.act) {
      f.lift = math.max(0, f.lift - dt * 2.5);
    }
    if (winner != null && f.mode != FighterMode.act) {
      if (f.side == winner) {
        _setAnim(f, Anim.victory);
        f.mode = FighterMode.win;
        f.dir = f.side == 0 ? 1 : -1;
      } else if (f.mode != FighterMode.down) {
        f.mode = FighterMode.down;
        _setAnim(f, Anim.faint, restart: true);
      }
      return;
    }
    if (f.mode == FighterMode.hurt) {
      if (f.animT > (kAnimLength[Anim.hit] ?? 0.5)) f.mode = FighterMode.roam;
      return;
    }
    if (f.mode != FighterMode.roam) return;
    // Always face the opponent.
    f.dir = o.x >= f.x ? 1 : -1;
    final s = f.side;
    _intentLeft[s] -= dt;
    if (_intentLeft[s] <= 0) {
      final r = _rng.nextDouble();
      _intent[s] = r < 0.35
          ? _Intent.approach
          : r < 0.7
          ? _Intent.circle
          : r < 0.85
          ? _Intent.retreat
          : _Intent.wait;
      _intentLeft[s] = 1.0 + _rng.nextDouble() * 1.5;
    }
    var vx = 0.0, vz = 0.0;
    final dx = o.x - f.x;
    final dist = dx.abs();
    switch (_intent[s]) {
      case _Intent.approach:
        if (dist > 1.7) vx = dx.sign;
      case _Intent.circle:
        final zr = s == 0 ? zNear : zFar;
        final target = (_intentLeft[s] * 7).floor().isEven ? zr[1] : zr[0];
        vz = (target - f.z).sign * 0.8;
        if (dist < 1.4) vx = -dx.sign * 0.6;
      case _Intent.retreat:
        if (dist < 3.2) vx = -dx.sign * 0.8;
      case _Intent.wait:
        break;
    }
    const speed = 0.9;
    f.x = (f.x + vx * speed * dt).clamp(xMin, xMax);
    final zr = s == 0 ? zNear : zFar;
    f.z = (f.z + vz * speed * dt).clamp(zr[0], zr[1]);
    final moving = vx != 0 || vz != 0;
    _setAnim(f, f.charging ? Anim.cast : (moving ? Anim.walk : Anim.idle));
  }

  /// Keep the player left of the opponent with a gap (readable layout).
  void _separate() {
    final a = fighters[0], b = fighters[1];
    if (a.mode == FighterMode.dash || b.mode == FighterMode.dash) return;
    if (_current != null) return;
    final gap = halfWidth[0] + halfWidth[1] + 0.2;
    if (b.x - a.x < gap) {
      final mid = (a.x + b.x) / 2;
      a.x = mid - gap / 2;
      b.x = mid + gap / 2;
    }
  }

  void _setAnim(StageFighter f, Anim a, {bool restart = false}) {
    if (f.anim == a && !restart) return;
    f.anim = a;
    f.animT = 0;
  }

  // --- actions -------------------------------------------------------------

  void _start(_Action a) {
    _current = a;
    final f = fighters[a.side];
    _home[a.side] = (f.x, f.z);
    final m = a.move;
    final ctx = contexts[a.side];
    switch (m.kind) {
      case StageMoveKind.physical:
        a.anim = ctx.physicalClip(_variant++);
        final dash = a.fast ? 0.0 : 0.28;
        a.impactAt = dash + (kAnimImpact[a.anim] ?? 0.3);
        a.length =
            dash +
            (kAnimLength[a.anim] ?? 0.7) +
            (a.fast ? 0.1 : 0.3) +
            0.12 * (m.hits - 1);
        f.mode = a.fast ? FighterMode.act : FighterMode.dash;
      case StageMoveKind.ranged:
        a.anim = Anim.shoot;
        a.impactAt = 0.3 + 0.32; // shoot + travel
        a.length = 0.95 + 0.12 * (m.hits - 1);
        f.mode = FighterMode.act;
      case StageMoveKind.self:
        a.anim = Anim.cast;
        a.impactAt = 0.45;
        a.length = 0.85;
        f.mode = FighterMode.act;
    }
    if (f.mode == FighterMode.act) _setAnim(f, a.anim, restart: true);
  }

  static String _effText(StageEffectiveness e) => switch (e) {
    StageEffectiveness.strong => 'ばつぐん！',
    StageEffectiveness.weak => 'いまひとつ…',
    StageEffectiveness.normal => '',
  };

  void _runAction(_Action a, double dt) {
    a.t += dt;
    final f = fighters[a.side];
    final o = fighters[1 - a.side];
    final m = a.move;
    _focus = math.min(1, _focus + dt * 4);
    f.dir = o.x >= f.x ? 1 : -1;
    if (f.mode == FighterMode.dash) {
      // Run to the target, stopping where a swung arm reaches the other
      // drawing.
      final tx = o.x - f.dir * (0.55 * (halfWidth[0] + halfWidth[1]) + 0.15);
      final tz = o.z + (a.side == 0 ? -0.12 : 0.12);
      final k = math.min(1.0, dt * 9);
      f.x += (tx - f.x) * k;
      f.z += (tz - f.z) * k;
      _setAnim(f, Anim.walk);
      if (a.t >= 0.28) {
        f.mode = FighterMode.act;
        _setAnim(f, a.anim, restart: true);
      }
    }
    final scale = fxScale[a.side] * (m.special ? 1.25 : 1);
    final big = scale > 1.2;
    // Projectile leaves the hand.
    if (m.kind == StageMoveKind.ranged && a.t - dt < 0.3 && a.t >= 0.3) {
      fx.add(
        Fx(
          m.vfx,
          f.x + f.dir * 0.35,
          f.z,
          y: 0.65,
          tx: o.x,
          tz: o.z,
          colour: m.colour,
          duration: 0.34,
          side: a.side,
          big: big,
          scale: scale,
          drawn: m.drawnEffect,
        ),
      );
    }
    if (m.kind == StageMoveKind.self && (a.t - dt < 0.05 && a.t >= 0.05)) {
      fx.add(
        Fx(
          m.vfx,
          f.x,
          f.z,
          y: 0.6,
          colour: m.colour,
          duration: 0.9,
          side: a.side,
          big: big,
          scale: scale,
          drawn: m.drawnEffect,
        ),
      );
    }
    // Impacts: one per hit, 0.12 s apart.
    final hits = a.e.hits;
    while (a.hitsShown < math.max(1, hits.length) &&
        a.t >= a.impactAt + 0.12 * a.hitsShown) {
      final h = hits.isEmpty ? null : hits[a.hitsShown];
      a.hitsShown++;
      if (h == null) break;
      final tf = fighters[h.target];
      if (h.missed) {
        fx.add(
          Fx(
            'miss',
            tf.x,
            tf.z,
            y: 1.3,
            text: 'はずれ',
            duration: 0.8,
            side: h.target,
          ),
        );
        continue;
      }
      if (h.hpAfter != null) tf.shownHp = h.hpAfter!.toDouble();
      fx.add(
        Fx(
          'number',
          tf.x,
          tf.z,
          y: 1.15,
          value: h.amount!,
          colour: h.crit
              ? 'orange'
              : (h.effectiveness == StageEffectiveness.weak ? 'grey' : 'white'),
          duration: 0.9,
          side: h.target,
          big: h.crit || h.effectiveness == StageEffectiveness.strong,
        ),
      );
      fx.add(
        Fx(
          m.kind == StageMoveKind.physical ? m.vfx : 'burst',
          tf.x - f.dir * 0.15,
          tf.z,
          y: 0.55,
          colour: m.colour,
          duration: m.kind == StageMoveKind.physical ? 0.45 : 0.4,
          side: a.side,
          big: big,
          scale: scale,
          drawn: m.drawnEffect && m.kind == StageMoveKind.physical,
        ),
      );
      if (a.hitsShown == 1) {
        if (h.crit) {
          fx.add(
            Fx(
              'crit',
              tf.x,
              tf.z,
              y: 1.5,
              text: 'かいしん！',
              duration: 0.9,
              side: h.target,
            ),
          );
        }
        final eff = _effText(h.effectiveness);
        if (eff.isNotEmpty) {
          fx.add(
            Fx(
              h.effectiveness == StageEffectiveness.strong ? 'strong' : 'weak',
              tf.x,
              tf.z,
              y: h.crit ? 1.85 : 1.55,
              text: eff,
              duration: 1.0,
              side: h.target,
            ),
          );
        }
      }
      if (tf.mode != FighterMode.down) {
        tf.mode = FighterMode.hurt;
        _setAnim(tf, Anim.hit, restart: true);
        tf.x = (tf.x + f.dir * 0.18).clamp(xMin, xMax);
        tf.lift = 0.12;
      }
      final strong = h.crit || h.effectiveness == StageEffectiveness.strong;
      _shake = math.max(
        _shake,
        (strong ? 14.0 : 8.0) * scale.clamp(0.6, 1.4) * shakeScale,
      );
    }
    if (!a.resultsShown && a.t >= a.impactAt) {
      a.resultsShown = true;
      for (final e in a.e.outcomes) {
        switch (e) {
          case StageHealed(:final side, :final amount, :final hpAfter):
            fighters[side].shownHp = hpAfter.toDouble();
            fx.add(
              Fx(
                'heal',
                fighters[side].x,
                fighters[side].z,
                y: 1.15,
                value: amount,
                colour: 'green',
                duration: 0.9,
                side: side,
              ),
            );
          case StageStatus(:final target, :final status):
            fx.add(
              Fx(
                'status',
                fighters[target].x,
                fighters[target].z,
                y: 1.45,
                text: status == StageStatusKind.poison ? 'ねばねば！' : 'ビリビリ！',
                duration: 1.0,
                side: target,
              ),
            );
          case StageStatChange(:final side, :final up):
            fx.add(
              Fx(
                up ? 'up' : 'down',
                fighters[side].x,
                fighters[side].z,
                y: 1.4,
                text: up ? 'パワーアップ！' : 'よわくなった',
                duration: 1.0,
                side: side,
              ),
            );
          case StageShieldUp(:final side):
            fx.add(
              Fx(
                'status',
                fighters[side].x,
                fighters[side].z,
                y: 1.45,
                text: 'まもり！',
                duration: 1.0,
                side: side,
              ),
            );
        }
      }
    }
    // Return home after the clip.
    final animEnd = a.length - (a.fast ? 0.1 : 0.3);
    if (a.t >= animEnd &&
        m.kind == StageMoveKind.physical &&
        f.mode == FighterMode.act) {
      f.mode = FighterMode.back;
      _setAnim(f, Anim.walk);
    }
    if (f.mode == FighterMode.back) {
      final (hx, hz) = _home[a.side]!;
      final k = math.min(1.0, dt * 7);
      f.x += (hx - f.x) * k;
      f.z += (hz - f.z) * k;
    }
    if (a.t >= a.length) {
      if (f.mode != FighterMode.down && f.mode != FighterMode.hurt) {
        f.mode = FighterMode.roam;
        _setAnim(f, Anim.idle);
      }
      _current = null;
    }
  }

  // --- camera --------------------------------------------------------------

  void _frame({double dt = 0, bool snap = false}) {
    final a = fighters[0], b = fighters[1];
    var tx = (a.x + b.x) / 2;
    var tz = 0.0;
    var zoom = 1.0;
    final spread = (a.x - b.x).abs();
    zoom = (3.2 / math.max(2.4, spread + 1.2)).clamp(0.85, 1.15);
    final cur = _current;
    if (cur == null) _focus = math.max(0, _focus - dt * 2);
    if (cur != null || _focus > 0) {
      final f = fighters[cur?.side ?? 0];
      tx = tx * (1 - 0.3 * _focus) + f.x * 0.3 * _focus;
      zoom *= 1 + 0.22 * _focus;
      tz = 0.35 * _focus;
    }
    if (winner != null) {
      // Lean towards the winner but keep the fainted loser in the shot.
      final w = fighters[winner!], l = fighters[1 - winner!];
      tx = 0.65 * w.x + 0.35 * l.x;
      tz = 0.3;
      zoom = 1.2;
    }
    // Keep both fighters (their width) inside the screen: zoom out until
    // they fit, then clamp the pan.
    final probe = StageCamera(x: tx, z: tz, zoom: zoom);
    for (var i = 0; i < 12; i++) {
      var ok = true;
      for (final f in fighters) {
        final (sx, _, k) = probe.project(f.x, f.z, viewW, viewH);
        // A fainted fighter lies along the ground (≈ its height).
        final half =
            (f.mode == FighterMode.down ? 1.35 : halfWidth[f.side] + 0.1) * k;
        if (sx - half < viewW * 0.03 || sx + half > viewW * 0.97) ok = false;
      }
      if (ok) break;
      probe.zoom *= 0.94;
    }
    zoom = probe.zoom;
    // Vertical framing: the fighters' feet around 64 % of the screen
    // height (between the HP panels and the move buttons).
    var feetY = 0.0;
    for (final f in fighters) {
      feetY += probe.project(f.x, f.z, viewW, viewH).$2 - probe.tilt;
    }
    final tilt = 0.64 * viewH - feetY / 2;
    final k = snap ? 1.0 : math.min(1.0, dt * 4);
    camera.tilt += (tilt - camera.tilt) * k;
    camera.x += (tx - camera.x) * k;
    camera.z += (tz - camera.z) * k;
    camera.zoom +=
        (zoom - camera.zoom) * (zoom < camera.zoom ? math.max(k, 0.5) : k);
    _shake = math.max(0, _shake - dt * 40);
    camera.shakeX = _shake * math.sin(time * 70);
    camera.shakeY = _shake * 0.6 * math.cos(time * 53);
  }
}
