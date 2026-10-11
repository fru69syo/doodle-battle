import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../puppet/puppet_look.dart';
import '../puppet/render/aura.dart';
import '../puppet/render/puppet_sprite.dart';
import 'stage_background.dart';
import 'stage_director.dart';
import 'stage_quality.dart';
import 'stage_theme.dart';
import 'stage_vfx.dart';

export 'stage_vfx.dart' show fxColour;

/// Draws one frame of the 2.5D stage: the theme's parallax background, a
/// perspective ground, depth-sorted props and fighters with soft shadows,
/// auras and status visuals, then the move effects. Ordinary Canvas drawing
/// (paths, gradients, `drawVertices`) that Skia-GLES2 and Impeller both
/// support.
class StagePainter extends CustomPainter {
  StagePainter({
    required this.director,
    required this.sprites,
    required this.background,
    required this.vfx,
    super.repaint,
    this.looks = const [PuppetLook(), PuppetLook()],
    this.quality = StageQuality.high,
  });

  final StageDirector director;
  final List<PuppetSprite> sprites;
  final StageBackground background;
  final StageVfx vfx;

  /// Per side: simple look / でんせつ aura.
  final List<PuppetLook> looks;
  final StageQuality quality;

  StageTheme get theme => background.theme;

  /// World height of a character (units).
  static const charHeight = 1.25;

