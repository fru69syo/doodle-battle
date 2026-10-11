import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'stage_camera.dart';
import 'stage_theme.dart';

/// Parallax background and perspective ground of a [StageTheme].
///
/// The far layers (sky, hills, tree line) do not change shape when the
/// camera moves, only position, so each is recorded once per screen size
/// into a `Picture` and replayed with a translation (parallax: clouds 0.05,
/// far hills 0.12, near hills 0.25, trees 0.4). The ground and the props
/// use the real ground-plane projection.
class StageBackground {
  StageBackground(this.theme);

  final StageTheme theme;
  Size? _size;
  ui.Picture? _sky, _far, _near, _trees;

  /// Strip margin (px) recorded on each side for parallax shifts.
  static const _margin = 420.0;

  void dispose() {
    for (final p in [_sky, _far, _near, _trees]) {
      p?.dispose();
    }
    _sky = _far = _near = _trees = null;
  }

  /// Horizon-relative layers recorded at y = 0 = horizon.
  void _record(Size s) {
    dispose();
    _size = s;
    final hz = s.height * StageCamera.horizonFrac;
    ui.Picture rec(void Function(Canvas c) f) {
      final r = ui.PictureRecorder();
      f(Canvas(r));
      return r.endRecording();
    }

    _sky = rec((c) => _paintSky(c, s, hz));
    _far = rec((c) => _hills(c, s, hz, theme.farHill, 0.55, 3, 0.37));
    _near = rec((c) {
      if (theme.water) {
        _sea(c, s, hz);
      } else {
        _hills(c, s, hz, theme.nearHill, 0.32, 5, 0.53);
      }
    });
    _trees = rec((c) => _treeLine(c, s));
  }

  /// Sky, sun / moon, clouds, hills, trees (behind everything).
  void paintFar(
    Canvas c,
    Size s,
    StageCamera cam,
    double time, {
    bool low = false,
  }) {
    if (_size != s) _record(s);
    final hz = cam.horizon(s.height);
    final f = cam.focal(s.width, s.height);
    // The sky picture is drawn so its horizon line lands on hz.
    c.save();
    c.translate(0, hz - s.height * StageCamera.horizonFrac);
    c.drawPicture(_sky!);
    c.restore();
    if (!low) {
      for (var i = 0; i < 4; i++) {
        final x =
            ((i * 0.31 + time * 0.01) % 1.3 - 0.15) * s.width -
            cam.x * f * 0.05;
        _cloud(c, Offset(x, hz * (0.18 + 0.13 * (i % 3))), 26.0 + 8 * (i % 2));
      }
    }
    for (final (pic, k) in [(_far!, 0.12), (_near!, 0.25), (_trees!, 0.4)]) {
      c.save();
      c.translate((-cam.x * f * k).clamp(-_margin, _margin), hz);
      c.drawPicture(pic);
      c.restore();
    }
  }

