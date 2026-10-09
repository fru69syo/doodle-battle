import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../glb/standee_glb.dart';

/// The paper standee drawn in Flutter for かんたん AR: aura behind, the paper
/// sprite with the same idle hop as the GLB, and twinkling sparkles.
///
/// Its size is the sprite plus [StandeeGlb.effectMarginPx] on the left, right
/// and top, times [pixelScale]; the bottom-centre is the character's feet.
class StandeeSprite extends StatefulWidget {
  const StandeeSprite({
    super.key,
    required this.standee,
    required this.pixelScale,
    this.sparkles = false,
    this.animate = true,
  });

  final StandeeGlb standee;

  /// Logical pixels per sprite texture pixel.
  final double pixelScale;
  final bool sparkles;
  final bool animate;

  static Size layerSize(StandeeGlb s, double pixelScale) {
    final m = s.effectMarginPx;
    return Size(
      (s.spriteWidth + 2 * m) * pixelScale,
      (s.spriteHeight + m) * pixelScale,
    );
  }

  @override
  State<StandeeSprite> createState() => _StandeeSpriteState();
}

class _StandeeSpriteState extends State<StandeeSprite>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(StandeeSprite old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.standee;
    final ps = widget.pixelScale;
    final m = s.effectMarginPx * ps;
    final w = s.spriteWidth * ps;
    final h = s.spriteHeight * ps;
    final size = StandeeSprite.layerSize(s, ps);

    return SizedBox.fromSize(
      size: size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final p = _c.value;
          final hop = idleHop(p);
          final squash = idleSquash(p);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (s.auraPng != null)
                Positioned.fill(
                  child: Transform.scale(
                    alignment: Alignment.bottomCenter,
                    scale: 1 + 0.05 * math.sin(2 * math.pi * p),
                    child: Transform.translate(
                      offset: Offset(0, -hop * h * 0.06),
                      child: Image.memory(
                        s.auraPng!,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              // Soft ground shadow.
              Positioned(
                left: m + w * 0.5 - w * 0.62 * (1 - 0.18 * hop),
                width: w * 1.24 * (1 - 0.18 * hop),
                bottom: -h * 0.04,
                height: h * 0.08,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [Color(0x55000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: m,
                top: m,
                width: w,
                height: h,
                child: Transform.translate(
                  offset: Offset(0, -hop * h * 0.06),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.diagonal3Values(squash[0], squash[1], 1),
                    child: Image.memory(
                      s.spritePng,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
              if (widget.sparkles)
                for (final (i, sp) in standeeSparkleLayout.indexed)
                  _sparkle(
                    center: Offset(
                      m + w / 2 + sp.$1 * w / 2,
                      m + h - sp.$2 * h,
                    ),
                    size: h * 0.14,
                    scale: sparkleScale(p + i / standeeSparkleLayout.length),
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _sparkle({
    required Offset center,
    required double size,
    required double scale,
  }) {
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: Transform.scale(
        scale: scale,
        child: const CustomPaint(painter: SparklePainter()),
      ),
    );
  }
}

/// 4-point star.
class SparklePainter extends CustomPainter {
  const SparklePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFE680)
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2),
    );
    canvas.drawCircle(c, r * 0.18, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(SparklePainter oldDelegate) => false;
}
