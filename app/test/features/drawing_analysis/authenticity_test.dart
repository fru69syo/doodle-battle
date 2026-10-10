import 'dart:math' as math;
import 'dart:typed_data';

import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/drawing_analysis/src/authenticity.dart';
import 'package:doodle_battle/features/drawing_analysis/src/normalize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../../tool/src/trust_cases.dart';

/// Calibration of the non-drawing detector (docs/TRUST.md §3). The full
/// report, including a local sample of real kids' drawings, is printed by
/// `dart run tool/trust_calibration.dart --kids <dir>`.
void main() {
  group('kids\' drawings are never refused', () {
    for (final c in kidCases()) {
      test(c.name, () {
        final r = analyzeDrawingSync(c.build());
        expect(
          r.rejectReason?.isNotPaperDrawing ?? false,
          isFalse,
          reason: '${c.name}: ${r.rejectReason} ${r.authenticity.toMap()}',
        );
      });
    }
  });

  group('non-drawings are refused with the gentle message', () {
    for (final c in notDrawingCases()) {
      test('${c.category}: ${c.name}', () {
        final r = analyzeDrawingSync(c.build());
        expect(r.rejectReason, isNotNull, reason: '${r.authenticity.toMap()}');
        expect(r.rejectReason!.isNotPaperDrawing, isTrue);
        expect(r.rejectReason!.message, 'かみに かいた えを とってね');
        switch (c.category) {
          case 'digital':
            expect(r.rejectReason, DrawingRejectReason.digital);
          case 'photo':
            expect(r.rejectReason, DrawingRejectReason.photo);
          default: // print / screen: both are lattices; the label may swap
            expect(
              r.rejectReason,
              anyOf(DrawingRejectReason.printed, DrawingRejectReason.screen),
            );
        }
      });
    }
  });

  group('signals', () {
    test('a dot lattice scores high, noise and a straight edge do not', () {
      const n = 128;
      final dots = Float64List(n * n);
      final noise = Float64List(n * n);
      final edge = Float64List(n * n);
      final rng = math.Random(1);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final u = (x * 0.94 + y * 0.34) / 5, v = (-x * 0.34 + y * 0.94) / 5;
          final du = u - u.floor() - 0.5, dv = v - v.floor() - 0.5;
          dots[y * n + x] =
              (du * du + dv * dv < 0.08 ? 60 : 220) + rng.nextDouble() * 6;
          noise[y * n + x] = 128 + rng.nextDouble() * 40;
          edge[y * n + x] = (x > 60 ? 40 : 220) + rng.nextDouble() * 6;
        }
      }
      expect(periodicLattice(dots, n, maxPeriod: 12), greaterThan(20));
      expect(periodicLattice(noise, n, maxPeriod: 12), lessThan(8));
      expect(periodicLattice(edge, n, maxPeriod: 12), lessThan(8));
      // Ruled lines (1D, period 16 px, noise-free) are not a 2D lattice.
      final lines = Float64List(n * n);
      for (var i = 0; i < n * n; i++) {
        lines[i] = (i ~/ n) % 16 < 2 ? 120 : 230;
      }
      expect(periodicLattice(lines, n, maxPeriod: 24), lessThan(8));
    });

    test('noise estimate: zero for digital, ~σ for sensor noise', () {
      const n = 64;
      final flat = Float64List(n * n)..fillRange(0, n * n, 200);
      final rng = math.Random(2);
      final noisy = Float64List.fromList([
        for (var i = 0; i < n * n; i++)
          150 + 3 * (rng.nextDouble() + rng.nextDouble() - 1) * 2.45,
      ]);
      expect(immerkaerNoise(flat, n), 0);
      expect(immerkaerNoise(noisy, n), inInclusiveRange(2, 4.5));
    });

    test('native pixels follow EXIF orientation', () {
      final p = NativePixels(
        raw: Uint8List(4 * 3 * 3),
        channels: 3,
        width: 4,
        height: 3,
        orientation: 6,
      );
      expect(p.orientedWidth, 3);
      expect(p.orientedHeight, 4);
      // Upright (0,0) is the stored bottom-left corner for orientation 6.
      final s = p.storedFromOriented(0, 0);
      expect((s.x, s.y), (0.0, 2.0));
    });

    test('rules need several signals at once', () {
      AuthenticitySignals sig({
        double paper = 1,
        double photo = 0,
        double polish = 0,
        double sym = 0.5,
        double grad = 0,
        double fine = 2,
        double coh = 0.5,
        double flat = 0,
        double noise = 2,
        double luma = 0,
        int periodic = 0,
      }) => AuthenticitySignals(
        paperLikeness: paper,
        paperDetected: true,
        photoLikelihood: photo,
        polish: polish,
        symmetry: sym,
        gradientShare: grad,
        fineLineRatio: fine,
        edgeCoherence: coh,
        backgroundShare: 0.7,
        backgroundFlatness: 0.9,
        noiseLevel: noise,
        exactFlatShare: flat,
        lumaPeriodicity: luma,
        chromaPeriodicity: 0,
        periodicPatches: periodic,
        patchCount: 6,
      );
      expect(classifyAuthenticity(sig()), isNull);
      // A single odd periodic patch is not enough.
      expect(classifyAuthenticity(sig(luma: 50, periodic: 1)), isNull);
      expect(
        classifyAuthenticity(sig(luma: 50, periodic: 3)),
        DrawingRejectReason.printed,
      );
      // Polished + symmetric but camera-noisy (a real adult drawing): ok.
      expect(classifyAuthenticity(sig(polish: 0.8, sym: 1)), isNull);
      expect(
        classifyAuthenticity(sig(polish: 0.8, sym: 1, flat: 0.1, noise: 0.2)),
        DrawingRejectReason.digital,
      );
      // No paper alone (tinted paper, dim room) is not a reason.
      expect(classifyAuthenticity(sig(paper: 0, photo: 0.7)), isNull);
      expect(
        classifyAuthenticity(
          sig(paper: 0, photo: 0.7, fine: 0, coh: 0.9, grad: 0.4),
        ),
        DrawingRejectReason.photo,
      );
    });
  });

  test('a small part drawing (Loop parts/effects) is not refused', () {
    final c = DoodleCanvasForTest.smallPart();
    final r = analyzeDrawingSync(c);
    expect(r.rejectReason?.isNotPaperDrawing ?? false, isFalse);
  });
}

/// Tiny wobbly star in a corner of the page, like a drawn part.
abstract final class DoodleCanvasForTest {
  static Uint8List smallPart() {
    final im = img.Image(width: 800, height: 600)
      ..clear(img.ColorRgb8(255, 255, 255));
    final rng = math.Random(3);
    for (var k = 0; k < 400; k++) {
      final a = k / 400 * 2 * math.pi;
      final r = 40 + 18 * math.sin(5 * a) + rng.nextDouble() * 3;
      img.fillCircle(
        im,
        x: (200 + r * math.cos(a)).round(),
        y: (150 + r * math.sin(a)).round(),
        radius: 3,
        color: img.ColorRgb8(240, 140, 30),
      );
    }
    return img.encodePng(im);
  }
}
