import 'dart:io';
import 'dart:typed_data';

import 'package:doodle_battle/data/before_photo.dart';
import 'package:doodle_battle/data/character_repository.dart';
import 'package:doodle_battle/data/file_character_repository.dart';
import 'package:doodle_battle/data/memory_character_repository.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/video_export/before_photo_extractor.dart';
import 'package:doodle_battle/features/video_export/video_export_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../support/fakes.dart';
import '../../support/harness.dart';
import '../drawing_analysis/synthetic_drawings.dart';
import 'video_fixtures.dart';

/// Mean brightness of a frame's outer 4 % border.
double _borderLuma(img.Image im) {
  var sum = 0.0, n = 0;
  final bx = (im.width * 0.04).ceil(), by = (im.height * 0.04).ceil();
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (x >= bx && x < im.width - bx && y >= by && y < im.height - by) {
        continue;
      }
      final p = im.getPixel(x, y);
      sum += (p.r + p.g + p.b) / 3;
      n++;
    }
  }
  return sum / n;
}

void main() {
  group('extractBeforePhotoSync', () {
    test('keeps only the perspective-corrected paper, ≤ 1280 px', () {
      final shot = photographedKidDrawing();
      expect(shot.report.paperQuad, isNotNull);
      final photo = extractBeforePhotoSync(
        shot.jpeg,
        BeforePhotoInput.fromReport(shot.report),
      )!;
      final im = img.decodeJpg(photo.jpeg)!;
      expect(
        im.width > im.height ? im.width : im.height,
        lessThanOrEqualTo(1280),
      );
      // Portrait 3:4 sheet, not the 1200×1600 frame with the table around it.
      expect(im.width / im.height, closeTo(600 / 800, 0.04));
      // The border is paper (bright), not the darker table.
      expect(_borderLuma(im), greaterThan(200));
      final ink = photo.inkRect!;
      expect(ink.left, inInclusiveRange(0, 1));
      expect(ink.top, inInclusiveRange(0, 1));
      expect(ink.left + ink.width, lessThanOrEqualTo(1.01));
      expect(ink.top + ink.height, lessThanOrEqualTo(1.01));
      // Roughly where the scribble is (top half of the sheet).
      expect(ink.centerY, lessThan(0.5));
    });

    test('no sheet but clearly paper: crops around the drawing', () {
      final png = kidScribble(seed: 3, width: 1000, height: 1000).encodePng();
      final report = analyzeDrawingSync(png);
      final input = BeforePhotoInput.fromReport(report);
      expect(input.quad, isNull);
      final photo = extractBeforePhotoSync(png, input)!;
      final im = img.decodeJpg(photo.jpeg)!;
      expect(im.width * im.height, lessThan(1000 * 1000));
      expect(photo.inkRect, isNotNull);
    });

    test('a photo without paper is never kept', () {
      for (final jpeg in [photoLike(), photoLandscape()]) {
        final input = BeforePhotoInput.fromReport(analyzeDrawingSync(jpeg));
        expect(input.quad, isNull);
        expect(input.paperLikeness, lessThan(kMinPaperLikenessWithoutQuad));
        expect(extractBeforePhotoSync(jpeg, input), isNull);
      }
    });

    test('garbage bytes give null (async wrapper never throws)', () async {
      final input = BeforePhotoInput(
        quad: null,
        paperWidth: 10,
        paperHeight: 10,
        inkBox: const [1, 1, 5, 5],
        cutoutWidth: 4,
        cutoutHeight: 4,
        paperLikeness: 1,
      );
      expect(
        await extractBeforePhoto(Uint8List.fromList([1, 2, 3]), input),
        isNull,
      );
    });

    test('pngSize reads the header', () {
      expect(pngSize(testPng()), (8, 8));
      expect(pngSize(Uint8List(4)), isNull);
    });
  });

  group('storage', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('db_before'));
    tearDown(() => dir.deleteSync(recursive: true));

    final photo = BeforePhoto(
      jpeg: Uint8List.fromList([0xff, 0xd8, 1, 2, 3]),
      inkRect: const NormRect(0.1, 0.2, 0.3, 0.4),
    );

    Future<void> roundTrip(CharacterRepository repo) async {
      await repo.add(testCharacter(id: 'c_1'), testPng(), limit: 12);
      await repo.add(testCharacter(id: 'c_2'), testPng(), limit: 12);
      expect(await repo.readBeforePhoto('c_1'), isNull);
      await repo.saveBeforePhoto('c_1', photo);
      await repo.saveBeforePhoto('c_2', photo);
      final back = (await repo.readBeforePhoto('c_1'))!;
      expect(back.jpeg, photo.jpeg);
      expect(back.inkRect, photo.inkRect);
      // Deleted together with the character…
      await repo.delete('c_1');
      expect(await repo.readBeforePhoto('c_1'), isNull);
      expect(await repo.readBeforePhoto('c_2'), isNotNull);
      // …and by delete-all.
      await repo.deleteAll();
      expect(await repo.readBeforePhoto('c_2'), isNull);
      // Unknown characters cannot get one.
      expect(
        () => repo.saveBeforePhoto('c_9', photo),
        throwsA(isA<StateError>()),
      );
    }

    test('file repository', () async {
      final repo = FileCharacterRepository(dir);
      await roundTrip(repo);
      expect(Directory('${dir.path}/characters/before').existsSync(), isFalse);
    });

    test(
      'file repository: files live next to the character and go with it',
      () async {
        final repo = FileCharacterRepository(dir);
        await repo.add(testCharacter(id: 'c_1'), testPng(), limit: 12);
        await repo.saveBeforePhoto('c_1', photo);
        final jpg = File('${dir.path}/characters/before/c_1.jpg');
        expect(jpg.existsSync(), isTrue);
        // The sidecar JSON is not mistaken for a character.
        expect((await repo.loadAll()).map((c) => c.id), ['c_1']);
        await repo.delete('c_1');
        expect(jpg.existsSync(), isFalse);
      },
    );

    test('memory repository', () => roundTrip(InMemoryCharacterRepository()));

    test(
      'keepBeforePhoto stores the extracted photo, ignores failures',
      () async {
        final repo = InMemoryCharacterRepository([
          (testCharacter(), testPng()),
        ]);
        await keepBeforePhoto(repo, 'c_1', Future.value(photo));
        expect(await repo.readBeforePhoto('c_1'), isNotNull);
        await keepBeforePhoto(repo, 'c_1', null);
        await keepBeforePhoto(repo, 'c_404', Future.value(photo));
        await keepBeforePhoto(
          repo,
          'c_1',
          Future.delayed(const Duration(seconds: 1), () => photo),
          timeout: const Duration(milliseconds: 10),
        );
      },
    );
  });
}
