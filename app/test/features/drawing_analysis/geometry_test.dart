import 'dart:typed_data';

import 'package:doodle_battle/features/drawing_analysis/src/morphology.dart';
import 'package:doodle_battle/features/drawing_analysis/src/paper_detection.dart';
import 'package:doodle_battle/features/drawing_analysis/src/raster.dart';
import 'package:flutter_test/flutter_test.dart';

Mask _rect(int w, int h, int x0, int y0, int x1, int y1) {
  final m = Mask(w, h);
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      m.bits[y * w + x] = 1;
    }
  }
  return m;
}

void main() {
  test('contour of a rectangle visits its whole border once', () {
    final m = _rect(20, 20, 3, 4, 12, 9); // 10 x 6
    final c = traceContour(m, 4 * 20 + 3);
    expect(c.length ~/ 2, 2 * (10 + 6) - 4);
    final pts = toPoints(c);
    expect(polygonArea(pts), closeTo(9 * 5, 1e-9));
  });

  test('isolated pixel contour', () {
    final m = _rect(5, 5, 2, 2, 2, 2);
    expect(traceContour(m, 12), Int32List.fromList([2, 2]));
  });

  test('convex hull of a square with an interior point', () {
    final hull = convexHull(const [
      Pt(0, 0),
      Pt(10, 0),
      Pt(10, 10),
      Pt(0, 10),
      Pt(5, 5),
    ]);
    expect(hull.length, 4);
    expect(polygonArea(hull), 100);
  });

  test('fillHoles fills a ring and morphology is symmetric', () {
    final ring = _rect(30, 30, 5, 5, 24, 24);
    for (var y = 9; y <= 20; y++) {
      for (var x = 9; x <= 20; x++) {
        ring.bits[y * 30 + x] = 0;
      }
    }
    expect(fillHoles(ring).count(), 20 * 20);
    final dot = _rect(31, 31, 15, 15, 15, 15);
    final grown = dilate(dot, 3);
    expect(grown.iou(grown.mirrored()), 1);
    expect(erode(grown, 3).count(), 1);
  });

  test('labelComponents uses 8-connectivity', () {
    final m = Mask(4, 4);
    m.bits[0] = 1;
    m.bits[5] = 1; // diagonal neighbour
    m.bits[15] = 1;
    final l = labelComponents(m);
    expect(l.components.length, 2);
    expect(l.components.first.area, 2);
  });

  test('square-to-quad maps the corners', () {
    const q = PaperQuad(Pt(10, 20), Pt(110, 25), Pt(120, 140), Pt(5, 130));
    final h = SquareToQuad(q);
    void near(Pt a, Pt b) {
      expect(a.x, closeTo(b.x, 1e-6));
      expect(a.y, closeTo(b.y, 1e-6));
    }

    near(h.map(0, 0), q.topLeft);
    near(h.map(1, 0), q.topRight);
    near(h.map(1, 1), q.bottomRight);
    near(h.map(0, 1), q.bottomLeft);
  });
}
