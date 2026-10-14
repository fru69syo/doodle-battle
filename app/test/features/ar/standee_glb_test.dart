import 'dart:math' as math;
import 'dart:typed_data';

import 'package:doodle_battle/domain/character.dart' show EvolutionStage;
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/features/ar/ar_effects.dart';
import 'package:doodle_battle/features/ar/glb/glb_reader.dart';
import 'package:doodle_battle/features/ar/glb/glb_writer.dart';
import 'package:doodle_battle/features/ar/glb/standee_glb.dart';
import 'package:doodle_battle/features/ar/glb/standee_textures.dart';
import 'package:doodle_battle/features/ar/sample_cutout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 400x300 canvas, transparent, with an opaque 200x100 rectangle at (50, 120)
/// so cropping, aspect ratio and the paper border can be checked exactly.
Uint8List rectCutout() {
  final im = img.Image(width: 400, height: 300, numChannels: 4);
  img.fill(im, color: img.ColorRgba8(0, 0, 0, 0));
  img.fillRect(
    im,
    x1: 50,
    y1: 120,
    x2: 249,
    y2: 219,
    color: img.ColorRgba8(200, 30, 30, 255),
  );
  return img.encodePng(im);
}

List<double> positionsOf(GlbDocument doc, int meshIndex, int primitive) {
  final p =
      (doc.list('meshes')[meshIndex]['primitives'] as List)[primitive]
          as Map<String, Object?>;
  final pos = (p['attributes'] as Map)['POSITION'] as int;
  return doc.floatAccessor(pos).toList();
}

