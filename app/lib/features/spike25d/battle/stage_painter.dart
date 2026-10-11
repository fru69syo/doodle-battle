import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../render/character_sprite.dart';
import 'director25d.dart';

/// Colours for the move `colour` vocabulary (moves_v2 `kColours`).
Color fxColour(String c) => switch (c) {
  'red' => const Color(0xFFFF4D4D),
  'orange' => const Color(0xFFFF9A2E),
  'yellow' => const Color(0xFFFFD83A),
  'green' => const Color(0xFF4CD964),
  'cyan' => const Color(0xFF3ADCF0),
  'blue' => const Color(0xFF4A7DFF),
  'purple' => const Color(0xFFB45CFF),
  'pink' => const Color(0xFFFF6EC7),
  'black' => const Color(0xFF3A3550),
  'white' => const Color(0xFFFFFFFF),
  _ => const Color(0xFFFF7AE0), // rainbow: pink base, particles vary
};

/// Draws one frame of the 2.5D stage: parallax sky / hills / trees, a
/// perspective ground, depth-sorted props and fighters with soft shadows,
/// and the move effects. Everything is ordinary Canvas drawing (paths,
/// gradients, drawVertices) that Skia-GLES2 and Impeller both support.
class StagePainter extends CustomPainter {
  StagePainter({
    required this.director,
    required this.sprites,
    required this.repaintSignal,
    this.legend = const [false, false],
    this.lowQuality = false,
  }) : super(repaint: repaintSignal);

  final Director25 director;
  final List<CharacterSprite> sprites;
  final Listenable repaintSignal;

  /// Lv50+ "でんせつ" aura (every character gets it at Lv50, so the hidden
  /// late bloomer's rebuild is indistinguishable).
  final List<bool> legend;

  /// Old / slow phones: no clouds, fewer props and particles.
  final bool lowQuality;

  /// World height of a character (units).
  static const charHeight = 1.25;

