import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'stroke_drawing.dart';

/// Paints strokes with kid-friendly brushes (no pressure):
/// * crayon — waxy line with paper grain showing through,
/// * marker — solid round line,
/// * brush — wide, soft-edged, slightly transparent paint,
/// * eraser — clears ink (never the paper).
///
/// Strokes are drawn into their own layer so the eraser only removes ink.
class StrokeRenderer {
  const StrokeRenderer();

  void paint(Canvas c, List<Stroke> strokes, {Stroke? live}) {
    c.saveLayer(null, Paint());
    for (final (i, s) in strokes.indexed) {
      _stroke(c, s, i);
    }
    if (live != null) _stroke(c, live, strokes.length);
    c.restore();
  }

  Path _path(Stroke s) {
    final p = Path();
    final xy = s.xy;
    if (xy.length < 2) return p;
    p.moveTo(xy[0], xy[1]);
    if (xy.length == 2) {
      p.lineTo(xy[0] + 0.01, xy[1]);
      return p;
    }
    // Quadratic smoothing through midpoints.
    for (var i = 2; i < xy.length - 2; i += 2) {
      final mx = (xy[i] + xy[i + 2]) / 2, my = (xy[i + 1] + xy[i + 3]) / 2;
      p.quadraticBezierTo(xy[i], xy[i + 1], mx, my);
    }
    p.lineTo(xy[xy.length - 2], xy[xy.length - 1]);
    return p;
  }

  void _stroke(Canvas c, Stroke s, int index) {
    if (s.xy.isEmpty) return;
    final path = _path(s);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s.width
      ..isAntiAlias = true;
    final col = Color(s.color);
    switch (s.tool) {
      case DrawTool.eraser:
        c.drawPath(path, base..blendMode = BlendMode.clear);
      case DrawTool.marker:
        c.drawPath(path, base..color = col);
      case DrawTool.brush:
        c.drawPath(
          path,
          base
            ..color = col.withValues(alpha: 0.85)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      case DrawTool.crayon:
        c.drawPath(path, base..color = col);
        _grain(c, s, index);
    }
  }

  /// Wax grain: small paper-coloured specks punched out along the stroke
  /// (deterministic per stroke, so redraws do not shimmer).
  void _grain(Canvas c, Stroke s, int index) {
    final rnd = math.Random(index * 7919 + s.length);
    final xy = s.xy;
    final hw = s.width / 2;
    final pts = <double>[];
    for (var i = 0; i < xy.length; i += 2) {
      // Interpolate so long segments get grain too.
      final nx = i + 2 < xy.length ? xy[i + 2] : xy[i];
      final ny = i + 3 < xy.length ? xy[i + 3] : xy[i + 1];
      final segs = math.max(
        1,
        (math.sqrt(
                  (nx - xy[i]) * (nx - xy[i]) +
                      (ny - xy[i + 1]) * (ny - xy[i + 1]),
                ) /
                4)
            .ceil(),
      );
      for (var k = 0; k < segs; k++) {
        final t = k / segs;
        final cx = xy[i] + (nx - xy[i]) * t,
            cy = xy[i + 1] + (ny - xy[i + 1]) * t;
        for (var j = 0; j < 3; j++) {
          final a = rnd.nextDouble() * 2 * math.pi;
          final r = math.sqrt(rnd.nextDouble()) * hw;
          pts
            ..add(cx + math.cos(a) * r)
            ..add(cy + math.sin(a) * r);
        }
      }
    }
    if (pts.isEmpty) return;
    c.drawRawPoints(
      ui.PointMode.points,
      Float32List.fromList(pts),
      Paint()
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0x8C000000)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }
}

/// Cream drawing paper with faint fibres (deterministic, cheap).
class PaperPainter extends CustomPainter {
  const PaperPainter();

  static const paper = Color(0xFFFFFCF2);

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = paper);
    final rnd = math.Random(17);
    final fibre = Paint()
      ..color = const Color(0x0F8A6A3B)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final n = (size.width * size.height / 900).round().clamp(50, 900);
    for (var i = 0; i < n; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final a = rnd.nextDouble() * math.pi;
      final l = 3 + rnd.nextDouble() * 7;
      c.drawLine(
        Offset(x, y),
        Offset(x + math.cos(a) * l, y + math.sin(a) * l),
        fibre,
      );
    }
  }

  @override
  bool shouldRepaint(PaperPainter oldDelegate) => false;
}

/// Renders [d] to PNG bytes at [longest] px on a plain white background
/// (what the analysis pipeline reads; the paper texture is only on
/// screen, so the colour analysis sees the child's colours, not ours).
Future<Uint8List> renderDrawingPng(
  StrokeDrawing d, {
  int longest = 1024,
}) async {
  final k = longest / StrokeDrawing.height;
  final w = (StrokeDrawing.size * k).round();
  final h = (StrokeDrawing.height * k).round();
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = Colors.white,
  );
  c.scale(k);
  const StrokeRenderer().paint(c, d.strokes);
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  pic.dispose();
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bytes!.buffer.asUint8List();
}
