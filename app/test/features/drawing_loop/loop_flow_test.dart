import 'dart:typed_data';

import 'package:doodle_battle/core/router/app_router.dart';
import 'package:doodle_battle/data/app_state.dart';
import 'package:doodle_battle/data/drawing_loop_storage.dart';
import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/cosmetics.dart';
import 'package:doodle_battle/domain/drawing_analysis_result.dart';
import 'package:doodle_battle/features/draw/drawing_services.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:doodle_battle/features/drawing_loop/effects/move_effect_layer.dart';
import 'package:doodle_battle/features/drawing_loop/odai/daily_odai.dart';
import 'package:doodle_battle/features/drawing_loop/odai/stamp_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../support/fakes.dart';
import '../../support/harness.dart';

/// A distinctive [w]×[h] PNG.
Uint8List pngOf(int w, int h, img.Color c) {
  final i = img.Image(width: w, height: h, numChannels: 4);
  img.fill(i, color: c);
  return Uint8List.fromList(img.encodePng(i));
}

DrawingAnalysisResult withCutout(Uint8List png) {
  final r = fakeAnalysis();
  return DrawingAnalysisResult(
    cutoutPng: png,
    imageHash: r.imageHash,
    features: r.features,
    energy: r.energy,
    skill: r.skill,
    element: r.element,
    baseStats: r.baseStats,
  );
}

Future<void> go(TestApp app, WidgetTester tester, String location) async {
  app.container.read(routerProvider).go(location);
  await tester.pumpAndSettle();
}

Future<void> nameAndSave(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('name-field')), name);
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byKey(const Key('name-save')));
}

