import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'stage_director.dart';

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
  'grey' => const Color(0xFFC9C9D6),
  _ => const Color(0xFFFF7AE0), // rainbow: pink base, particles vary
};

const _rainbow = [
  Color(0xFFFF4D4D),
  Color(0xFFFF9A2E),
  Color(0xFFFFD83A),
  Color(0xFF4CD964),
  Color(0xFF4A7DFF),
  Color(0xFFB45CFF),
];

/// Draws the director's effect cues: the 15 move effects × 11 colours,
/// damage / heal numbers, effectiveness, crit, status and K.O. texts.
/// [particles] scales particle counts (adaptive quality).
class StageVfx {
  StageVfx({this.particles = 1});

  double particles;

  /// Drawn move effects (docs/LOOP.md): a child's own drawing replaces the
  /// generic effect of an element / special move. Keyed by side; drawn
  /// centred, flying for ranged moves and popping on impact.
  final drawn = <int, ui.Image>{};

  /// Colour of particle [i] (rainbow cycles).
  Color _pc(Fx e, int i, Color base) =>
      e.colour == 'rainbow' ? _rainbow[i % _rainbow.length] : base;

  void paint(Canvas c, Size s, StageCamera cam, List<Fx> fx) {
    _effects(c, s, cam, fx);
  }

  // --- effects -------------------------------------------------------------

