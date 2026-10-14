import 'dart:typed_data';

import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/domain/cosmetics.dart';
import 'package:doodle_battle/features/drawing_loop/parts/composite.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Opaque [w]×[h] rectangle of one colour.
Uint8List solid(int w, int h, img.Color color) {
  final i = img.Image(width: w, height: h, numChannels: 4);
  img.fill(i, color: color);
  return Uint8List.fromList(img.encodePng(i));
}

img.Image decode(Uint8List png) =>
    img.decodePng(png)!.convert(numChannels: 4, format: img.Format.uint8);

int alphaAt(img.Image i, num x, num y) =>
    i.getPixel(x.round(), y.round()).a.toInt();

void main() {
  final red = img.ColorRgba8(220, 30, 30, 255);
  final blue = img.ColorRgba8(30, 60, 220, 255);

  test('no parts: the base drawing is returned untouched', () {
    final base = solid(80, 60, red);
    final out = renderComposite(
      CompositeRequest(basePng: base, parts: const []),
    );
    expect(out.png, same(base));
    expect((out.width, out.height), (80, 60));
  });

  test('a hat on top grows the canvas upwards; alpha is where expected', () {
    final base = solid(100, 80, red);
    final hat = solid(40, 40, blue);
    const t = PartTransform(cx: 0.5, cy: -0.25, scale: 0.4); // 40 px square
    final out = renderComposite(
      CompositeRequest(basePng: base, parts: [CompositePart(hat, t)]),
    );
    final pad = partOutlinePx + partGlowPx(EvolutionStage.normal) + 1;
    // Base spans y 0..80, hat spans y -40..0 → 120 tall, 100 wide (+pad).
    expect(out.width, 100 + 2 * pad);
    expect(out.height, 120 + 2 * pad);
    expect(out.baseRect.top, closeTo(40 + pad, 1e-9));
    expect(out.baseRect.left, closeTo(pad, 1e-9));
    final i = decode(out.png);
    expect((i.width, i.height), (out.width, out.height));
    // Corners of the canvas next to the hat are transparent.
    expect(alphaAt(i, 0, 0), 0);
    expect(alphaAt(i, out.width - 1, 0), 0);
    // Hat centre: opaque blue. Base centre: opaque red.
    final hatPx = i.getPixel(out.width ~/ 2, pad + 20);
    expect(hatPx.a, 255);
    expect(hatPx.b, greaterThan(200));
    final basePx = i.getPixel(out.width ~/ 2, pad + 40 + 40);
    expect(basePx.a, 255);
    expect(basePx.r, greaterThan(200));
    // White sticker edge just beside the hat.
    final edge = i.getPixel(out.width ~/ 2 - 21, pad + 20);
    expect(edge.a, greaterThan(200));
    expect((edge.r, edge.g, edge.b), (255, 255, 255));
  });

  test('behind parts go under the base, front parts over it', () {
    final base = solid(100, 100, red);
    final part = solid(50, 50, blue);
    const centre = PartTransform(cx: 0.5, cy: 0.5, scale: 0.5);
    for (final behind in [true, false]) {
      final out = renderComposite(
        CompositeRequest(
          basePng: base,
          parts: [CompositePart(part, centre.copyWith(behind: behind))],
        ),
      );
      final i = decode(out.png);
      final c = i.getPixel(out.width ~/ 2, out.height ~/ 2);
      expect(c.b > c.r, !behind, reason: 'behind=$behind');
    }
  });

  test('output never exceeds maxSide and keeps the aspect ratio', () {
    final base = solid(500, 250, red);
    final wing = solid(300, 100, blue);
    final out = renderComposite(
      CompositeRequest(
        basePng: base,
        parts: [
          CompositePart(
            wing,
            const PartTransform(cx: 1.3, cy: 0.5, scale: 1.2, rotation: 0.3),
          ),
        ],
        maxSide: 256,
      ),
    );
    expect(out.width, lessThanOrEqualTo(256));
    expect(out.height, lessThanOrEqualTo(256));
    expect(out.baseRect.width / out.baseRect.height, closeTo(2, 0.01));
    final i = decode(out.png);
    expect((i.width, i.height), (out.width, out.height));
    expect(alphaAt(i, out.baseRect.center.dx, out.baseRect.center.dy), 255);
  });

  test('evolution makes parts more prominent (glow, then bigger)', () {
    final base = solid(100, 100, red);
    final hat = solid(30, 30, blue);
    const t = PartTransform(cx: 0.5, cy: -0.3, scale: 0.3);
    int opaqueOutsideBase(EvolutionStage s) {
      final out = renderComposite(
        CompositeRequest(
          basePng: base,
          parts: [CompositePart(hat, t)],
          stage: s,
          glowArgb: 0xFF00FF00,
        ),
      );
      final i = decode(out.png);
      var n = 0;
      for (var y = 0; y < out.baseRect.top.floor() - 1; y++) {
        for (var x = 0; x < out.width; x++) {
          if (i.getPixel(x, y).a > 0) n++;
        }
      }
      return n;
    }

    final normal = opaqueOutsideBase(EvolutionStage.normal);
    final kagayaki = opaqueOutsideBase(EvolutionStage.kagayaki);
    final densetsu = opaqueOutsideBase(EvolutionStage.densetsu);
    expect(kagayaki, greaterThan(normal));
    expect(densetsu, greaterThan(kagayaki));
    expect(partScaleBoost(EvolutionStage.densetsu), greaterThan(1));

    // かがやき glow uses the given (element) colour.
    final out = renderComposite(
      CompositeRequest(
        basePng: base,
        parts: [CompositePart(hat, t)],
        stage: EvolutionStage.kagayaki,
        glowArgb: 0xFF00FF00,
      ),
    );
    final i = decode(out.png);
    final hatLeft = out.width / 2 - 15;
    final glow = i.getPixel((hatLeft - partOutlinePx - 2).round(), 20);
    expect(glow.a, greaterThan(0));
    expect(glow.g, greaterThan(glow.r));
  });

  test('is deterministic', () {
    final req = CompositeRequest(
      basePng: solid(64, 48, red),
      parts: [
        CompositePart(
          solid(20, 10, blue),
          const PartTransform(cx: 0.8, cy: 0.1, scale: 0.4, rotation: 0.7),
        ),
      ],
      stage: EvolutionStage.kagayaki,
    );
    expect(renderComposite(req).png, renderComposite(req).png);
  });

  test('compositeRequestFor skips parts whose PNG is missing', () {
    final c =
        CharacterV2.create(
          id: 'c1',
          name: 'x',
          imagePath: '',
          imageHash: 'h',
          rawFeatures: const {},
          energy: 1,
          skill: 1,
          createdAt: DateTime.utc(2026),
        ).copyWith(
          level: 50,
          cosmetics: const CharacterCosmetics(
            parts: [
              CharacterPart(
                id: 'a',
                type: PartType.hat,
                transform: PartTransform(cx: 0.5, cy: 0, scale: 0.3),
              ),
              CharacterPart(
                id: 'b',
                type: PartType.tail,
                transform: PartTransform(
                  cx: 1,
                  cy: 1,
                  scale: 0.3,
                  behind: true,
                ),
              ),
            ],
          ),
        );
    final r = compositeRequestFor(c, solid(10, 10, red), {
      'b': solid(5, 5, blue),
    }, glowArgb: 0xFF112233);
    expect(r.parts.length, 1);
    expect(r.parts.single.transform.behind, isTrue);
    expect(r.stage, EvolutionStage.densetsu);
  });
}
