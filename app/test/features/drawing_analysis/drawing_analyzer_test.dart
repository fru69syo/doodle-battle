import 'dart:typed_data';

import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/drawing_analysis/src/morphology.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../../tool/src/doodle_painter.dart';
import 'synthetic_drawings.dart';

DrawingAnalysisReport _analyze(String name, Uint8List bytes) {
  final r = analyzeDrawingSync(bytes);
  // Calibration log (see docs/VISION.md).
  // ignore: avoid_print
  print('[$name] energy=${r.result.energy} skill=${r.result.skill} '
      'element=${r.result.element.name} stats=${r.result.baseStats} '
      'reject=${r.rejectReason?.name} ${r.totalMs}ms');
  return r;
}

void main() {
  group('scoring behaviour', () {
    late DrawingAnalysisReport kid, kid2, marker, skilled, photo, landscape;

    setUpAll(() {
      kid = _analyze('kid crayon', kidScribble().encodePng());
      kid2 = _analyze('kid crayon #2', kidScribble(seed: 2).encodePng());
      marker = _analyze('kid marker', kidMarker().encodePng());
      skilled = _analyze('skilled line art', skilledLineArt().encodePng());
      photo = _analyze('photo still-life', photoLike());
      landscape = _analyze('photo landscape', photoLandscape());
    });

    test('wobbly crayon scribble: low skill, high energy', () {
      for (final r in [kid, kid2]) {
        expect(r.result.skill, lessThanOrEqualTo(35));
        expect(r.result.energy, greaterThanOrEqualTo(75));
        expect(r.features.colorCount, inInclusiveRange(3, 5));
        expect(r.result.isShobo, isFalse);
        expect(r.rejectReason, isNull);
      }
    });

    test('kid marker stick figure is not judged skilled', () {
      expect(marker.result.skill, lessThanOrEqualTo(35));
      expect(marker.rejectReason, isNull);
    });

    test('clean symmetric shaded line art: high skill', () {
      expect(skilled.result.skill, greaterThan(60));
      expect(skilled.features.symmetry, greaterThan(0.9));
      expect(skilled.features.shadingLevel, greaterThan(0.5));
      expect(skilled.result.skill, greaterThan(kid.result.skill + 40));
    });

    test('photo-like images become しょぼキャラ', () {
      for (final r in [photo, landscape]) {
        expect(r.result.skill, greaterThan(75));
        expect(r.result.isShobo, isTrue);
        expect(r.features.photoLikelihood, greaterThan(0.6));
        // Budget is cut to 0.35x.
        expect(r.result.baseStats.total,
            lessThan((200 + 2 * r.result.energy) * 0.36));
      }
    });

    test('kid scribble out-powers skilled art and photos', () {
      expect(kid.result.baseStats.total,
          greaterThan(skilled.result.baseStats.total * 2));
      expect(kid.result.baseStats.total,
          greaterThan(photo.result.baseStats.total * 2));
    });
  });

  group('near-empty drawings', () {
    test('single dot is rejected with zero energy', () {
      final r = _analyze('single dot', singleDot().encodePng());
      expect(r.rejectReason, DrawingRejectReason.nearlyEmpty);
      expect(r.rejectReason!.message, 'もうすこし かいてみよう');
      expect(r.result.energy, lessThan(5));
      expect(rejectReasonOf(r.result), DrawingRejectReason.nearlyEmpty);
    });

    test('tiny single line is rejected with very low energy', () {
      final r = _analyze('tiny line', tinyLine().encodePng());
      expect(r.rejectReason, DrawingRejectReason.nearlyEmpty);
      expect(r.result.energy, lessThan(5));
    });

    test('blank paper is rejected', () {
      final r = _analyze('blank', DoodleCanvas(640, 480).encodePng());
      expect(r.rejectReason, DrawingRejectReason.nearlyEmpty);
      expect(r.result.energy, 0);
    });
  });

  group('element from dominant colour', () {
    final cases = <String, (DoodleCanvas Function(), ElementType)>{
      'red': (() => colourBlob(Crayon.red), ElementType.fire),
      'orange': (() => colourBlob(Crayon.orange), ElementType.fire),
      'blue': (() => colourBlob(Crayon.blue), ElementType.water),
      'sky': (() => colourBlob(Crayon.sky), ElementType.water),
      'green': (() => colourBlob(Crayon.green), ElementType.leaf),
      'yellow': (() => colourBlob(Crayon.yellow), ElementType.thunder),
      'black/grey': (monochrome, ElementType.shadow),
      'rainbow': (rainbowBlob, ElementType.rainbow),
    };
    for (final e in cases.entries) {
      test('${e.key} → ${e.value.$2.name}', () {
        final r = _analyze('element ${e.key}', e.value.$1().encodePng());
        expect(r.result.element, e.value.$2);
      });
    }
  });

  group('paper detection and cut-out', () {
    test('paper on a darker table with perspective and uneven light', () {
      final paper = kidScribble();
      final shot = photographedOnTable(paper);
      final r = _analyze('photographed on table', shot.jpeg);
      expect(r.paperQuad, isNotNull);
      expect(r.features.paperDetected, isTrue);

      // Ground truth: the painted silhouette in paper coordinates, sampled
      // at the analyser's output grid (which spans the paper minus inset).
      final gtPaper = Mask(paper.width, paper.height, paper.inkMask());
      final gtFilled = fillHoles(close(gtPaper, 3 * paper.width / 512));
      final sil = r.silhouette;
      final gt = Mask(sil.width, sil.height);
      const span = 1 - 2 * kPaperInset;
      for (var y = 0; y < sil.height; y++) {
        final v = kPaperInset + span * (y + 0.5) / sil.height;
        for (var x = 0; x < sil.width; x++) {
          final u = kPaperInset + span * (x + 0.5) / sil.width;
          final px = (u * paper.width).floor().clamp(0, paper.width - 1);
          final py = (v * paper.height).floor().clamp(0, paper.height - 1);
          gt.bits[y * sil.width + x] = gtFilled.bits[py * paper.width + px];
        }
      }
      final iou = sil.iou(gt);
      // ignore: avoid_print
      print('[photographed on table] mask IoU vs ground truth = '
          '${iou.toStringAsFixed(3)}');
      expect(iou, greaterThanOrEqualTo(0.8));

      // Scores survive the camera: still a strong kid character.
      final flat = _analyze('same drawing, flat scan', paper.encodePng());
      expect(r.result.element, flat.result.element);
      expect((r.result.skill - flat.result.skill).abs(), lessThan(15));
      expect((r.result.energy - flat.result.energy).abs(), lessThan(15));
    });

    test('cut-out PNG is RGBA, transparent outside, longest side <= 512', () {
      final r = analyzeDrawingSync(kidScribble().encodePng());
      final png = img.decodePng(r.result.cutoutPng)!;
      expect(png.numChannels, 4);
      expect(png.width <= 512 && png.height <= 512, isTrue);
      expect(png.getPixel(0, 0).a, 0);
      expect(png.getPixel(png.width ~/ 2, png.height ~/ 2).a, 255);
    });

    test('paper filling the whole frame needs no crop', () {
      final r = analyzeDrawingSync(kidScribble().encodePng());
      expect(r.paperQuad, isNull);
      expect(r.features.paperLikeness, greaterThan(0.8));
    });
  });

  group('determinism and performance', () {
    test('identical input gives identical output (sync and isolate)', () async {
      final bytes = photographedOnTable(kidScribble(seed: 9)).jpeg;
      final a = analyzeDrawingSync(bytes).result;
      final b = analyzeDrawingSync(bytes).result;
      final c = await analyzeDrawing(bytes);
      for (final other in [b, c]) {
        expect(other.imageHash, a.imageHash);
        expect(other.cutoutPng, a.cutoutPng);
        expect(other.features, a.features);
        expect(other.energy, a.energy);
        expect(other.skill, a.skill);
        expect(other.element, a.element);
        expect(other.baseStats, a.baseStats);
      }
      expect(a.imageHash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('different drawings hash differently', () {
      final a = analyzeDrawingSync(kidScribble(seed: 1).encodePng());
      final b = analyzeDrawingSync(kidScribble(seed: 2).encodePng());
      expect(a.result.imageHash, isNot(b.result.imageHash));
    });

    test('EXIF orientation is applied before analysis', () {
      final upright = kidMarker().toImage();
      final stored = img.copyRotate(upright, angle: -90); // sensor layout
      stored.exif.imageIfd.orientation = 6; // "rotate 90° CW to view"
      final a = analyzeDrawingSync(img.encodePng(upright));
      final b = analyzeDrawingSync(img.encodeJpg(stored, quality: 95));
      expect(b.silhouette.width, a.silhouette.width);
      expect(b.silhouette.height, a.silhouette.height);
      expect(b.silhouette.iou(a.silhouette), greaterThan(0.8));
    });

    test('rejects undecodable bytes', () {
      expect(() => analyzeDrawingSync(Uint8List.fromList([1, 2, 3, 4])),
          throwsA(isA<UndecodableImageException>()));
    });

    test('4000x3000 camera photo is analysed well under 3 s', () {
      final small = img.decodeJpg(photographedOnTable(kidScribble()).jpeg)!;
      final big = img.copyResize(small,
          width: 4000, height: 3000, interpolation: img.Interpolation.linear);
      final bytes = img.encodeJpg(big, quality: 88);
      final sw = Stopwatch()..start();
      final r = analyzeDrawingSync(bytes);
      final ms = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('[4000x3000 JPEG ${bytes.length ~/ 1024} KiB] total ${ms}ms '
          '${r.timingsMs}');
      expect(r.paperQuad, isNotNull);
      expect(ms, lessThan(3000));
    });
  });

  group('cloud blending', () {
    test('applyCloudSkill blends 0.6/0.4 and re-derives stats', () {
      final r = analyzeDrawingSync(kidScribble().encodePng()).result;
      final blended = applyCloudSkill(r, 100);
      expect(blended.skill, closeTo(0.6 * r.skill + 40, 0.051));
      expect(blended.energy, r.energy);
      expect(blended.baseStats,
          computeBaseStatsFromMap(r.features, r.energy, blended.skill));
      expect(blended.baseStats.total, lessThanOrEqualTo(r.baseStats.total));
    });
  });
}
