// Family features × drawing loop (docs/LOOP.md §5): cards show the picture
// with drawn parts, family battles fly both players' drawn effects.
import 'dart:typed_data';

import 'package:doodle_battle/data/drawing_loop_storage.dart';
import 'package:doodle_battle/domain/cosmetics.dart';
import 'package:doodle_battle/features/card_print/card_output.dart';
import 'package:doodle_battle/features/drawing_loop/display_image.dart';
import 'package:doodle_battle/features/battle_stage/battle_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../support/harness.dart';
import '../card_print/card_pdf_test.dart' show testCardFonts;

Uint8List pngOf(int w, int h, img.Color c) {
  final i = img.Image(width: w, height: h, numChannels: 4);
  img.fill(i, color: c);
  return Uint8List.fromList(img.encodePng(i));
}

void main() {
  testWidgets('card preview uses the display image (drawing + parts)', (
    tester,
  ) async {
    final store = InMemoryDrawingLoopStorage();
    final c = testCharacter(id: 'c_1').copyWith(
      cosmetics: const CharacterCosmetics(
        parts: [
          CharacterPart(
            id: 'p1',
            type: PartType.hat,
            transform: PartTransform(cx: 0.5, cy: 0.02, scale: 0.5),
          ),
        ],
      ),
    );
    // A cached composite stands in for the rendered one.
    final composite = pngOf(30, 20, img.ColorRgba8(1, 2, 250, 255));
    await store.writeAsset('c_1', 'display_${displaySignature(c)}', composite);
    await store.writeAsset(
      'c_1',
      'part_p1',
      pngOf(5, 5, img.ColorRgba8(0, 0, 0, 255)),
    );
    await pumpApp(
      tester,
      characters: [c],
      overrides: [
        drawingLoopStorageProvider.overrideWithValue(store),
        cardFontsProvider.overrideWithValue(AsyncData(testCardFonts)),
      ],
    );
    await tapVisible(tester, find.byKey(const Key('home-zukan')));
    await tapVisible(tester, find.byKey(const Key('zukan-card-c_1')));
    await tapVisible(tester, find.byKey(const Key('detail-card')));
    final preview = find.descendant(
      of: find.byKey(const Key('card-preview-0')),
      matching: find.byType(Image),
    );
    final image = tester.widget<Image>(preview).image as MemoryImage;
    expect(image.bytes, composite);
  });

  testWidgets('family battle flies the drawn effect of the player who drew', (
    tester,
  ) async {
    final store = InMemoryDrawingLoopStorage();
    await store.writeAsset(
      'c_2',
      'fx_element_1',
      pngOf(12, 12, img.ColorRgba8(10, 200, 10, 255)),
    );
    await pumpApp(
      tester,
      characters: [
        testCharacter(id: 'c_1', name: 'ねこまる'),
        // Newest → あか by default.
        testCharacter(id: 'c_2', name: 'いぬまる').copyWith(
          cosmetics: const CharacterCosmetics(
            effects: {DrawnMove.element: 'fx_element_1'},
          ),
        ),
      ],
      overrides: [drawingLoopStorageProvider.overrideWithValue(store)],
    );
    await tapVisible(tester, find.byKey(const Key('home-family')));
    await tapNoSettle(tester, find.byKey(const Key('family-start')));
    await settleReal(tester, rounds: 10);
    // あか's drawing is handed to the stage; あお (no drawing) uses the
    // normal effect.
    final stage = tester.widget<BattleStage>(find.byType(BattleStage));
    expect(stage.drawnEffects.keys, [0]);
    await unmount(tester);
  });
}