  static final _props = <(double, double, int)>[
    // x, z, kind (0 flower, 1 stone, 2 bush, 3 tuft)
    (-3.4, 2.6, 2),
    (3.3, 3.0, 2),
    (-2.2, 3.3, 1),
    (2.6, 0.2, 1),
    (-3.1, 0.9, 3),
    (0.4, 3.4, 0), (-0.8, 3.1, 3), (1.7, 3.5, 0), (3.6, 1.4, 3), (-3.8, 1.8, 0),
    (-1.6, -0.3, 3), (1.2, -0.4, 0), (2.9, 2.2, 0), (-2.7, 2.0, 0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cam = director.camera;
    final w = size.width, h = size.height;
    director
      ..viewW = w
      ..viewH = h;
    _sky(canvas, size, cam);
    _ground(canvas, size, cam);
    // Depth-sorted drawables: props and fighters (far first).
    final items = <(double, void Function())>[];
    for (final (i, p) in _props.indexed) {
      if (lowQuality && i.isOdd) continue;
      items.add((p.$2, () => _prop(canvas, size, cam, p.$1, p.$2, p.$3)));
    }
    for (final f in director.fighters) {
      items.add((f.z, () => _fighter(canvas, size, cam, f)));
    }
    items.sort((a, b) => b.$1.compareTo(a.$1));
    for (final it in items) {
      it.$2();
    }
    _effects(canvas, size, cam);
    // Gentle vignette for focus.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(Offset(w / 2, h * 0.55), h * 0.75, [
          const Color(0x00000000),
          const Color(0x22000000),
        ]),
    );
  }

  // --- background ----------------------------------------------------------

  void _sky(Canvas c, Size s, StageCamera cam) {
    final hz = cam.horizon(s.height);
    c.drawRect(
      Rect.fromLTWH(0, 0, s.width, hz + 2),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, hz), [
          const Color(0xFF8FD3FF),
          const Color(0xFFDDF3FF),
        ]),
    );
    final f = cam.focal(s.width, s.height);
    // Sun.
    final sunX = s.width * 0.82 - cam.x * f * 0.02;
    c.drawCircle(
      Offset(sunX, hz * 0.32),
      30,
      Paint()..color = const Color(0xFFFFE066),
    );
    c.drawCircle(
      Offset(sunX, hz * 0.32),
      44,
      Paint()..color = const Color(0x33FFE066),
    );
    // Clouds drift slowly (parallax 0.05).
    if (!lowQuality) {
      final t = director.time;
      for (var i = 0; i < 4; i++) {
        final x =
            ((i * 0.31 + t * 0.01) % 1.3 - 0.15) * s.width - cam.x * f * 0.05;
        _cloud(c, Offset(x, hz * (0.18 + 0.13 * (i % 3))), 26.0 + 8 * (i % 2));
      }
    }
    // Far hills (parallax 0.12) and near hills (0.25), crayon outlines.
    _hills(c, s, hz, -cam.x * f * 0.12, const Color(0xFFA7D99A), 0.55, 3);
    _hills(c, s, hz, -cam.x * f * 0.25, const Color(0xFF7CC576), 0.32, 5);
    // Tree line (parallax 0.4).
    for (var i = -2; i < 9; i++) {
      final x = i * s.width / 6 - cam.x * f * 0.4 + (i.isEven ? 10 : -6);
      _tree(c, Offset(x, hz + 4), 26 + 6.0 * ((i * 7) % 3));
    }
  }

  void _cloud(Canvas c, Offset o, double r) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.9);
    c.drawCircle(o, r, p);
    c.drawCircle(o.translate(r * 0.9, 4), r * 0.75, p);
    c.drawCircle(o.translate(-r * 0.9, 6), r * 0.65, p);
  }

  void _hills(
    Canvas c,
    Size s,
    double hz,
    double shift,
    Color col,
    double hFrac,
    int n,
  ) {
    final path = Path()..moveTo(-10, hz + 2);
    final period = s.width * 1.6 / n;
    for (double x = -10; x <= s.width + 10; x += 8) {
      final u = (x - shift) / period;
      final y =
          hz -
          hFrac *
              hz *
              0.5 *
              (0.55 + 0.45 * math.sin(u * math.pi) * math.sin(u * 0.37 + 1));
      path.lineTo(x, y);
    }
    path
      ..lineTo(s.width + 10, hz + 2)
      ..close();
    c.drawPath(path, Paint()..color = col);
    c.drawPath(
      path,
      Paint()
        ..color = const Color(0x553A6B35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _tree(Canvas c, Offset base, double r) {
    c.drawRect(
      Rect.fromCenter(
        center: base.translate(0, -r * 0.4),
        width: r * 0.25,
        height: r * 0.8,
      ),
      Paint()..color = const Color(0xFF8B5A2B),
    );
    final leaf = Paint()..color = const Color(0xFF4FAF5A);
    c.drawCircle(base.translate(0, -r * 1.05), r * 0.62, leaf);
    c.drawCircle(base.translate(-r * 0.35, -r * 0.8), r * 0.45, leaf);
    c.drawCircle(base.translate(r * 0.35, -r * 0.8), r * 0.45, leaf);
  }

  void _ground(Canvas c, Size s, StageCamera cam) {
    final hz = cam.horizon(s.height);
    c.drawRect(
      Rect.fromLTWH(0, hz, s.width, s.height - hz),
      Paint()..color = const Color(0xFF8ED36B),
    );
    // Perspective stripes (mowed grass), bands every 0.6 units of depth.
    final band = Paint()..color = const Color(0xFF9FDC7C);
    for (var z = -1.8; z < 14; z += 1.2) {
      final (_, y0, _) = cam.project(0, z, s.width, s.height);
      final (_, y1, _) = cam.project(0, z + 0.6, s.width, s.height);
      if (y0 < hz) break;
      c.drawRect(Rect.fromLTRB(0, y1, s.width, y0), band);
    }
    // Arena: a soft dirt ellipse on the ground (projected polygon).
    final ring = Path();
    for (var i = 0; i <= 48; i++) {
      final a = i / 48 * 2 * math.pi;
      final (x, y, _) = cam.project(
        2.9 * math.cos(a),
        1.5 + 1.75 * math.sin(a),
        s.width,
        s.height,
      );
      i == 0 ? ring.moveTo(x, y) : ring.lineTo(x, y);
    }
    c.drawPath(ring, Paint()..color = const Color(0x55F3E2A9));
    c.drawPath(
      ring,
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _prop(Canvas c, Size s, StageCamera cam, double x, double z, int kind) {
    final (sx, sy, k) = cam.project(x, z, s.width, s.height);
    if (sx < -80 || sx > s.width + 80) return;
    final u = k * 0.12; // ~12 cm
    switch (kind) {
      case 0: // flower
        c.drawLine(
          Offset(sx, sy),
          Offset(sx, sy - u * 2),
          Paint()
            ..color = const Color(0xFF3E9B45)
            ..strokeWidth = math.max(1, u * 0.25),
        );
        for (var i = 0; i < 5; i++) {
          final a = i / 5 * 2 * math.pi;
          c.drawCircle(
            Offset(
              sx + math.cos(a) * u * 0.6,
              sy - u * 2 + math.sin(a) * u * 0.6,
            ),
            u * 0.45,
            Paint()
              ..color = (x > 0
                  ? const Color(0xFFFF7BAC)
                  : const Color(0xFFFFE14D)),
          );
        }
        c.drawCircle(
          Offset(sx, sy - u * 2),
          u * 0.35,
          Paint()..color = const Color(0xFFFFA42E),
        );
      case 1: // stone
        c.drawOval(
          Rect.fromCenter(
            center: Offset(sx, sy - u * 0.6),
            width: u * 4,
            height: u * 2.2,
          ),
          Paint()..color = const Color(0xFFB9B4AE),
        );
        c.drawOval(
          Rect.fromCenter(
            center: Offset(sx - u * 0.5, sy - u * 1.0),
            width: u * 1.6,
            height: u * 0.7,
          ),
          Paint()..color = const Color(0x55FFFFFF),
        );
      case 2: // bush
        final p = Paint()..color = const Color(0xFF5DBB5A);
        c.drawCircle(Offset(sx, sy - u * 2.5), u * 2.6, p);
        c.drawCircle(Offset(sx - u * 2.2, sy - u * 1.5), u * 1.9, p);
        c.drawCircle(Offset(sx + u * 2.2, sy - u * 1.6), u * 2.0, p);
      default: // grass tuft
        final p = Paint()
          ..color = const Color(0xFF5FAE4C)
          ..strokeWidth = math.max(1.5, u * 0.35)
          ..strokeCap = StrokeCap.round;
        for (final d in [-1.0, -0.4, 0.3, 0.9]) {
          c.drawLine(
            Offset(sx + d * u, sy),
            Offset(sx + d * u * 1.8, sy - u * 2.4),
            p,
          );
        }
    }
  }

  // --- fighters ------------------------------------------------------------

  void _fighter(Canvas c, Size s, StageCamera cam, FighterView25 f) {
    final sprite = sprites[f.side];
    final (sx, sy, k) = cam.project(f.x, f.z, s.width, s.height);
    final scale = k * charHeight / math.max(1, sprite.height);
    final mirror = sprite.prepare(f.anim, f.animT, f.dir);
    final pose = sprite.pose;
    final liftPx = f.lift * k - pose.dy * sprite.data.rig.height * scale;
    // Shadow: shrinks as the character leaves the ground.
    final up = (liftPx / (k * charHeight)).clamp(0.0, 1.0);
    final sw = sprite.width * scale * 0.62 * (1 - 0.5 * up) * pose.sx;
    c.drawOval(
      Rect.fromCenter(center: Offset(sx, sy), width: sw, height: sw * 0.22),
      Paint()..color = Color.fromRGBO(30, 50, 20, 0.28 * (1 - 0.5 * up)),
    );
    final feet = Offset(sx, sy - f.lift * k);
    final top = feet.translate(0, -k * charHeight * 0.55);
    // Auras behind the character.
    if (legend[f.side]) {
      _aura(
        c,
        top,
        k * charHeight * 0.75,
        const Color(0xFFFFD54A),
        0.35 + 0.1 * math.sin(director.time * 4),
      );
    }
    if (f.charging || pose.glow > 0) {
      final g = math.max(pose.glow, f.charging ? 0.8 : 0);
      _aura(c, top, k * charHeight * 0.7, const Color(0xFF8FE3FF), 0.55 * g);
    }
    sprite.drawPose(
      c,
      sprite.placement(feet, scale, mirror: mirror),
      tint: f.paralyzed
          ? const Color(0xFFFFF27A)
          : (f.poisoned ? const Color(0xFFB45CFF) : null),
      tintAmount: f.paralyzed || f.poisoned
          ? 0.18 + 0.1 * math.sin(director.time * 9)
          : 0,
    );
    // Status visuals.
    if (f.shield > 0) {
      c.drawOval(
        Rect.fromCenter(
          center: top,
          width: k * charHeight * 1.05,
          height: k * charHeight * 1.25,
        ),
        Paint()
          ..shader = ui.Gradient.radial(top, k * charHeight * 0.65, [
            const Color(0x0066CCFF),
            const Color(0x5566CCFF),
          ]),
      );
      c.drawOval(
        Rect.fromCenter(
          center: top,
          width: k * charHeight * 1.05,
          height: k * charHeight * 1.25,
        ),
        Paint()
          ..color = const Color(0xAAFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    if (f.poisoned) {
      for (var i = 0; i < 4; i++) {
        final t = (director.time * 0.8 + i * 0.25) % 1;
        c.drawCircle(
          top.translate((i - 1.5) * k * 0.18, -t * k * 0.7),
          k * 0.05 * (1 - t) + 2,
          Paint()..color = const Color(0xAAB45CFF),
        );
      }
    }
    if (f.paralyzed && (director.time * 6).floor().isEven) {
      _zigzag(
        c,
        top.translate(-k * 0.35, -k * 0.2),
        top.translate(k * 0.35, -k * 0.45),
        const Color(0xFFFFE14D),
        3,
      );
    }
  }

  void _aura(Canvas c, Offset center, double r, Color col, double a) {
    c.drawCircle(
      center,
      r,
      Paint()
        ..shader = ui.Gradient.radial(center, r, [
          col.withValues(alpha: a),
          col.withValues(alpha: 0),
        ]),
    );
  }

  // --- effects -------------------------------------------------------------

  void _effects(Canvas c, Size s, StageCamera cam) {
    for (final e in director.fx) {
      final (sx, sy, k) = cam.project(e.x, e.z, s.width, s.height);
      final p = Offset(sx, sy - e.y * k);
      final t = (e.age / e.duration).clamp(0.0, 1.0);
      final col = fxColour(e.colour);
      final big = e.big ? 1.35 : 1.0;
      switch (e.kind) {
        case 'number' || 'heal':
          final rise = t * k * 0.35;
          _text(
            c,
            e.kind == 'heal' ? '+${e.value}' : '${e.value}',
            p.translate(0, -rise),
            size: (e.big ? 44 : 34) * (t < 0.15 ? 0.7 + 2 * t : 1.0),
            fill: e.kind == 'heal'
                ? const Color(0xFF4CD964)
                : (e.colour == 'purple'
                      ? const Color(0xFFD9A6FF)
                      : (e.colour == 'orange'
                            ? const Color(0xFFFFB13B)
                            : Colors.white)),
            alpha: t < 0.75 ? 1 : (1 - t) * 4,
          );
        case 'miss' || 'crit' || 'status' || 'up' || 'down' || 'ko':
          final pop = t < 0.15 ? 0.6 + t * 2.7 : 1.0;
          _text(
            c,
            e.text ?? '',
            p.translate(0, -t * k * 0.15),
            size: (e.kind == 'ko' ? 64 : 24) * pop,
            fill: switch (e.kind) {
              'crit' => const Color(0xFFFFB13B),
              'ko' => const Color(0xFFFF4D4D),
              'up' => const Color(0xFFFF9A2E),
              'down' => const Color(0xFF7FA7FF),
              'status' => const Color(0xFFD9A6FF),
              _ => const Color(0xFFEEEEEE),
            },
            alpha: t < 0.8 ? 1 : (1 - t) * 5,
          );
        default:
          _vfx(c, s, cam, e, p, t, col, k, big);
      }
    }
  }

  void _vfx(
    Canvas c,
    Size s,
    StageCamera cam,
    Fx e,
    Offset p,
    double t,
    Color col,
    double k,
    double big,
  ) {
    final r = k * 0.42 * big;
    final fade = (1 - t).clamp(0.0, 1.0);
    final n = lowQuality ? 5 : (8 * big).round();
    // Projectiles fly from (x, z) to (tx, tz).
    if (e.tx != null) {
      final (tx, ty, tk) = cam.project(e.tx!, e.tz!, s.width, s.height);
      final to = Offset(tx, ty - 0.6 * tk);
      final head = Offset.lerp(p, to, Curves.easeIn.transform(t))!;
      switch (e.kind) {
        case 'beam' || 'wave':
          final paint = Paint()
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(p, head, [
              col.withValues(alpha: 0.2),
              col,
            ]);
          c.drawLine(p, head, paint..strokeWidth = k * 0.22 * big);
          c.drawLine(
            p,
            head,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.9)
              ..strokeWidth = k * 0.07 * big
              ..strokeCap = StrokeCap.round,
          );
        case 'sparks':
          _zigzag(c, p, head, col, k * 0.05 * big);
        case 'rain' || 'bubbles' || 'leaves' || 'stars':
          for (var i = 0; i < n; i++) {
            final q = Offset.lerp(p, to, (t * 1.2 - i * 0.04).clamp(0.0, 1.0))!;
            final o = q.translate(
              math.sin(i * 2.1) * r * 0.3,
              math.cos(i * 1.7) * r * 0.3,
            );
            if (e.kind == 'stars') {
              _star(c, o, r * 0.25, col);
            } else {
              c.drawCircle(
                o,
                r * 0.12,
                Paint()..color = col.withValues(alpha: 0.85),
              );
            }
          }
        default: // orb, glow...
          c.drawCircle(
            head,
            r * 0.45,
            Paint()
              ..shader = ui.Gradient.radial(
                head,
                r * 0.45,
                [Colors.white, col, col.withValues(alpha: 0)],
                [0, 0.45, 1],
              ),
          );
      }
      return;
    }
    switch (e.kind) {
      case 'punch' || 'burst':
        // Star burst + ring.
        _star(
          c,
          p,
          r * (0.5 + 0.6 * t),
          col.withValues(alpha: fade),
          points: 8,
          inner: 0.45,
        );
        c.drawCircle(
          p,
          r * (0.4 + 1.1 * t),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.8 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4 * big,
        );
        for (var i = 0; i < n; i++) {
          final a = i / n * 2 * math.pi + 0.3;
          final d = r * (0.5 + 1.4 * t);
          c.drawCircle(
            p + Offset(math.cos(a) * d, math.sin(a) * d),
            4 * big * fade + 1,
            Paint()..color = col.withValues(alpha: fade),
          );
        }
      case 'slash':
        final rect = Rect.fromCircle(center: p, radius: r * 1.1);
        c.drawArc(
          rect,
          -2.2 + t * 0.8,
          1.9,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10 * big * fade + 2
            ..strokeCap = StrokeCap.round,
        );
        c.drawArc(
          rect.inflate(6),
          -2.1 + t * 0.8,
          1.7,
          false,
          Paint()
            ..color = col.withValues(alpha: fade * 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5 * big,
        );
      case 'spiral':
        final path = Path();
        for (var i = 0; i <= 40; i++) {
          final a = i / 40 * 4 * math.pi + t * 6;
          final rr = r * 0.1 + r * i / 40 * (0.6 + 0.6 * t);
          final q = p + Offset(math.cos(a) * rr, math.sin(a) * rr * 0.7);
          i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
        }
        c.drawPath(
          path,
          Paint()
            ..color = col.withValues(alpha: fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4 * big,
        );
      case 'hearts' ||
          'glow' ||
          'leaves' ||
          'stars' ||
          'bubbles' ||
          'rain' ||
          'sparks':
        // Self effects (heal / power-up): particles rising around the body.
        for (var i = 0; i < n; i++) {
          final u = (t * 1.3 + i / n) % 1;
          final q = p.translate(
            math.sin(i * 2.4 + t * 3) * r * 0.9,
            r * 0.6 - u * r * 2.2,
          );
          final a = (1 - u) * fade * 1.4;
          if (e.kind == 'hearts') {
            _heart(c, q, r * 0.16, col.withValues(alpha: a.clamp(0.0, 1.0)));
          } else {
            _star(c, q, r * 0.14, col.withValues(alpha: a.clamp(0.0, 1.0)));
          }
        }
        c.drawCircle(
          p,
          r * 1.2,
          Paint()
            ..shader = ui.Gradient.radial(p, r * 1.2, [
              col.withValues(alpha: 0.35 * fade),
              col.withValues(alpha: 0),
            ]),
        );
      case 'shield':
        c.drawCircle(
          p,
          r * (1.0 + 0.3 * t),
          Paint()
            ..color = const Color(0xFF66CCFF).withValues(alpha: 0.5 * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6,
        );
      default:
        c.drawCircle(
          p,
          r * (0.5 + t),
          Paint()..color = col.withValues(alpha: 0.5 * fade),
        );
    }
  }

  void _star(
    Canvas c,
    Offset o,
    double r,
    Color col, {
    int points = 5,
    double inner = 0.5,
  }) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / points;
      final rr = i.isEven ? r : r * inner;
      final q = o + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    path.close();
    c.drawPath(path, Paint()..color = col);
  }

  void _heart(Canvas c, Offset o, double r, Color col) {
    final p = Path()
      ..moveTo(o.dx, o.dy + r)
      ..cubicTo(
        o.dx - r * 2,
        o.dy - r * 0.6,
        o.dx - r * 0.6,
        o.dy - r * 1.8,
        o.dx,
        o.dy - r * 0.6,
      )
      ..cubicTo(
        o.dx + r * 0.6,
        o.dy - r * 1.8,
        o.dx + r * 2,
        o.dy - r * 0.6,
        o.dx,
        o.dy + r,
      );
    c.drawPath(p, Paint()..color = col);
  }

  void _zigzag(Canvas c, Offset a, Offset b, Color col, double width) {
    final path = Path()..moveTo(a.dx, a.dy);
    const n = 7;
    final d = b - a;
    final nrm = Offset(-d.dy, d.dx) / math.max(1, d.distance);
    for (var i = 1; i < n; i++) {
      final q = a + d * (i / n) + nrm * ((i.isEven ? 1 : -1) * 10.0);
      path.lineTo(q.dx, q.dy);
    }
    path.lineTo(b.dx, b.dy);
    c.drawPath(
      path,
      Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = width + 2
        ..strokeJoin = StrokeJoin.round,
    );
    c.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, width * 0.4),
    );
  }

  final _tp = TextPainter(
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  );

  void _text(
    Canvas c,
    String s,
    Offset center, {
    required double size,
    required Color fill,
    double alpha = 1,
  }) {
    final a = alpha.clamp(0.0, 1.0);
    TextStyle st(Paint? fg, Color? color) => TextStyle(
      fontFamily: 'ZenMaruGothic',
      fontSize: size,
      fontWeight: FontWeight.w900,
      foreground: fg,
      color: color,
      height: 1,
    );
    _tp.text = TextSpan(
      text: s,
      style: st(
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.16
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF2A2240).withValues(alpha: a),
        null,
      ),
    );
    _tp.layout();
    final o = center - Offset(_tp.width / 2, _tp.height / 2);
    _tp.paint(c, o);
    _tp.text = TextSpan(
      text: s,
      style: st(null, fill.withValues(alpha: a)),
    );
    _tp.layout();
    _tp.paint(c, o);
  }

  @override
  bool shouldRepaint(covariant StagePainter old) => true;
}