void main() {
  group('きょうの おだい', () {
    testWidgets('home shows today\'s theme; drawing for it gives a badge '
        'and a stamp, a plain drawing does not', (tester) async {
      final store = InMemoryDrawingLoopStorage();
      final app = await pumpApp(
        tester,
        overrides: [drawingLoopStorageProvider.overrideWithValue(store)],
      );
      final theme = odaiFor(DateTime(2026, 10, 9)); // harness clock
      expect(find.text('「${theme.text}」'), findsOneWidget);
      expect(find.byKey(const Key('odai-stamped')), findsNothing);

      await tapVisible(tester, find.byKey(const Key('odai-draw')));
      await tapVisible(tester, find.byKey(const Key('draw-camera')));
      await tapVisible(tester, find.byKey(const Key('guide-shoot')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('birth-name')));
      await nameAndSave(tester, 'おだいまる');
      expect(find.text('スタンプ ゲット！'), findsOneWidget);
      await tester.tap(find.byKey(const Key('kid-message-ok')));
      await tester.pumpAndSettle();

      final c = (await app.characters.loadAll()).single;
      expect(c.cosmetics.odai!.date, '2026-10-09');
      expect(c.cosmetics.odai!.text, theme.text);
      // The badge is further down the character page: scroll to it instead
      // of relying on the page height.
      await tester.scrollUntilVisible(
        find.byKey(const Key('loop-odai-badge')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('loop-odai-badge')), findsOneWidget);
      final card = OdaiStampCard.fromJson(store.stampCard);
      expect(card.total, 1);
      expect(card.byDate['2026-10-09']!.characterId, c.id);
      expect(card.byDate['2026-10-09']!.kind, StampKind.character);

      await go(app, tester, '/');
      expect(find.byKey(const Key('odai-stamped')), findsOneWidget);

      // A plain かく afterwards: no badge, no second stamp.
      await tapVisible(tester, find.byKey(const Key('home-draw')));
      await tapVisible(tester, find.byKey(const Key('draw-camera')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('birth-name')));
      await nameAndSave(tester, 'ふつうまる');
      expect(find.text('スタンプ ゲット！'), findsNothing);
      final plain = (await app.characters.loadAll()).firstWhere(
        (x) => x.name == 'ふつうまる',
      );
      expect(plain.cosmetics.isEmpty, isTrue);
      expect(OdaiStampCard.fromJson(store.stampCard).total, 1);

      // The calendar shows the stamp on the 9th and the stamp count.
      await go(app, tester, '/odai');
      expect(find.text('あつめた スタンプ 1 こ'), findsOneWidget);
      expect(find.text('2026ねん 10がつ'), findsOneWidget);
      expect(find.byKey(const Key('stamp-mark-9')), findsOneWidget);
      expect(find.byKey(const Key('stamp-mark-8')), findsNothing);
      await tester.tap(find.byKey(const Key('stamp-day-9')));
      await tester.pumpAndSettle();
      expect(find.text('「${theme.text}」'), findsOneWidget);
      expect(find.text('おだいまる'), findsOneWidget);
      await tester.tap(find.byKey(const Key('kid-message-ok')));
      await tester.pumpAndSettle();
      // No streak / missed-day wording anywhere.
      for (final word in ['れんぞく', 'のこり', 'いそいで', 'わすれ']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      await tester.tap(find.byKey(const Key('stamp-prev')));
      await tester.pumpAndSettle();
      expect(find.text('2026ねん 9がつ'), findsOneWidget);
      expect(find.byKey(const Key('stamp-mark-9')), findsNothing);
    });

    testWidgets('with a full ずかん the theme can be answered with a part', (
      tester,
    ) async {
      final store = InMemoryDrawingLoopStorage();
      final app = await pumpApp(
        tester,
        characters: [
          for (var i = 0; i < 12; i++)
            testCharacter(id: 'c_$i', name: 'き$i', level: 5),
        ],
        overrides: [drawingLoopStorageProvider.overrideWithValue(store)],
      );
      await tapVisible(tester, find.byKey(const Key('odai-draw')));
      expect(find.textContaining('パーツや わざの えを'), findsOneWidget);
      await tester.tap(find.byKey(const Key('kid-message-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('zukan-card-c_0')), findsOneWidget);

      await go(app, tester, '/zukan/c_0/parts/new');
      await tapVisible(tester, find.byKey(const Key('loop-capture')));
      await tapVisible(tester, find.byKey(const Key('part-type-horn')));
      await tapVisible(tester, find.byKey(const Key('part-save')));
      expect(find.text('スタンプ ゲット！'), findsOneWidget);
      final card = OdaiStampCard.fromJson(store.stampCard);
      expect(card.byDate['2026-10-09']!.kind, StampKind.part);
      expect(card.byDate['2026-10-09']!.characterId, 'c_0');
    });
  });

  group('パーツを かきたす', () {
    testWidgets('slots are locked below Lv5; effects are always open', (
      tester,
    ) async {
      final app = await pumpApp(tester, characters: [testCharacter()]);
      await go(app, tester, '/zukan/c_1');
      await tester.scrollUntilVisible(
        find.byKey(const Key('loop-section')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      for (final s in [1, 2, 3]) {
        expect(find.byKey(Key('loop-slot-locked-$s')), findsOneWidget);
      }
      expect(find.text('Lv5'), findsOneWidget);
      expect(find.text('Lv10'), findsOneWidget);
      expect(find.text('Lv20'), findsOneWidget);
      expect(find.byKey(const Key('loop-effect-element')), findsOneWidget);
      expect(find.byKey(const Key('loop-effect-special')), findsOneWidget);
    });

    testWidgets('draw → pick type → place → saved; base kept; removable', (
      tester,
    ) async {
      final store = InMemoryDrawingLoopStorage();
      final base = pngOf(40, 30, img.ColorRgba8(200, 40, 40, 255));
      final app = await pumpApp(
        tester,
        characters: [testCharacter(level: 5)],
        images: {'c_1': base},
        analyzer: FakeAnalyzer(
          result: withCutout(pngOf(20, 20, img.ColorRgba8(20, 40, 220, 255))),
        ),
        overrides: [drawingLoopStorageProvider.overrideWithValue(store)],
      );
      await go(app, tester, '/zukan/c_1');
      await tester.scrollUntilVisible(
        find.byKey(const Key('loop-add-part-1')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('loop-slot-locked-2')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('loop-add-part-1')));
      await tapVisible(tester, find.byKey(const Key('loop-capture')));
      expect(app.imageSource.picked, [PhotoSource.camera]);
      expect(app.analyzer.calls, 1);
      expect(find.text('なにを かいたの？'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('part-type-hat')));

      // Drag it to the right (one finger), then make it bigger.
      final start = tester.getCenter(find.byKey(const Key('part-outline-0')));
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(8, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('part-bigger')));
      await tapVisible(tester, find.byKey(const Key('part-save')));

      var c = (await app.characters.loadAll()).single;
      expect(c.cosmetics.parts.length, 1);
      final part = c.cosmetics.parts.single;
      expect(part.type, PartType.hat);
      expect(part.transform.cx, greaterThan(0.6));
      expect(part.transform.scale, closeTo(0.5 * 1.15, 1e-9));
      expect(c.baseStats.toJson(), testCharacter().baseStats.toJson());
      // Base drawing untouched; part and composite stored separately.
      expect(await app.characters.readImage('c_1'), base);
      final assets = await store.listAssets('c_1');
      expect(assets, contains('part_${part.id}'));
      final display = assets.where((a) => a.startsWith('display_')).single;
      final composite = img.decodePng(
        (await store.readAsset('c_1', display))!,
      )!;
      expect(composite.height, greaterThan(30), reason: 'hat sticks out');
      expect(composite.getPixel(0, 0).a, 0);
      // Slot 1 shows the part, slots 2–3 stay locked at Lv5.
      expect(find.byKey(Key('loop-part-${part.id}')), findsOneWidget);
      expect(find.byKey(const Key('loop-add-part-2')), findsNothing);

      // Remove it again → back to the plain drawing.
      await tapVisible(tester, find.byKey(const Key('loop-edit-parts')));
      await tapVisible(tester, find.byKey(const Key('part-remove')));
      await tapVisible(tester, find.byKey(const Key('kid-ask-yes')));
      await tapVisible(tester, find.byKey(const Key('part-save')));
      c = (await app.characters.loadAll()).single;
      expect(c.cosmetics.parts, isEmpty);
      expect(await store.listAssets('c_1'), isEmpty);
      expect(await app.characters.readImage('c_1'), base);
    });

    testWidgets('a rejected photo is not used and nothing is saved', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        characters: [testCharacter(level: 10)],
        analyzer: FakeAnalyzer(reject: DrawingRejectReason.nearlyEmpty),
      );
      await go(app, tester, '/zukan/c_1/parts/new');
      await tapVisible(tester, find.byKey(const Key('loop-capture')));
      expect(find.text('もうすこし かいてみよう'), findsOneWidget);
      await tester.tap(find.byKey(const Key('kid-message-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('loop-capture')), findsOneWidget);
      expect((await app.characters.loadAll()).single.cosmetics.isEmpty, isTrue);
    });

    testWidgets('releasing a character deletes its loop assets', (
      tester,
    ) async {
      final store = InMemoryDrawingLoopStorage();
      await store.writeAsset('c_1', 'part_p1', testPng());
      final app = await pumpApp(
        tester,
        characters: [testCharacter()],
        overrides: [drawingLoopStorageProvider.overrideWithValue(store)],
      );
      await app.container.read(charactersProvider.notifier).delete('c_1');
      expect(await store.listAssets('c_1'), isEmpty);
    });
  });

  group('わざを かく', () {
    testWidgets('draw an effect, preview it flying, keep it, reset it', (
      tester,
    ) async {
      final store = InMemoryDrawingLoopStorage();
      final app = await pumpApp(
        tester,
        characters: [testCharacter()],
        overrides: [drawingLoopStorageProvider.overrideWithValue(store)],
      );
      await go(app, tester, '/zukan/c_1');
      await tapVisible(tester, find.byKey(const Key('loop-effect-element')));
      expect(find.textContaining('めらめらパンチ'), findsWidgets);
      await tapVisible(tester, find.byKey(const Key('loop-capture')));
      expect(find.byKey(const Key('effect-preview')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('effect-save')));

      var c = (await app.characters.loadAll()).single;
      final asset = c.cosmetics.effects[DrawnMove.element]!;
      expect(asset, startsWith('fx_element_'));
      expect(await store.readAsset('c_1', asset), testPng());
      expect(c.cosmetics.effects.containsKey(DrawnMove.special), isFalse);

      await tapVisible(
        tester,
        find.byKey(const Key('loop-effect-reset-element')),
      );
      await tapVisible(tester, find.byKey(const Key('kid-ask-yes')));
      c = (await app.characters.loadAll()).single;
      expect(c.cosmetics.effects, isEmpty);
      expect(await store.readAsset('c_1', asset), isNull);
    });
  });

  group('battle effect', () {
    test('custom sprite only for the side and move that has one', () {
      final drawn = {
        Side.a: {BattleAction.element: testPng()},
      };
      MoveEffectCue cue(Side s, BattleAction m) =>
          MoveEffectCue(side: s, move: m, tick: 1);
      expect(
        effectSpriteFor(cue(Side.a, BattleAction.element), drawn),
        EffectSprite.custom,
      );
      expect(
        effectSpriteFor(cue(Side.a, BattleAction.special), drawn),
        EffectSprite.fallback,
      );
      expect(
        effectSpriteFor(cue(Side.b, BattleAction.element), drawn),
        EffectSprite.fallback,
      );
      expect(movePlaysEffect(BattleAction.tackle), isFalse);
      expect(movePlaysEffect(BattleAction.guard), isFalse);
      expect(movePlaysEffect(BattleAction.special), isTrue);
    });

    test('motion flies, then bursts and fades', () {
      expect(effectMotion(0).travel, 0);
      expect(effectMotion(0.6).travel, 1);
      expect(effectMotion(0.3).travel, inExclusiveRange(0, 1));
      expect(effectMotion(1).opacity, 0);
      expect(effectMotion(0.5).opacity, 1);
      expect(effectMotion(0.9).scale, greaterThan(effectMotion(0.6).scale));
    });

    Future<Set<String>> playElementMove(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('move-element')));
      final seen = <String>{};
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        for (final k in ['move-effect-custom', 'move-effect-default']) {
          if (find.byKey(Key(k)).evaluate().isNotEmpty) seen.add(k);
        }
      }
      await tester.pumpAndSettle();
      return seen;
    }

    testWidgets('battle uses the drawn effect when there is one', (
      tester,
    ) async {
      final store = InMemoryDrawingLoopStorage();
      final fx = pngOf(12, 12, img.ColorRgba8(10, 200, 10, 255));
      await store.writeAsset('c_1', 'fx_element_1', fx);
      final app = await pumpApp(
        tester,
        characters: [
          testCharacter().copyWith(
            cosmetics: const CharacterCosmetics(
              effects: {DrawnMove.element: 'fx_element_1'},
            ),
          ),
        ],
        battleStep: const Duration(milliseconds: 300),
        overrides: [drawingLoopStorageProvider.overrideWithValue(store)],
      );
      await go(app, tester, '/battle/c_1/stage/1');
      final seen = await playElementMove(tester);
      expect(seen, contains('move-effect-custom'));
      await unmount(tester);
    });

    testWidgets('falls back to the default effect without a drawing', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        characters: [testCharacter()],
        battleStep: const Duration(milliseconds: 300),
      );
      await go(app, tester, '/battle/c_1/stage/1');
      final seen = await playElementMove(tester);
      expect(seen, contains('move-effect-default'));
      expect(seen, isNot(contains('move-effect-custom')));
      await unmount(tester);
    });
  });
}