  static const _props = <(double, double, int)>[
    // x, z, prop slot (index into the theme's prop list)
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
    final low = quality == StageQuality.low;
    background.paintFar(canvas, size, cam, director.time, low: low);
    background.paintGround(canvas, size, cam);
    // Depth-sorted drawables: props and fighters (far first).
    final items = <(double, void Function())>[];
    for (final (i, p) in _props.indexed) {
      if (low && i.isOdd) continue;
      final kind = theme.props[p.$3 % theme.props.length];
      items.add((p.$2, () => _prop(canvas, size, cam, p.$1, p.$2, kind)));
    }
    for (final f in director.fighters) {
      items.add((f.z, () => _fighter(canvas, size, cam, f)));
    }
    items.sort((a, b) => b.$1.compareTo(a.$1));
    for (final it in items) {
      it.$2();
    }
    vfx.particles = quality.particles;
    vfx.paint(canvas, size, cam, director.fx);
    background.paintAmbient(
      canvas,
      size,
      director.time,
      count: (18 * quality.particles).round(),
    );
    if (!low) {
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
  }

  void _prop(
    Canvas c,
    Size s,
    StageCamera cam,
    double x,
    double z,
    PropKind kind,
  ) {
    final (sx, sy, k) = cam.project(x, z, s.width, s.height);
    if (sx < -80 || sx > s.width + 80) return;
    final u = k * 0.12; // ~12 cm
    switch (kind) {
      case PropKind.flower:
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
      case PropKind.stone:
        c.drawOval(
          Rect.fromCenter(
            center: Offset(sx, sy - u * 0.6),
            width: u * 4,
            height: u * 2.2,
          ),
          Paint()
            ..color = theme.ambient == Ambient.snow
                ? const Color(0xFFDDE6F2)
                : const Color(0xFFB9B4AE),
        );
        c.drawOval(
          Rect.fromCenter(
            center: Offset(sx - u * 0.5, sy - u * 1.0),
            width: u * 1.6,
            height: u * 0.7,
          ),
          Paint()..color = const Color(0x55FFFFFF),
        );
      case PropKind.bush:
        final p = Paint()..color = theme.treeColor.withValues(alpha: 0.9);
        c.drawCircle(Offset(sx, sy - u * 2.5), u * 2.6, p);
        c.drawCircle(Offset(sx - u * 2.2, sy - u * 1.5), u * 1.9, p);
        c.drawCircle(Offset(sx + u * 2.2, sy - u * 1.6), u * 2.0, p);
      case PropKind.tuft:
        final p = Paint()
          ..color = Color.lerp(theme.ground, const Color(0xFF2F6B2A), 0.45)!
          ..strokeWidth = math.max(1.5, u * 0.35)
          ..strokeCap = StrokeCap.round;
        for (final d in [-1.0, -0.4, 0.3, 0.9]) {
          c.drawLine(
            Offset(sx + d * u, sy),
            Offset(sx + d * u * 1.8, sy - u * 2.4),
            p,
          );
        }
      case PropKind.shell:
        final p = Path()
          ..moveTo(sx - u * 1.2, sy)
          ..quadraticBezierTo(sx, sy - u * 2.4, sx + u * 1.2, sy)
          ..close();
        c.drawPath(p, Paint()..color = const Color(0xFFFFB7A8));
        c.drawLine(
          Offset(sx, sy),
          Offset(sx, sy - u * 1.4),
          Paint()
            ..color = const Color(0x88FFFFFF)
            ..strokeWidth = math.max(1, u * 0.2),
        );
      case PropKind.snowman:
        final p = Paint()..color = Colors.white;
        c.drawCircle(Offset(sx, sy - u * 1.2), u * 1.2, p);
        c.drawCircle(Offset(sx, sy - u * 3.0), u * 0.85, p);
        c.drawCircle(
          Offset(sx, sy - u * 3.0),
          u * 0.15,
          Paint()..color = const Color(0xFFFF8A3D),
        );
      case PropKind.candy:
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(sx, sy - u),
              width: u * 2.4,
              height: u * 1.4,
            ),
            Radius.circular(u * 0.7),
          ),
          Paint()
            ..color = (x > 0
                ? const Color(0xFFFF8FC7)
                : const Color(0xFF8FD8FF)),
        );
        c.drawCircle(
          Offset(sx - u * 0.4, sy - u * 1.2),
          u * 0.25,
          Paint()..color = Colors.white70,
        );
      case PropKind.cactus:
        final p = Paint()
          ..color = const Color(0xFF5BAA55)
          ..strokeWidth = u * 0.9
          ..strokeCap = StrokeCap.round;
        c.drawLine(Offset(sx, sy), Offset(sx, sy - u * 3.2), p);
        c.drawLine(Offset(sx, sy - u * 1.6), Offset(sx + u, sy - u * 1.6), p);
        c.drawLine(
          Offset(sx + u, sy - u * 1.6),
          Offset(sx + u, sy - u * 2.4),
          p,
        );
      case PropKind.mushroom:
        c.drawRect(
          Rect.fromCenter(
            center: Offset(sx, sy - u * 0.6),
            width: u * 0.8,
            height: u * 1.2,
          ),
          Paint()..color = const Color(0xFFFFF3DD),
        );
        c.drawArc(
          Rect.fromCenter(
            center: Offset(sx, sy - u * 1.2),
            width: u * 2.6,
            height: u * 2.2,
          ),
          math.pi,
          math.pi,
          true,
          Paint()..color = const Color(0xFFE5533D),
        );
        c.drawCircle(
          Offset(sx - u * 0.5, sy - u * 1.6),
          u * 0.22,
          Paint()..color = Colors.white,
        );
      case PropKind.star:
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final a = -math.pi / 2 + i * math.pi / 5;
          final rr = i.isEven ? u * 1.3 : u * 0.6;
          final q = Offset(
            sx + math.cos(a) * rr,
            sy - u * 1.4 + math.sin(a) * rr,
          );
          i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
        }
        c.drawPath(path..close(), Paint()..color = const Color(0xFFFFE066));
    }
  }

  // --- fighters ------------------------------------------------------------

  void _fighter(Canvas c, Size s, StageCamera cam, StageFighter f) {
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
    if (looks[f.side].legend) {
      paintLegendAura(
        c,
        top,
        k * charHeight * 0.68,
        director.time + f.side,
        sparkles: quality.particles >= 1 ? 6 : 3,
      );
    }
    if (f.charging || pose.glow > 0) {
      final g = math.max(pose.glow, f.charging ? 0.8 : 0);
      paintAura(
        c,
        top,
        k * charHeight * 0.7,
        const Color(0xFF8FE3FF),
        0.55 * g,
      );
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
    _statusIcons(c, f, top.translate(0, -k * charHeight * 0.62), k);
  }

  /// Small round badges over the head (ねばねば / ビリビリ / まもり).
  void _statusIcons(Canvas c, StageFighter f, Offset at, double k) {
    final icons = <(IconData, Color)>[
      if (f.poisoned) (Icons.water_drop, const Color(0xFFB45CFF)),
      if (f.paralyzed) (Icons.bolt, const Color(0xFFE6B800)),
      if (f.shield > 0) (Icons.shield, const Color(0xFF3AA0E0)),
    ];
    if (icons.isEmpty) return;
    final r = math.max(9.0, k * 0.07);
    var x = at.dx - (icons.length - 1) * r * 1.2;
    for (final (icon, col) in icons) {
      final o = Offset(x, at.dy);
      c.drawCircle(o, r + 2, Paint()..color = Colors.white);
      c.drawCircle(o, r, Paint()..color = col);
      _iconTp.text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: r * 1.3,
          color: Colors.white,
        ),
      );
      _iconTp.layout();
      _iconTp.paint(c, o - Offset(_iconTp.width / 2, _iconTp.height / 2));
      x += r * 2.4;
    }
  }

  final _iconTp = TextPainter(textDirection: TextDirection.ltr);

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

  @override
  bool shouldRepaint(covariant StagePainter old) => true;
}