  void _paintSky(Canvas c, Size s, double hz) {
    c.drawRect(
      Rect.fromLTWH(-_margin, -hz - 40, s.width + 2 * _margin, 2 * hz + 80),
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, -40), Offset(0, hz), [
          theme.skyTop,
          theme.skyBottom,
        ]),
    );
    final sun = Offset(s.width * 0.82, hz * 0.32);
    if (theme.moon) {
      final rnd = math.Random(4);
      final star = Paint()..color = const Color(0xCCFFFFFF);
      for (var i = 0; i < 40; i++) {
        c.drawCircle(
          Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * hz * 0.9),
          rnd.nextDouble() * 1.6 + 0.6,
          star,
        );
      }
      c.drawCircle(sun, 26, Paint()..color = theme.sun);
      c.drawCircle(sun.translate(10, -6), 22, Paint()..color = theme.skyTop);
    } else {
      c.drawCircle(sun, 30, Paint()..color = theme.sun);
      c.drawCircle(sun, 44, Paint()..color = theme.sun.withValues(alpha: 0.2));
    }
  }

  void _cloud(Canvas c, Offset o, double r) {
    final p = Paint()
      ..color = (theme.moon ? const Color(0xFF8C95C8) : Colors.white)
          .withValues(alpha: 0.85);
    c.drawCircle(o, r, p);
    c.drawCircle(o.translate(r * 0.9, 4), r * 0.75, p);
    c.drawCircle(o.translate(-r * 0.9, 6), r * 0.65, p);
  }

  /// Hills recorded around y = 0 (the horizon).
  void _hills(
    Canvas c,
    Size s,
    double hz,
    Color col,
    double hFrac,
    int n,
    double phase,
  ) {
    final path = Path()..moveTo(-_margin, 2);
    final period = s.width * 1.6 / n;
    for (double x = -_margin; x <= s.width + _margin; x += 8) {
      final u = x / period;
      final y =
          -hFrac *
          hz *
          0.5 *
          (0.55 + 0.45 * math.sin(u * math.pi) * math.sin(u * phase + 1));
      path.lineTo(x, y);
    }
    path
      ..lineTo(s.width + _margin, 2)
      ..close();
    c.drawPath(path, Paint()..color = col);
    c.drawPath(
      path,
      Paint()
        ..color = theme.hillOutline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _sea(Canvas c, Size s, double hz) {
    final r = Rect.fromLTWH(
      -_margin,
      -hz * 0.12,
      s.width + 2 * _margin,
      hz * 0.12 + 3,
    );
    c.drawRect(r, Paint()..color = theme.nearHill);
    final wave = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var row = 0; row < 3; row++) {
      final y = -hz * 0.1 + row * hz * 0.035;
      final path = Path()..moveTo(-_margin, y);
      for (double x = -_margin; x <= s.width + _margin; x += 12) {
        path.lineTo(x, y + 2 * math.sin(x / 14 + row));
      }
      c.drawPath(path, wave);
    }
  }

  void _treeLine(Canvas c, Size s) {
    if (theme.trees == TreeKind.none) return;
    for (var i = -4; i < 11; i++) {
      final x = i * s.width / 6 + (i.isEven ? 10 : -6);
      _tree(c, Offset(x, 4), 26 + 6.0 * ((i * 7) % 3), i);
    }
  }

  void _tree(Canvas c, Offset base, double r, int i) {
    final trunk = Paint()..color = const Color(0xFF8B5A2B);
    final leaf = Paint()..color = theme.treeColor;
    switch (theme.trees) {
      case TreeKind.round:
        c.drawRect(
          Rect.fromCenter(
            center: base.translate(0, -r * 0.4),
            width: r * 0.25,
            height: r * 0.8,
          ),
          trunk,
        );
        c.drawCircle(base.translate(0, -r * 1.05), r * 0.62, leaf);
        c.drawCircle(base.translate(-r * 0.35, -r * 0.8), r * 0.45, leaf);
        c.drawCircle(base.translate(r * 0.35, -r * 0.8), r * 0.45, leaf);
      case TreeKind.pine:
        c.drawRect(
          Rect.fromCenter(
            center: base.translate(0, -r * 0.2),
            width: r * 0.2,
            height: r * 0.4,
          ),
          trunk,
        );
        for (var k = 0; k < 3; k++) {
          final y = -r * (0.35 + 0.42 * k);
          final hw = r * (0.6 - 0.15 * k);
          c.drawPath(
            Path()
              ..moveTo(base.dx - hw, base.dy + y)
              ..lineTo(base.dx + hw, base.dy + y)
              ..lineTo(base.dx, base.dy + y - r * 0.7)
              ..close(),
            leaf,
          );
        }
        if (theme.ambient == Ambient.snow) {
          c.drawCircle(
            base.translate(0, -r * 1.75),
            r * 0.14,
            Paint()..color = Colors.white,
          );
        }
      case TreeKind.palm:
        final top = base.translate(r * 0.25, -r * 1.5);
        c.drawLine(
          base,
          top,
          trunk
            ..strokeWidth = r * 0.16
            ..strokeCap = StrokeCap.round,
        );
        for (var k = 0; k < 5; k++) {
          final a = -math.pi / 2 + (k - 2) * 0.6;
          final end = top + Offset(math.cos(a), math.sin(a) + 0.5) * r * 0.75;
          c.drawLine(
            top,
            end,
            Paint()
              ..color = theme.treeColor
              ..strokeWidth = r * 0.18
              ..strokeCap = StrokeCap.round,
          );
        }
      case TreeKind.lollipop:
        c.drawLine(
          base,
          base.translate(0, -r * 1.1),
          Paint()
            ..color = Colors.white
            ..strokeWidth = r * 0.12,
        );
        final colors = [
          theme.treeColor,
          const Color(0xFF7BD3F7),
          const Color(0xFFFFD54A),
        ];
        c.drawCircle(
          base.translate(0, -r * 1.3),
          r * 0.45,
          Paint()..color = colors[i.abs() % 3],
        );
        c.drawCircle(
          base.translate(0, -r * 1.3),
          r * 0.25,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.08,
        );
      case TreeKind.cactus:
        if (i.isOdd) return;
        final p = Paint()
          ..color = theme.treeColor
          ..strokeWidth = r * 0.28
          ..strokeCap = StrokeCap.round;
        c.drawLine(base, base.translate(0, -r * 1.3), p);
        c.drawLine(
          base.translate(0, -r * 0.6),
          base.translate(r * 0.4, -r * 0.6),
          p,
        );
        c.drawLine(
          base.translate(r * 0.4, -r * 0.6),
          base.translate(r * 0.4, -r * 0.95),
          p,
        );
      case TreeKind.none:
        break;
    }
  }

  /// Ground plane with mowed stripes and the arena ellipse.
  void paintGround(Canvas c, Size s, StageCamera cam) {
    final hz = cam.horizon(s.height);
    c.drawRect(
      Rect.fromLTWH(0, hz, s.width, s.height - hz),
      Paint()..color = theme.ground,
    );
    final band = Paint()..color = theme.stripe;
    for (var z = -1.8; z < 14; z += 1.2) {
      final (_, y0, _) = cam.project(0, z, s.width, s.height);
      final (_, y1, _) = cam.project(0, z + 0.6, s.width, s.height);
      if (y0 < hz) break;
      c.drawRect(Rect.fromLTRB(0, y1, s.width, y0), band);
    }
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
    c.drawPath(ring, Paint()..color = theme.arena);
    c.drawPath(
      ring,
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  /// Ambient particles over the whole stage (snow, petals, bubbles...).
  void paintAmbient(Canvas c, Size s, double time, {int count = 18}) {
    if (theme.ambient == Ambient.none || count <= 0) return;
    final p = Paint();
    for (var i = 0; i < count; i++) {
      final seed = i * 0.6180339;
      final x0 = (seed % 1) * s.width;
      final speed = 0.04 + 0.05 * ((i * 7) % 5) / 5;
      var u = (time * speed + seed * 3.1) % 1.0;
      switch (theme.ambient) {
        case Ambient.snow:
          final q = Offset(x0 + 14 * math.sin(time + i), u * s.height);
          c.drawCircle(q, 2.5 + (i % 3), p..color = const Color(0xDDFFFFFF));
        case Ambient.petals:
          final q = Offset(x0 + 30 * math.sin(time * 0.7 + i), u * s.height);
          c.save();
          c.translate(q.dx, q.dy);
          c.rotate(time + i);
          c.drawOval(
            Rect.fromCenter(center: Offset.zero, width: 7, height: 4),
            p..color = const Color(0xCCFF9EC7),
          );
          c.restore();
        case Ambient.bubbles:
          u = 1 - u;
          final q = Offset(x0 + 10 * math.sin(time * 2 + i), u * s.height);
          c.drawCircle(
            q,
            3 + (i % 4).toDouble(),
            p
              ..color = const Color(0x88FFFFFF)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
          p.style = PaintingStyle.fill;
        case Ambient.stars:
          final tw = 0.5 + 0.5 * math.sin(time * 3 + i * 1.7);
          final q = Offset(x0, (seed * 7 % 1) * s.height * 0.45);
          c.drawCircle(
            q,
            1.5 + 1.5 * tw,
            p..color = Color.fromRGBO(255, 245, 190, 0.3 + 0.6 * tw),
          );
        case Ambient.embers:
          u = 1 - u;
          final q = Offset(x0 + 8 * math.sin(time * 3 + i), u * s.height);
          c.drawCircle(
            q,
            2 + (i % 2).toDouble(),
            p..color = const Color(0xCCFF8A3D),
          );
        case Ambient.none:
          break;
      }
    }
  }
}