void main() {
  group('GLB container', () {
    late StandeeGlb result;
    late GlbDocument doc;

    setUpAll(() {
      result = buildStandeeGlb(buildSampleCutoutPng());
      doc = GlbDocument.parse(result.glb);
    });

    test('header, chunks and lengths are valid', () {
      final bd = ByteData.sublistView(result.glb);
      expect(bd.getUint32(0, Endian.little), 0x46546C67); // glTF
      expect(bd.getUint32(4, Endian.little), 2);
      expect(bd.getUint32(8, Endian.little), result.glb.length);
      expect(result.glb.length % 4, 0);
      expect(bd.getUint32(16, Endian.little), 0x4E4F534A); // JSON
      expect(doc.json['asset'], containsPair('version', '2.0'));
      expect(doc.bin, isNotNull);
      expect(doc.validate(), isEmpty);
    });

    test('buffer byteLength matches BIN chunk', () {
      final bl = doc.list('buffers').single['byteLength'] as int;
      expect(bl, doc.bin!.length);
    });

    test('every accessor fits its bufferView with exact byte length', () {
      for (final a in doc.list('accessors')) {
        final view = doc.list('bufferViews')[a['bufferView'] as int];
        final size = a['componentType'] == GltfComponentType.float ? 4 : 2;
        final n = GlbWriter.componentsOf(a['type'] as String);
        expect(view['byteLength'], (a['count'] as int) * n * size);
      }
    });

    test('embedded textures are PNGs that decode', () {
      final images = doc.list('images');
      expect(images.length, greaterThanOrEqualTo(2));
      for (var i = 0; i < images.length; i++) {
        expect(images[i]['mimeType'], 'image/png');
        final bytes = doc.imageBytes(i);
        expect(bytes.sublist(0, 8), [
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]);
        expect(img.decodePng(bytes), isNotNull);
      }
      final front = img.decodePng(doc.imageBytes(0))!;
      expect(math.max(front.width, front.height), lessThanOrEqualTo(512));
      expect(front.width, result.spriteWidth);
      expect(front.height, result.spriteHeight);
    });

    test('front/back are alpha-masked, single-sided; edge double-sided', () {
      final mats = {
        for (final m in doc.list('materials')) m['name'] as String: m,
      };
      expect(mats['paper_front']!['alphaMode'], 'MASK');
      expect(mats['paper_front']!['alphaCutoff'], 0.5);
      expect(mats['paper_front']!['doubleSided'], false);
      expect(mats['paper_back']!['alphaMode'], 'MASK');
      expect(mats['paper_back']!['doubleSided'], false);
      expect(mats['paper_edge']!['doubleSided'], true);
      expect(doc.json['extensionsUsed'], contains('KHR_materials_unlit'));
      expect(doc.json['extensionsRequired'], isNull);
    });

    test('front faces +Z, back faces -Z, with paper thickness', () {
      final front = positionsOf(doc, 0, 0);
      final back = positionsOf(doc, 0, 1);
      expect(front[2], closeTo(0.0015, 1e-6));
      expect(back[2], closeTo(-0.0015, 1e-6));
      // Winding: front CCW from +Z, back reversed.
      final prims = (doc.list('meshes')[0]['primitives'] as List)
          .cast<Map<String, Object?>>();
      final idxF = prims[0]['indices'] as int;
      final idxB = prims[1]['indices'] as int;
      List<int> idx(int a) {
        final bytes = doc.bufferViewBytes(
          doc.list('accessors')[a]['bufferView'] as int,
        );
        final bd = ByteData.sublistView(bytes);
        return [for (var i = 0; i < 6; i++) bd.getUint16(i * 2, Endian.little)];
      }

      expect(idx(idxF), [0, 1, 2, 0, 2, 3]);
      expect(idx(idxB), [0, 2, 1, 0, 3, 2]);
    });

    test('origin at bottom centre, ~25 cm tall by default', () {
      final p = positionsOf(doc, 0, 0);
      final xs = [p[0], p[3], p[6], p[9]];
      final ys = [p[1], p[4], p[7], p[10]];
      expect(ys.reduce(math.min), closeTo(0, 1e-6));
      expect(ys.reduce(math.max), closeTo(0.25, 1e-6));
      expect(xs.reduce(math.min), closeTo(-xs.reduce(math.max), 1e-6));
      expect(result.heightMeters, closeTo(0.25, 1e-9));
    });

    test('has a looping idle animation with valid samplers', () {
      final anim = doc.list('animations').single;
      expect(anim['name'], standeeIdleAnimation);
      final samplers = (anim['samplers'] as List).cast<Map<String, Object?>>();
      for (final s in samplers) {
        final input = doc.list('accessors')[s['input'] as int];
        expect(input['min'], [0.0]);
        expect((input['max'] as List).single, closeTo(1.2, 1e-6));
        final out = doc.floatAccessor(s['output'] as int);
        // Loops seamlessly: first and last keyframe are equal.
        expect(out.sublist(out.length - 3), out.sublist(0, 3));
      }
    });
  });

  group('geometry', () {
    test('keeps the aspect ratio of the cropped drawing + border', () {
      final r = buildStandeeGlb(rectCutout());
      // Drawing 200x100 → border = round(200*0.035)=7 → 214x114 texture.
      expect(r.spriteWidth, 214);
      expect(r.spriteHeight, 114);
      expect(r.widthMeters / r.heightMeters, closeTo(214 / 114, 1e-9));
    });

    test('very wide drawings are capped in width', () {
      final im = img.Image(width: 500, height: 60, numChannels: 4);
      img.fill(im, color: img.ColorRgba8(10, 10, 200, 255));
      final r = buildStandeeGlb(img.encodePng(im));
      expect(r.widthMeters, closeTo(0.40, 1e-9));
      expect(r.heightMeters, lessThan(0.25));
    });

    test('custom height is respected', () {
      final r = buildStandeeGlb(
        buildSampleCutoutPng(),
        options: const StandeeGlbOptions(heightMeters: 0.3),
      );
      expect(r.heightMeters, closeTo(0.3, 1e-9));
    });

    test('large inputs are downscaled to ≤512 px textures', () {
      final im = img.Image(width: 1200, height: 900, numChannels: 4);
      img.fill(im, color: img.ColorRgba8(0, 200, 0, 255));
      final r = buildStandeeGlb(img.encodePng(im));
      expect(math.max(r.spriteWidth, r.spriteHeight), lessThanOrEqualTo(512));
    });

    test('rejects non-PNG input', () {
      expect(
        () => buildStandeeGlb(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });

    test('fully transparent input still produces a model', () {
      final im = img.Image(width: 50, height: 80, numChannels: 4);
      final r = buildStandeeGlb(img.encodePng(im));
      expect(GlbDocument.parse(r.glb).validate(), isEmpty);
      expect(r.spriteHeight, greaterThan(r.spriteWidth));
    });
  });

  group('textures', () {
    test(
      'white paper border surrounds the drawing; outside is transparent',
      () {
        final r = buildStandeeGlb(rectCutout());
        final front = img.decodePng(r.spritePng)!;
        // Corner: outside the rounded border → transparent.
        expect(front.getPixel(0, 0).a, 0);
        // Middle of the left border strip → opaque white paper.
        final border = front.getPixel(2, front.height ~/ 2);
        expect(border.a, 255);
        expect(border.r, greaterThan(250));
        // Centre → the red drawing.
        final c = front.getPixel(front.width ~/ 2, front.height ~/ 2);
        expect(c.r, 200);
        expect(c.g, 30);
      },
    );

    test('distance transform is exact on a single point', () {
      final mask = Uint8List(5 * 5)..[12] = 1;
      final d = squaredDistanceTransform(mask, 5, 5);
      expect(d[12], 0);
      expect(d[0], 8); // (2,2) → (0,0)
      expect(d[2], 4);
    });
  });

  group('evolution effects', () {
    CharacterV2 character(int level, ElementType element) => CharacterV2.create(
      id: 'c',
      name: 'test',
      imagePath: '/x.png',
      imageHash: 'h',
      rawFeatures: const {},
      energy: 50,
      skill: 30,
      createdAt: DateTime(2026),
      legacyElement: element,
    ).copyWith(level: level);

    test('stage → effects mapping (SPEC §6)', () {
      expect(
        ArEffects.forCharacter(character(9, ElementType.fire)).aura,
        false,
      );
      final lv10 = ArEffects.forCharacter(character(10, ElementType.water));
      expect(lv10.aura, true);
      expect(lv10.sparkles, false);
      expect(lv10.auraColor, elementAuraColor(ElementType.water));
      final lv20 = ArEffects.forCharacter(character(50, ElementType.rainbow));
      expect(lv20.aura, true);
      expect(lv20.sparkles, true);
      expect(lv20.rainbowAura, true);
    });

    test('no effects → no aura/sparkle nodes', () {
      final doc = GlbDocument.parse(buildStandeeGlb(rectCutout()).glb);
      final names = doc.list('nodes').map((n) => n['name']).toList();
      expect(names, isNot(contains('aura')));
      expect(names.where((n) => '$n'.startsWith('sparkle')), isEmpty);
    });

    test(
      'Lv10 adds a blended aura behind the paper, around the silhouette',
      () {
        final r = buildStandeeGlb(
          rectCutout(),
          options: StandeeGlbOptions(
            effects: ArEffects.forStage(
              EvolutionStage.kagayaki,
              ElementType.fire,
            ),
          ),
        );
        final doc = GlbDocument.parse(r.glb);
        expect(doc.validate(), isEmpty);
        final names = doc.list('nodes').map((n) => n['name']).toList();
        expect(names, contains('aura'));
        final aura = doc
            .list('materials')
            .firstWhere((m) => m['name'] == 'aura');
        expect(aura['alphaMode'], 'BLEND');
        expect(r.auraPng, isNotNull);
        final auraImg = img.decodePng(r.auraPng!)!;
        expect(math.max(auraImg.width, auraImg.height), lessThanOrEqualTo(256));
        // Aura quad is wider than the body and starts at the floor.
        final auraMesh = doc
            .list('meshes')
            .indexWhere((m) => m['name'] == 'aura');
        final p = positionsOf(doc, auraMesh, 0);
        expect(p[0], lessThan(-r.widthMeters / 2));
        expect(p[1], closeTo(0, 1e-6));
      },
    );

    test('Lv20 adds animated sparkles', () {
      final r = buildStandeeGlb(
        rectCutout(),
        options: StandeeGlbOptions(
          effects: ArEffects.forStage(
            EvolutionStage.densetsu,
            ElementType.thunder,
          ),
        ),
      );
      final doc = GlbDocument.parse(r.glb);
      expect(doc.validate(), isEmpty);
      final sparkleNodes = [
        for (final (i, n) in doc.list('nodes').indexed)
          if ('${n['name']}'.startsWith('sparkle_')) i,
      ];
      expect(sparkleNodes.length, 6);
      final channels = (doc.list('animations').single['channels'] as List)
          .cast<Map<String, Object?>>();
      final animated = channels
          .map((c) => (c['target'] as Map)['node'])
          .toSet();
      expect(animated, containsAll(sparkleNodes));
    });
  });

  test('idle curves loop and stay gentle', () {
    expect(idleHop(0), 0);
    expect(idleHop(1), 0);
    expect(idleHop(0.225), closeTo(1, 1e-9));
    expect(idleSquash(0), [1, 1, 1]);
    for (var p = 0.0; p <= 1; p += 0.05) {
      final s = idleSquash(p);
      expect(s[1], inInclusiveRange(0.92, 1.05));
      expect(sparkleScale(p), inInclusiveRange(0.15, 1.0));
    }
  });
}
