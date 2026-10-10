import 'dart:typed_data';

import 'package:doodle_battle/features/card_print/card_output.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';
import 'card_pdf_test.dart' show testCardFonts;
import 'pdf_text.dart';

class FakeCardOutput implements CardOutput {
  final printed = <Uint8List>[];
  final shared = <(Uint8List, String)>[];
  bool fail = false;

  @override
  Future<void> printPdf(Uint8List pdf, {required String name}) async {
    if (fail) throw Exception('no printer');
    printed.add(pdf);
  }

  @override
  Future<void> sharePdf(Uint8List pdf, {required String filename}) async {
    if (fail) throw Exception('no share');
    shared.add((pdf, filename));
  }
}

Future<(TestApp, FakeCardOutput)> pumpCards(
  WidgetTester tester, {
  FakeGate? gate,
  int count = 2,
}) async {
  final out = FakeCardOutput();
  final app = await pumpApp(
    tester,
    gate: gate,
    characters: [
      for (var i = 1; i <= count; i++)
        testCharacter(id: 'c_$i', name: 'キャラ$i', level: i * 4),
    ],
    wrap: (child) => ProviderScope(
      overrides: [
        cardOutputProvider.overrideWithValue(out),
        cardFontsProvider.overrideWithValue(AsyncData(testCardFonts)),
      ],
      child: child,
    ),
  );
  return (app, out);
}

void main() {
  testWidgets('detail → カードに する → print behind the parental gate', (
    tester,
  ) async {
    final gate = FakeGate();
    final (_, out) = await pumpCards(tester, gate: gate);
    await tapVisible(tester, find.byKey(const Key('home-zukan')));
    await tapVisible(tester, find.byKey(const Key('zukan-card-c_1')));
    await tapVisible(tester, find.byKey(const Key('detail-card')));

    expect(find.byKey(const Key('card-preview-0')), findsOneWidget);
    expect(find.byKey(const Key('card-preview-1')), findsNothing);
    // Preview: name, Lv, stars — no raw stat numbers, nothing about skill.
    expect(find.text('キャラ1'), findsWidgets);
    expect(find.text('Lv4'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(20));
    expect(find.textContaining('140'), findsNothing);
    expect(find.textContaining('じょうず'), findsNothing);

    // Gate refused: nothing leaves the app.
    gate.pass = false;
    await tapVisible(tester, find.byKey(const Key('card-print')));
    expect(gate.calls, 1);
    expect(out.printed, isEmpty);

    gate.pass = true;
    await tapVisible(tester, find.byKey(const Key('card-print')));
    expect(gate.calls, 2);
    expect(out.printed, hasLength(1));
    expect(String.fromCharCodes(out.printed.single.take(5)), '%PDF-');
  });

  testWidgets('ずかん multi-select (max 9) → A4 / single share', (tester) async {
    final gate = FakeGate();
    final (_, out) = await pumpCards(tester, gate: gate, count: 10);
    await tapVisible(tester, find.byKey(const Key('home-zukan')));
    await tapVisible(tester, find.byKey(const Key('zukan-cards')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('card-select-next')))
          .onPressed,
      isNull,
    );
    for (var i = 1; i <= 10; i++) {
      await tapVisible(tester, find.byKey(Key('card-select-c_$i')));
    }
    // The 10th was refused.
    expect(find.text('えらんでね  9 / 9'), findsOneWidget);
    expect(find.text('1まいの かみに 9まいまで だよ'), findsOneWidget);
    // Deselect one again.
    await tapVisible(tester, find.byKey(const Key('card-select-c_2')));
    expect(find.text('えらんでね  8 / 9'), findsOneWidget);
    // Let the snack bar go away (it sits over the button).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('card-select-next')));

    for (var i = 0; i < 8; i++) {
      expect(find.byKey(Key('card-preview-$i')), findsOneWidget);
    }

    // A4 (default): one page with the eight names.
    await tapVisible(tester, find.byKey(const Key('card-share')));
    expect(gate.calls, 1);
    expect(out.shared, hasLength(1));
    final (pdf, filename) = out.shared.single;
    expect(filename, 'oekaki_fighters_cards_20261009.pdf');
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

    // 1まいずつ: one card-sized page each.
    await tapVisible(tester, find.text('1まいずつ'));
    await tapVisible(tester, find.byKey(const Key('card-share')));
    expect(gate.calls, 2);
    expect(out.shared, hasLength(2));
    expect(
      String.fromCharCodes(out.shared.last.$1),
      contains('/MediaBox[0 0 178.58'),
    );
  });

  testWidgets('output failure shows a gentle message', (tester) async {
    final (_, out) = await pumpCards(tester, count: 1);
    out.fail = true;
    await tapVisible(tester, find.byKey(const Key('home-zukan')));
    await tapVisible(tester, find.byKey(const Key('zukan-card-c_1')));
    await tapVisible(tester, find.byKey(const Key('detail-card')));
    await tapVisible(tester, find.byKey(const Key('card-print')));
    expect(find.text('うまく できなかったよ。もういちど ためしてね'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kid-message-ok')));
    await tester.pumpAndSettle();
    // Buttons usable again.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('card-print')))
          .onPressed,
      isNotNull,
    );
  });

  test('pdfPageCount sanity', () {
    expect(pdfPageCount(Uint8List(0)), 0);
  });
}