  void _effects(Canvas c, Size s, StageCamera cam, List<Fx> list) {
    for (final e in list) {
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
                            : (e.colour == 'grey'
                                  ? const Color(0xFFD0D6E6)
                                  : Colors.white))),
            alpha: t < 0.75 ? 1 : (1 - t) * 4,
          );
        case 'miss' ||
            'crit' ||
            'status' ||
            'up' ||
            'down' ||
            'ko' ||
            'strong' ||
            'weak':
          final pop = t < 0.15 ? 0.6 + t * 2.7 : 1.0;
          _text(
            c,
            e.text ?? '',
            p.translate(0, -t * k * 0.15),
            size: (e.kind == 'ko' ? 64 : (e.kind == 'strong' ? 30 : 24)) * pop,
            fill: switch (e.kind) {
              'crit' => const Color(0xFFFFB13B),
              'strong' => const Color(0xFFFFE14D),
              'weak' => const Color(0xFFB8C6E0),
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
    final n = math.max(
      3,
      (8 * big * e.scale.clamp(0.5, 1.4) * particles).round(),
    );
    final img = e.drawn ? drawn[e.side] : null;
    // Projectiles fly from (x, z) to (tx, tz).
    if (e.tx != null) {
      final (tx, ty, tk) = cam.project(e.tx!, e.tz!, s.width, s.height);
      final to = Offset(tx, ty - 0.6 * tk);
      final head = Offset.lerp(p, to, Curves.easeIn.transform(t))!;
      if (img != null) {
        _image(
          c,
          img,
          head,
          r * 1.6 * (0.7 + 0.5 * t),
          flip: to.dx < p.dx,
          wobble: t * 8,
        );
        return;
      }
      switch (e.kind) {
        case 'beam':
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
        case 'wave':
          final d = to - p;
          final ang = math.atan2(d.dy, d.dx);
          for (var i = 0; i < 3; i++) {
            final q = Offset.lerp(p, to, (t * 1.1 - i * 0.12).clamp(0.0, 1.0))!;
            c.drawArc(
              Rect.fromCircle(center: q, radius: r * (0.5 + 0.15 * i)),
              ang - 0.9,
              1.8,
              false,
              Paint()
                ..color = _pc(e, i, col).withValues(alpha: 0.9 - 0.2 * i)
                ..style = PaintingStyle.stroke
                ..strokeWidth = k * 0.06 * big
                ..strokeCap = StrokeCap.round,
            );
          }
        case 'sparks':
          _zigzag(c, p, head, col, k * 0.05 * big);
        case 'rain' ||
            'bubbles' ||
            'leaves' ||
            'stars' ||
            'hearts' ||
            'slash' ||
            'punch':
          for (var i = 0; i < n; i++) {
            final q = Offset.lerp(p, to, (t * 1.2 - i * 0.04).clamp(0.0, 1.0))!;
            final o = q.translate(
              math.sin(i * 2.1) * r * 0.3,
              math.cos(i * 1.7) * r * 0.3,
            );
            _particle(c, e.kind, o, r * 0.2, _pc(e, i, col), 1, i + t * 6);
          }
        case 'spiral':
          final q = head;
          final path = Path();
          for (var i = 0; i <= 24; i++) {
            final a = i / 24 * 4 * math.pi + t * 12;
            final rr = r * 0.05 + r * 0.45 * i / 24;
            final pt = q + Offset(math.cos(a) * rr, math.sin(a) * rr);
            i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
          }
          c.drawPath(
            path,
            Paint()
              ..color = col
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3 * big,
          );
        default: // orb, burst, glow, shield...
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
    if (img != null) {
      // A drawn effect pops on impact / rises around the user.
      final grow = t < 0.6 ? 0.7 + 0.5 * t / 0.6 : 1.0 + 0.9 * (t - 0.6) / 0.4;
      c.saveLayer(
        Rect.fromCircle(center: p, radius: r * 3),
        Paint()..color = Color.fromRGBO(0, 0, 0, fade),
      );
      _image(c, img, p, r * 1.4 * grow, wobble: t * 10);
      c.restore();
      return;
    }
    switch (e.kind) {
      case 'punch' || 'burst' || 'orb':
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
            Paint()..color = _pc(e, i, col).withValues(alpha: fade),
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
      case 'beam' || 'wave':
        // Physical hit with a beam / wave look: expanding rings.
        for (var i = 0; i < 3; i++) {
          final u = (t * 1.3 - i * 0.15).clamp(0.0, 1.0);
          c.drawCircle(
            p,
            r * (0.3 + 1.2 * u),
            Paint()
              ..color = _pc(e, i, col).withValues(alpha: (1 - u) * 0.9)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5 * big * (1 - u) + 1,
          );
        }
      case 'hearts' ||
          'glow' ||
          'leaves' ||
          'stars' ||
          'bubbles' ||
          'rain' ||
          'sparks':
        // Particles rising (self moves) or bursting (a hit).
        for (var i = 0; i < n; i++) {
          final u = (t * 1.3 + i / n) % 1;
          final fall = e.kind == 'rain';
          final q = p.translate(
            math.sin(i * 2.4 + t * 3) * r * 0.9,
            fall ? -r * 1.6 + u * r * 2.2 : r * 0.6 - u * r * 2.2,
          );
          final a = ((1 - u) * fade * 1.4).clamp(0.0, 1.0);
          _particle(c, e.kind, q, r * 0.16, _pc(e, i, col), a, i + t * 4);
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
        for (var i = 0; i < 6; i++) {
          final a = i / 6 * 2 * math.pi + t * 2;
          c.drawCircle(
            p + Offset(math.cos(a), math.sin(a)) * r * (1.0 + 0.3 * t),
            3,
            Paint()..color = Colors.white.withValues(alpha: fade),
          );
        }
      default:
        c.drawCircle(
          p,
          r * (0.5 + t),
          Paint()..color = col.withValues(alpha: 0.5 * fade),
        );
    }
  }

  /// One particle in the shape of [kind].
  void _particle(
    Canvas c,
    String kind,
    Offset o,
    double r,
    Color col,
    double a,
    double spin,
  ) {
    final cc = col.withValues(alpha: a.clamp(0.0, 1.0) * col.a);
    switch (kind) {
      case 'hearts':
        _heart(c, o, r, cc);
      case 'leaves':
        c.save();
        c.translate(o.dx, o.dy);
        c.rotate(spin);
        c.drawOval(
          Rect.fromCenter(center: Offset.zero, width: r * 2.2, height: r * 1.1),
          Paint()..color = cc,
        );
        c.restore();
      case 'bubbles':
        c.drawCircle(
          o,
          r,
          Paint()
            ..color = cc
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, r * 0.25),
        );
        c.drawCircle(
          o.translate(-r * 0.35, -r * 0.35),
          r * 0.25,
          Paint()..color = Colors.white.withValues(alpha: a),
        );
      case 'rain':
        c.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - r * 1.4)
            ..quadraticBezierTo(o.dx + r, o.dy + r * 0.3, o.dx, o.dy + r * 0.7)
            ..quadraticBezierTo(o.dx - r, o.dy + r * 0.3, o.dx, o.dy - r * 1.4),
          Paint()..color = cc,
        );
      case 'sparks':
        _zigzag(c, o.translate(-r, -r), o.translate(r, r), cc, 1.5);
      case 'glow':
        c.drawCircle(o, r * 0.8, Paint()..color = cc);
      default:
        _star(c, o, r * 1.2, cc);
    }
  }

  void _image(
    Canvas c,
    ui.Image img,
    Offset center,
    double r, {
    bool flip = false,
    double wobble = 0,
  }) {
    final w = img.width.toDouble(), h = img.height.toDouble();
    final k = 2 * r / math.max(w, h);
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(0.12 * math.sin(wobble));
    c.scale(flip ? -k : k, k);
    c.drawImage(
      img,
      Offset(-w / 2, -h / 2),
      Paint()..filterQuality = FilterQuality.medium,
    );
    c.restore();
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
}
