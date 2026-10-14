import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/features/battle_stage/stage_overlay.dart';
import 'package:doodle_battle/features/family_battle/family_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

FamilyBattleConfig config({
  int levelA = 1,
  int levelB = 5,
  bool sameLevel = true,
  int boostA = 0,
  int boostB = 0,
  double skillA = 20,
}) => FamilyBattleConfig(
  a: FamilyPlayer(
    label: 'あか チーム',
    character: testCharacter(
      id: 'a',
      name: 'ねこまる',
      level: levelA,
      skill: skillA,
    ),
    boost: boostA,
  ),
  b: FamilyPlayer(
    label: 'あお チーム',
    character: testCharacter(
      id: 'b',
      name: 'いぬまる',
      level: levelB,
      energy: 70,
      features: const {'inkCoverage': 0.2, 'roundness': 0.8},
    ),
    boost: boostB,
  ),
  sameLevel: sameLevel,
);

void main() {
  const spec = V3Spec();

  group('handicap', () {
    test('おなじ レベル raises the lower level to the higher one', () {
      final c = config();
      expect(c.battleLevel(FamilySide.a), 5);
      expect(c.battleLevel(FamilySide.b), 5);
      final off = config(sameLevel: false);
      expect(off.battleLevel(FamilySide.a), 1);
      expect(off.battleLevel(FamilySide.b), 5);
    });

    test('manual boost on top, capped at the max level', () {
      final c = config(boostA: 10);
      expect(c.battleLevel(FamilySide.a), 15);
      expect(c.battleLevel(FamilySide.b), 5);
      final capped = config(levelA: 98, levelB: 3, boostA: 10, boostB: 5);
      expect(capped.battleLevel(FamilySide.a), spec.maxLevel);
      expect(capped.battleLevel(FamilySide.b), spec.maxLevel);
    });

    test('battleLevel is familyBattleLevel', () {
      final c = config(boostA: 3);
      expect(
        c.battleLevel(FamilySide.a),
        familyBattleLevel(
          spec,
          ownLevel: 1,
          otherLevel: 5,
          sameLevel: true,
          boost: 3,
        ),
      );
    });

    test('setups are ordinary engine setups at the battle level', () {
      final c = config(boostA: 3);
      final a = c.setup(FamilySide.a);
      // The character as it would be at Lv8: own growth, Lv8 slots.
      expect(a.stats, c.a.character.copyWith(level: 8).stats());
      expect(a.moves.length, unlockedSlots(spec, 8));
      final b = c.setup(FamilySide.b);
      expect(b.stats, c.b.character.stats());
    });

    test('a hidden late bloomer keeps its form even when boosted', () {
      // Lv45 + 10 = Lv55 battle level, but its real level is below 50:
      // the family battle must not reveal the Lv50 rebuild early.
      final c = config(levelA: 45, levelB: 45, skillA: 90, boostA: 10);
      final boosted = c.setup(FamilySide.a);
      final real = c.a.character.copyWith(level: 55).battleSetup();
      expect(boosted.stats, isNot(real.stats));
    });

    test('mirror match names carry the team colour', () {
      final c = config();
      expect(c.fighterName(FamilySide.a), 'ねこまる');
      final mirror = c.copyWith(b: c.b.copyWith(character: c.a.character));
      expect(mirror.fighterName(FamilySide.a), 'ねこまる（あか）');
      expect(mirror.fighterName(FamilySide.b), 'ねこまる（あお）');
    });
  });

  testWidgets('ATB family battle: both sides play, handicap, no XP', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      characters: [
        testCharacter(id: 'c_1', name: 'ねこまる', level: 1),
        testCharacter(id: 'c_2', name: 'いぬまる', level: 5, energy: 70),
      ],
    );
    await tapVisible(tester, find.byKey(const Key('home-family')));

    // Defaults: newest for あか, the previous one for あお; おなじ レベル on.
    expect(
      tester.widget<Text>(find.byKey(const Key('family-char-a'))).data,
      'いぬまる',
    );
    Text level(FamilySide s) =>
        tester.widget<Text>(find.byKey(Key('family-level-${s.name}')));
    expect(level(FamilySide.a).data, 'Lv5');
    expect(level(FamilySide.b).data, 'Lv5');

    // Swap: あか takes ねこまる (Lv1) with a ハンデ of +3, あお いぬまる (Lv5).
    await tapVisible(tester, find.byKey(const Key('family-pick-a')));
    await tester.tap(find.byKey(const Key('family-option-c_1')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('family-pick-b')));
    await tester.tap(find.byKey(const Key('family-option-c_2')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('family-boost-a-3')));
    expect(level(FamilySide.a).data, 'Lv8');
    await tapVisible(tester, find.byKey(const Key('family-same-level')));
    expect(level(FamilySide.a).data, 'Lv4');
    await tapVisible(tester, find.byKey(const Key('family-same-level')));
    expect(level(FamilySide.a).data, 'Lv8');
    await tester.scrollUntilVisible(
      find.byKey(const Key('family-no-xp-note')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapNoSettle(tester, find.byKey(const Key('family-start')));
    await settleReal(tester, rounds: 10);

    // Both players have their own move pad (あお's is upside down on top).
    expect(find.byKey(const Key('family-controls-a')), findsOneWidget);
    expect(find.byKey(const Key('family-controls-b')), findsOneWidget);
    expect(find.byType(RotatedBox), findsWidgets);
    expect(find.byType(MovePad), findsNWidgets(2));
    // Handicap applied: Lv8 / Lv5 in the status panels.
    expect(find.text('Lv8'), findsOneWidget);
    expect(find.text('Lv5'), findsOneWidget);
    // さきどり for both.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('family-controls-a')),
        matching: find.byKey(const Key('move-1')),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('family-controls-b')),
        matching: find.byKey(const Key('move-0')),
      ),
    );
    await tester.pump();

    await playBattle(
      tester,
      done: find.byKey(const Key('family-result-title')),
    );
    expect(find.textContaining('の かち！'), findsOneWidget);
    expect(find.textContaining('けいけんち'), findsNothing);
    // No XP, no level change for either character.
    final saved = await app.characters.loadAll();
    expect([for (final c in saved) (c.level, c.xp)], [(1, 0), (5, 0)]);

    // もういちど: a fresh battle with the same setup.
    await tapNoSettle(tester, find.byKey(const Key('family-rematch')));
    await settleReal(tester, rounds: 10);
    expect(find.text('Lv8'), findsOneWidget);
    expect(find.byKey(const Key('family-controls-b')), findsOneWidget);
  });

  testWidgets('one character: mirror match with family names', (tester) async {
    await pumpApp(
      tester,
      characters: [testCharacter(id: 'c_1', name: 'ねこまる', level: 3)],
    );
    await tapVisible(tester, find.byKey(const Key('home-family')));
    expect(
      tester.widget<Text>(find.byKey(const Key('family-char-a'))).data,
      'ねこまる',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('family-char-b'))).data,
      'ねこまる',
    );
    await tapVisible(tester, find.byKey(const Key('family-name-a')));
    await tester.tap(find.byKey(const Key('family-label-option-おとうさん')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('family-name-b')));
    await tester.tap(find.byKey(const Key('family-label-option-いもうと')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('family-boost-b-10')));
    expect(
      tester.widget<Text>(find.byKey(const Key('family-level-b'))).data,
      'Lv13',
    );

    await tapNoSettle(tester, find.byKey(const Key('family-start')));
    await settleReal(tester, rounds: 10);
    expect(find.text('おとうさん: ねこまる（あか）'), findsOneWidget);
    expect(find.text('いもうと: ねこまる（あお）'), findsOneWidget);

    await playBattle(
      tester,
      done: find.byKey(const Key('family-result-title')),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'おとうさんの かち！' || w.data == 'いもうとの かち！'),
      ),
      findsOneWidget,
    );
    await tapVisible(tester, find.byKey(const Key('family-exit')));
    expect(find.byKey(const Key('home-family')), findsOneWidget);
  });

  testWidgets('no characters: asks to draw first', (tester) async {
    await pumpApp(tester);
    await tapVisible(tester, find.byKey(const Key('home-family')));
    expect(find.text('まずは えを かいて キャラを つくろう！'), findsOneWidget);
    expect(find.byKey(const Key('family-start')), findsNothing);
  });
}
