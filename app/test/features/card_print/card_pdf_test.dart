import 'dart:io';
import 'dart:typed_data';

import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:doodle_battle/features/battle_ui/move_labels.dart';
import 'package:doodle_battle/features/card_print/card_content.dart';
import 'package:doodle_battle/features/card_print/card_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';
import 'pdf_text.dart';

final testCardFonts = CardFonts(
  regular: ByteData.sublistView(
    File('assets/fonts/ZenMaruGothic-Regular.ttf').readAsBytesSync(),
  ),
  bold: ByteData.sublistView(
    File('assets/fonts/ZenMaruGothic-Bold.ttf').readAsBytesSync(),
  ),
);

CardContent content(Character c, {Uint8List? image, bool noImage = false}) =>
    cardContentFor(
      testSpec,
      c,
      image: noImage ? null : (image ?? testPng()),
      moveLabel: characterMoveLabel,
    );

void main() {
  group('cardStars', () {
    test('best stat gets 5 stars, others relative, at least 1', () {
      final s = cardStars(const Stats(hp: 100, atk: 50, def: 10, spd: 79));
      expect(s, {
        StatKind.hp: 5,
        StatKind.atk: 3,
        StatKind.def: 1,
        StatKind.spd: 4,
      });
    });

    test('same shape whatever the strength (no skill / power leak)', () {
      const strong = Stats(hp: 200, atk: 160, def: 120, spd: 80);
      const weak = Stats(hp: 70, atk: 56, def: 42, spd: 28);
      expect(cardStars(weak), cardStars(strong));
      // Level does not change the stars either (Lv shown as its own field).
      final c = testCharacter(stats: strong);
      expect(
        content(c.copyWith(level: 25)).stars,
        content(c.copyWith(level: 1)).stars,
      );
    });

    test('degenerate stats do not crash', () {
      final s = cardStars(const Stats(hp: 0, atk: 0, def: 0, spd: 0));
      expect(s.values, everyElement(1));
    });
  });

  test('content: name, Lv, moves, evolution, birth date', () {
    final c = testCharacter(
      name: 'ねこまる',
      level: 20,
    ).copyWith(elementMoveName: 'めらめらビーム', specialMoveName: 'ねこパンチ');
    final card = content(c);
    expect(card.name, 'ねこまる');
    expect(card.level, 20);
    expect(card.stage, EvolutionStage.densetsu);
    expect(card.moves, ['たいあたり', 'めらめらビーム', 'まもる', 'ねこパンチ']);
    expect(cardDateLabel(card.date), '2026.10.1');
  });

  test('single card: one page, card-sized, names and logo inside', () async {
    final bytes = await buildCardPdf(
      [content(testCharacter(name: 'ねこまる'))],
      fonts: testCardFonts,
      layout: CardLayout.single,
      compress: false,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(pdfPageCount(bytes), 1);
    // 63 × 88 mm = 178.58 × 249.45 pt.
    expect(String.fromCharCodes(bytes), contains('/MediaBox[0 0 178.58'));
    final texts = pdfTexts(bytes);
    expect(texts.any((t) => t.contains('ねこまる')), isTrue);
    expect(texts.any((t) => t.contains('らくがきバトル')), isTrue);
    expect(texts.any((t) => t.contains('たいりょく')), isTrue);
    expect(texts.any((t) => t.contains('Lv1')), isTrue);
    // Nothing about skill or raw numbers.
    for (final t in texts) {
      expect(t, isNot(contains('じょうず')));
      expect(t, isNot(contains('しょぼ')));
      expect(t, isNot(contains('140')));
    }
  });

  test('A4: nine cards per sheet, ten cards make two pages', () async {
    final chars = [
      for (var i = 0; i < 10; i++)
        testCharacter(
          id: 'c_$i',
          name: 'キャラ${String.fromCharCode(0x3042 + i * 2)}',
        ),
    ];
    final bytes = await buildCardPdf(
      [for (final c in chars) content(c)],
      fonts: testCardFonts,
      compress: false,
    );
    expect(pdfPageCount(bytes), 2);
    expect(String.fromCharCodes(bytes), contains('/MediaBox[0 0 595.27'));
    final texts = pdfTexts(bytes).join('\n');
    for (final c in chars) {
      expect(texts, contains(c.name));
    }
    // Spaces are layout, not glyphs.
    expect(texts, contains('せんにそってきってね'));
  });

  test('compressed output is much smaller than the fonts', () async {
    final bytes = await buildCardPdf([
      for (var i = 0; i < 9; i++)
        content(testCharacter(id: 'c_$i', level: i * 3 + 1)),
    ], fonts: testCardFonts);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, lessThan(1024 * 1024));
  });

  test('empty list is rejected', () {
    expect(
      () => buildCardPdf(const [], fonts: testCardFonts),
      throwsArgumentError,
    );
  });
}
