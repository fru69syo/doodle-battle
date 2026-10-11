import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:doodle_battle/features/draw_canvas/canvas_analysis.dart';
import 'package:doodle_battle/features/draw_canvas/draw_canvas_controller.dart';
import 'package:doodle_battle/features/draw_canvas/draw_canvas_screen.dart';
import 'package:doodle_battle/features/draw_canvas/stroke_drawing.dart';
import 'package:doodle_battle/features/draw_canvas/stroke_painter.dart';
import 'package:doodle_battle/features/puppet/puppet_builder.dart';
import 'package:doodle_battle/features/puppet/rig/character_rig.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../puppet/render_util.dart';

/// A kid-like drawing made of strokes: round head, body outline, arms
/// with hands on the hips (touching the body), legs, coloured in.
StrokeDrawing kidDrawing({int seed = 1}) {
  final r = math.Random(seed);
  double j() => (r.nextDouble() - 0.5) * 6;
  Stroke line(DrawTool t, int c, List<(double, double)> pts) {
    final s = Stroke(t, c, null);
    for (var i = 0; i < pts.length - 1; i++) {
      for (var k = 0; k < 12; k++) {
        final u = k / 12;
        s.add(
          pts[i].$1 + (pts[i + 1].$1 - pts[i].$1) * u + j(),
          pts[i].$2 + (pts[i + 1].$2 - pts[i].$2) * u + j(),
        );
      }
    }
    s.add(pts.last.$1, pts.last.$2);
    return s;
  }

  List<(double, double)> ring(double cx, double cy, double rx, double ry) => [
    for (var i = 0; i <= 24; i++)
      (
        cx + rx * math.cos(i / 24 * 2 * math.pi),
        cy + ry * math.sin(i / 24 * 2 * math.pi),
      ),
  ];

  return StrokeDrawing(
    strokes: [
      line(DrawTool.crayon, kCanvasColors[0], ring(500, 260, 120, 115)),
      line(DrawTool.brush, kCanvasColors[4], ring(500, 260, 60, 55)),
      line(DrawTool.crayon, kCanvasColors[2], ring(500, 600, 140, 210)),
      line(DrawTool.brush, kCanvasColors[2], [
        (470, 450),
        (520, 600),
        (470, 750),
      ]),
      // Arms: elbow out, hand back on the hip.
      line(DrawTool.marker, kCanvasColors[8], [
        (380, 480),
        (240, 600),
        (370, 700),
      ]),
      line(DrawTool.marker, kCanvasColors[8], [
        (620, 480),
        (760, 600),
        (630, 700),
      ]),
      line(DrawTool.crayon, kCanvasColors[6], [(440, 800), (400, 1150)]),
      line(DrawTool.crayon, kCanvasColors[6], [(560, 800), (600, 1150)]),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('controller', () {
    test('draw, undo, redo, clear (undoable), limits', () {
      final c = DrawCanvasController();
      expect(c.isEmpty, isTrue);
      c
        ..begin(10, 10)
        ..extend(50, 50)
        ..extend(50.5, 50.5) // too close: ignored
        ..end();
      expect(c.strokes.single.length, 2);
      c
        ..setColor(kCanvasColors[5])
        ..begin(100, 100)
        ..extend(200, 200)
        ..end();
      expect(c.strokes.last.color, kCanvasColors[5]);
      c.undo();
      expect(c.strokes, hasLength(1));
      expect(c.canRedo, isTrue);
      c.redo();
      expect(c.strokes, hasLength(2));
      c.clear();
      expect(c.isEmpty, isTrue);
      c.undo();
      expect(c.strokes, hasLength(2), reason: 'clear can be undone');
      c.redo();
      expect(c.strokes, isEmpty);
      // New stroke after an undo drops the redo stack.
      c
        ..undo()
        ..undo()
        ..begin(1, 1)
        ..end();
      expect(c.canRedo, isFalse);
      // Eraser is not ink.
      final e = DrawCanvasController()
        ..setTool(DrawTool.eraser)
        ..begin(1, 1)
        ..extend(30, 30)
        ..end();
      expect(e.isEmpty, isTrue);
      // Points are clamped to the canvas.
      final k = DrawCanvasController()
        ..begin(1, 1)
        ..extend(-50, 99999)
        ..end();
      expect(k.strokes.single.xy.last, StrokeDrawing.height);
    });

    test('JSON round trip of the stroke list', () {
      final d = kidDrawing();
      final back = StrokeDrawing.tryDecode(d.encode())!;
      expect(back.strokes.length, d.strokes.length);
      expect(back.strokes[3].tool, DrawTool.brush);
      expect(back.strokes[4].xy.length, d.strokes[4].xy.length);
      expect(StrokeDrawing.tryDecode('oops'), isNull);
    });
  });

  group('analysis (same pipeline minus paper / authenticity)', () {
    test('a kid drawing is accepted, stats like a paper drawing, strokes '
        'map onto the cut-out and rig the arms on the hips', () async {
      final d = kidDrawing();
      final png = await renderDrawingPng(d);
      final a = analyzeCanvasDrawingSync(png);
      expect(a.rejectReason, isNull);
      expect(a.result.skill, lessThan(60), reason: 'not "polished"');
      expect(a.result.energy, greaterThan(20));
      expect(a.result.imageHash, hasLength(64));
      final hints = hintStrokesOf(d, a.mapping);
      expect(hints, hasLength(d.strokes.length));
      // Every stroke point lands inside the cut-out.
      final cut = await _size(a.result.cutoutPng);
      for (final h in hints) {
        for (final p in h.points) {
          expect(p.x, inInclusiveRange(-8, cut.$1 + 8));
          expect(p.y, inInclusiveRange(-8, cut.$2 + 8));
        }
      }
      final rig = autoRigPng(a.result.cutoutPng, strokes: hints);
      expect(rig.source, RigSource.strokes);
      final arms = rig.of(LimbKind.arm).toList();
      expect(arms, hasLength(2));
      // The hands are where the arm strokes end (on the hips).
      for (final hand in [hints[4].points.last, hints[5].points.last]) {
        expect(
          arms.map((l) => l.tip.dist(hand)).reduce(math.min),
          lessThan(0.08 * cut.$2),
        );
      }
      // The stored record decodes back to the same rigger strokes.
      final rec = strokesRecordJson(d, a.mapping);
      expect(hintStrokesFromRecord(rec)!.length, hints.length);
      final dir = renderDir();
      if (dir != null) {
        File('$dir/draw_canvas_export.png').writeAsBytesSync(png);
      }
    });

    test('an empty-ish drawing asks for more', () async {
      final d = StrokeDrawing(
        strokes: [
          Stroke(DrawTool.marker, kCanvasColors[0], [500, 500, 503, 503]),
        ],
      );
      final a = analyzeCanvasDrawingSync(await renderDrawingPng(d));
      expect(a.rejectReason?.message, 'もうすこし かいてみよう');
    });
  });

  testWidgets('screen: draw, undo / redo, clear asks, done returns strokes', (
    tester,
  ) async {
    await tester.runAsync(loadAppFonts);
    tester.view.physicalSize = const Size(393 * 2, 851 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    StrokeDrawing? result;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'ZenMaruGothic'),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<StrokeDrawing>(
                      MaterialPageRoute(
                        builder: (_) => DrawCanvasScreen(initial: kidDrawing()),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final st = tester.state<DrawCanvasScreenState>(
      find.byType(DrawCanvasScreen),
    );
    expect(st.controller.strokes, hasLength(8));
    // Pick green and a brush, draw a stroke.
    await tester.tap(find.byKey(const Key('color-6')));
    await tester.tap(find.byKey(const Key('tool-brush')));
    await tester.pump();
    final surface = tester.getRect(find.byKey(const Key('canvas-surface')));
    await tester.dragFrom(
      surface.center + const Offset(-60, 120),
      const Offset(120, 30),
    );
    await tester.pump();
    expect(st.controller.strokes, hasLength(9));
    expect(st.controller.strokes.last.tool, DrawTool.brush);
    expect(st.controller.strokes.last.color, kCanvasColors[6]);
    await tester.pump(const Duration(milliseconds: 300));
    final dir = renderDir();
    if (dir != null) {
      await tester.runAsync(() async {
        final ro =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final img = await ro.toImage(pixelRatio: 1.5);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/draw_canvas.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    await tester.tap(find.byKey(const Key('canvas-undo')));
    await tester.pump();
    expect(st.controller.strokes, hasLength(8));
    await tester.tap(find.byKey(const Key('canvas-redo')));
    await tester.pump();
    expect(st.controller.strokes, hasLength(9));
    // Clear asks first; cancelling keeps the drawing.
    await tester.tap(find.byKey(const Key('canvas-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('canvas-clear-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('canvas-clear-cancel')));
    await tester.pumpAndSettle();
    expect(st.controller.strokes, hasLength(9));
    await tester.tap(find.byKey(const Key('canvas-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('canvas-clear-ok')));
    await tester.pumpAndSettle();
    expect(st.controller.isEmpty, isTrue);
    final done = tester.widget<FilledButton>(
      find.byKey(const Key('canvas-done')),
    );
    expect(done.onPressed, isNull, reason: 'nothing to hand in');
    // No way to bring in a picture: no text field (paste), no image button.
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.photo_library), findsNothing);
    await tester.tap(find.byKey(const Key('canvas-undo')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('canvas-done')));
    await tester.pumpAndSettle();
    expect(result!.strokes, hasLength(9));
  });
}

Future<(int, int)> _size(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final f = await codec.getNextFrame();
  final s = (f.image.width, f.image.height);
  f.image.dispose();
  return s;
}
