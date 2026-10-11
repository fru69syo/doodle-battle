import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Gold でんせつ colour (every Lv50+ character).
const kLegendGold = Color(0xFFFFD54A);

/// Soft radial glow.
void paintAura(Canvas c, Offset center, double r, Color col, double alpha) {
  if (alpha <= 0 || r <= 0) return;
  c.drawCircle(
    center,
    r,
    Paint()
      ..shader = ui.Gradient.radial(center, r, [
        col.withValues(alpha: alpha.clamp(0.0, 1.0)),
        col.withValues(alpha: 0),
      ]),
  );
}

/// The でんせつ aura: a pulsing gold glow with a few rising sparkles.
/// [r] is about the character's half height; [t] is time in seconds.
void paintLegendAura(
  Canvas c,
  Offset center,
  double r,
  double t, {
  int sparkles = 6,
}) {
  paintAura(c, center, r * 1.15, kLegendGold, 0.38 + 0.1 * math.sin(t * 4));
  final p = Paint()..color = const Color(0xFFFFF3B0);
  for (var i = 0; i < sparkles; i++) {
    final u = (t * 0.45 + i / sparkles) % 1.0;
    final a = i * 2.39996;
    final q = center.translate(math.cos(a) * r * 0.75, r * 0.7 - u * r * 1.7);
    final s = r * 0.06 * (1 - u) + 1.2;
    p.color = const Color(0xFFFFF3B0).withValues(alpha: (1 - u) * 0.9);
    final path = Path()
      ..moveTo(q.dx, q.dy - s * 2)
      ..lineTo(q.dx + s * 0.5, q.dy - s * 0.5)
      ..lineTo(q.dx + s * 2, q.dy)
      ..lineTo(q.dx + s * 0.5, q.dy + s * 0.5)
      ..lineTo(q.dx, q.dy + s * 2)
      ..lineTo(q.dx - s * 0.5, q.dy + s * 0.5)
      ..lineTo(q.dx - s * 2, q.dy)
      ..lineTo(q.dx - s * 0.5, q.dy - s * 0.5)
      ..close();
    c.drawPath(path, p);
  }
}
