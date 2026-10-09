import 'dart:math';

import 'package:doodle_battle/core/theme/app_theme.dart';
import 'package:doodle_battle/features/parental_gate/parental_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the shown question 「a × b ＝ ？」 and returns the answer.
int answerOnScreen(WidgetTester tester) {
  final text = tester
      .widget<Text>(find.byKey(const Key('gate-question')))
      .data!;
  final m = RegExp(r'(\d+) × (\d+)').firstMatch(text)!;
  return int.parse(m[1]!) * int.parse(m[2]!);
}

Future<void> holdGate(WidgetTester tester, Duration d) async {
  final g = await tester.startGesture(
    tester.getCenter(find.byKey(const Key('gate-hold'))),
  );
  await tester.pump(); // first frame starts the ticker
  for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 250)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await g.up();
  await tester.pump();
}

Future<void> typeAnswer(WidgetTester tester, int answer) async {
  for (final ch in '$answer'.split('')) {
    await tester.ensureVisible(find.byKey(Key('gate-key-$ch')));
    await tester.tap(find.byKey(Key('gate-key-$ch')));
    await tester.pump();
  }
  await tester.ensureVisible(find.byKey(const Key('gate-ok')));
  await tester.tap(find.byKey(const Key('gate-ok')));
  await tester.pumpAndSettle();
}

/// Passes a real gate dialog that is currently shown.
Future<void> passGate(WidgetTester tester) async {
  await holdGate(tester, parentalGateHold + const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
  await typeAnswer(tester, answerOnScreen(tester));
}

void main() {
  group('challenge', () {
    test('kanji numerals', () {
      expect(kanjiNumber(7), '七');
      expect(kanjiNumber(10), '十');
      expect(kanjiNumber(23), '二十三');
      expect(kanjiNumber(99), '九十九');
      expect(kanjiNumber(105), '百五');
      expect(kanjiNumber(891), '八百九十一');
    });

    test('random questions are 2-digit × 1-digit, never trivial', () {
      final r = Random(1);
      for (var i = 0; i < 500; i++) {
        final c = ParentalGateChallenge.random(r);
        expect(c.a, inInclusiveRange(11, 99));
        expect(c.a % 10, isNot(0));
        expect(c.b, inInclusiveRange(3, 9));
        expect(c.check('${c.a * c.b}'), isTrue);
        expect(c.check('${c.a * c.b + 1}'), isFalse);
      }
      const c = ParentalGateChallenge(23, 7);
      expect(c.digitsText, '23 × 7 ＝ ？');
      expect(c.kanjiText, '二十三 かける 七');
    });
  });

  group('dialog', () {
    late bool? result;

    Future<void> open(WidgetTester tester) async {
      result = null;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final gate = DialogParentalGate(random: Random(3));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async => result = await gate.verify(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a short press does not unlock', (tester) async {
      await open(tester);
      await holdGate(tester, const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gate-question')), findsNothing);
      // Releasing early resets the progress: another 2 s is still not enough.
      await holdGate(tester, const Duration(seconds: 2));
      expect(find.byKey(const Key('gate-question')), findsNothing);
    });

    testWidgets('3 s hold then the right answer passes', (tester) async {
      await open(tester);
      await holdGate(
        tester,
        parentalGateHold + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gate-question')), findsOneWidget);
      expect(find.byKey(const Key('gate-question-kanji')), findsOneWidget);
      await typeAnswer(tester, answerOnScreen(tester));
      expect(result, isTrue);
    });

    testWidgets('three wrong answers close the gate', (tester) async {
      await open(tester);
      await holdGate(
        tester,
        parentalGateHold + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await typeAnswer(tester, answerOnScreen(tester) + 1);
        expect(find.text('答えが違います。もう一度どうぞ。'), findsOneWidget);
      }
      await typeAnswer(tester, answerOnScreen(tester) + 1);
      expect(result, isFalse);
      expect(find.byType(ParentalGateDialog), findsNothing);
    });

    testWidgets('cancel returns false', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('gate-cancel')));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('backspace edits the answer', (tester) async {
      await open(tester);
      await passGateWithTypo(tester);
      expect(result, isTrue);
    });
  });
}

Future<void> passGateWithTypo(WidgetTester tester) async {
  await holdGate(tester, parentalGateHold + const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
  final answer = answerOnScreen(tester);
  await tester.ensureVisible(find.byKey(const Key('gate-key-←')));
  await tester.tap(find.byKey(const Key('gate-key-9')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('gate-key-←')));
  await tester.pump();
  await typeAnswer(tester, answer);
}
