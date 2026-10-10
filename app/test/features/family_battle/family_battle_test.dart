import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:doodle_battle/features/family_battle/family_battle_session.dart';
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
      stats: const Stats(hp: 120, atk: 150, def: 110, spd: 140),
    ),
    boost: boostB,
  ),
  sameLevel: sameLevel,
);

/// Plays the hot-seat flow until the winner is shown. Returns the cover
/// texts seen (title, hint) in order.
Future<List<(String, String)>> playFamilyBattle(WidgetTester tester) async {
  final covers = <(String, String)>[];
  var steps = 0;
  while (find.byKey(const Key('family-result-title')).evaluate().isEmpty) {
    expect(steps++, lessThan(200), reason: 'battle should end');
    final cover = find.byKey(const Key('family-cover'));
    if (cover.evaluate().isNotEmpty) {
      // Nothing to choose while the screen is covered.
      expect(find.byKey(const Key('move-tackle')), findsNothing);
      covers.add((
        tester.widget<Text>(find.byKey(const Key('family-cover-title'))).data!,
        tester.widget<Text>(find.byKey(const Key('family-cover-hint'))).data!,
      ));
      await tester.tap(find.byKey(const Key('family-cover-continue')));
      await tester.pumpAndSettle();
      continue;
    }
    final special = find.byKey(const Key('move-special'));
    final ready = tester.widget<ButtonStyleButton>(special).enabled;
    await tester.tap(ready ? special : find.byKey(const Key('move-element')));
    await tester.pumpAndSettle();
  }
  return covers;
}

void main() {
  group('handicap', () {
    test('おなじ レベル raises the lower level to the higher one', () {
      final c = config();
      expect(c.battleLevel(testSpec, Side.a), 5);
      expect(c.battleLevel(testSpec, Side.b), 5);
      final off = config(sameLevel: false);
      expect(off.battleLevel(testSpec, Side.a), 1);
      expect(off.battleLevel(testSpec, Side.b), 5);
    });

    test('manual boost on top, capped at the max level', () {
      final c = config(boostA: 10);
      expect(c.battleLevel(testSpec, Side.a), 15);
      expect(c.battleLevel(testSpec, Side.b), 5);
      final capped = config(levelA: 28, levelB: 3, boostA: 10, boostB: 5);
      expect(capped.battleLevel(testSpec, Side.a), testSpec.growth.maxLevel);
      expect(capped.battleLevel(testSpec, Side.b), testSpec.growth.maxLevel);
    });

    test('setups are ordinary engine setups at the battle level', () {
      final c = config(boostA: 3, skillA: 90);
      final a = c.setup(testSpec, Side.a);
      expect(a.level, 8);
      // Same growth rules as the character itself (its own growth rate,
      // spent seeds) — only the level changes.
      expect(
        a.stats,
        statsAtLevel(
          testSpec,
          c.a.character.baseStats,
          8,
          c.a.character.seedAllocations,
          isShobo: isShoboSkill(testSpec, 90),
        ),
      );
      expect(a.stats, currentStats(testSpec, c.a.character.copyWith(level: 8)));
      final b = c.setup(testSpec, Side.b);
      expect(b.stats, currentStats(testSpec, c.b.character));
      expect(b.level, 5);
    });

    test('mirror match names carry the team colour', () {
      final c = config();
      expect(c.fighterName(Side.a), 'ねこまる');
      final mirror = c.copyWith(b: c.b.copyWith(character: c.a.character));
      expect(mirror.fighterName(Side.a), 'ねこまる（あか）');
      expect(mirror.fighterName(Side.b), 'ねこまる（あお）');
    });
  });

  test('session: a picks, then b, then the engine resolves', () {
    final c = config();
    final s = FamilyBattleSession(spec: testSpec, config: c, seed: 9);
    final reference = FamilyBattleSession(spec: testSpec, config: c, seed: 9);
    var state = initBattle(
      testSpec,
      c.setup(testSpec, Side.a),
      c.setup(testSpec, Side.b),
    );
    expect(s.state, state);
    final rng = Mulberry32(deriveSeed(9, 0));
    while (!s.isOver) {
      expect(s.picker, Side.a);
      expect(s.pick(BattleAction.tackle), isNull);
      expect(s.picker, Side.b);
      final events = s.pick(BattleAction.element);
      final r = resolveTurn(
        testSpec,
        state,
        BattleAction.tackle,
        BattleAction.element,
        rng,
      );
      state = r.state;
      expect(events, r.events);
      expect(s.state, state);
      reference
        ..pick(BattleAction.tackle)
        ..pick(BattleAction.element);
    }
    expect(reference.state, s.state);
    expect(() => s.pick(BattleAction.tackle), throwsStateError);
  });

  testWidgets('full hot-seat battle: cover screens, handicap, no XP', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      characters: [
        testCharacter(id: 'c_1', name: 'ねこまる', level: 1),
        testCharacter(
          id: 'c_2',
          name: 'いぬまる',
          level: 5,
          stats: const Stats(hp: 120, atk: 150, def: 110, spd: 140),
        ),
      ],
    );
    await tapVisible(tester, find.byKey(const Key('home-family')));

    // Defaults: newest for あか, the previous one for あお; おなじ レベル on.
    expect(
      tester.widget<Text>(find.byKey(const Key('family-char-a'))).data,
      'いぬまる',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('family-char-b'))).data,
      'ねこまる',
    );
    Text level(Side s) =>
        tester.widget<Text>(find.byKey(Key('family-level-${s.name}')));
    expect(level(Side.a).data, 'Lv5');
    expect(level(Side.b).data, 'Lv5');

    // Swap: あか takes ねこまる (Lv1) with a ハンデ of +3, あお いぬまる (Lv5).
    await tapVisible(tester, find.byKey(const Key('family-pick-a')));
    await tester.tap(find.byKey(const Key('family-option-c_1')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('family-pick-b')));
    await tester.tap(find.byKey(const Key('family-option-c_2')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('family-boost-a-3')));
    expect(level(Side.a).data, 'Lv8');
    expect(level(Side.b).data, 'Lv5');
    // Without おなじ レベル: own level + boost.
    await tapVisible(tester, find.byKey(const Key('family-same-level')));
    expect(level(Side.a).data, 'Lv4');
    await tapVisible(tester, find.byKey(const Key('family-same-level')));
    expect(level(Side.a).data, 'Lv8');

    await tester.scrollUntilVisible(
      find.byKey(const Key('family-no-xp-note')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapVisible(tester, find.byKey(const Key('family-start')));

    // First cover: あか's turn, あお looks away; no moves visible.
    expect(find.text('あか チームの ばん！'), findsOneWidget);
    expect(find.text('あお チームは みないでね'), findsOneWidget);
    expect(find.byKey(const Key('move-tackle')), findsNothing);
    await tester.tap(find.byKey(const Key('family-cover-continue')));
    await tester.pumpAndSettle();

    // Handicap applied in the engine: Lv8 / Lv5 and HP from statsAtLevel.
    expect(find.text('Lv8'), findsOneWidget);
    expect(find.text('Lv5'), findsOneWidget);
    final hpA =
        statsAtLevel(
          testSpec,
          const Stats(hp: 140, atk: 140, def: 120, spd: 130),
          8,
          const {},
          isShobo: false,
        ).hp *
        testSpec.hpMultiplier;
    expect(find.text('$hpA / $hpA'), findsOneWidget);
    expect(find.text('あか チーム: わざを えらんでね'), findsOneWidget);

    await tester.tap(find.byKey(const Key('move-tackle')));
    await tester.pumpAndSettle();
    // Second cover: あお's turn, あか looks away.
    expect(find.text('あお チームの ばん！'), findsOneWidget);
    expect(find.text('あか チームは みないでね'), findsOneWidget);
    await tester.tap(find.byKey(const Key('family-cover-continue')));
    await tester.pumpAndSettle();
    expect(find.text('あお チーム: わざを えらんでね'), findsOneWidget);
    await tester.tap(find.byKey(const Key('move-guard')));
    await tester.pumpAndSettle();
    // Turn resolved and animated; next turn starts with あか's cover.
    expect(find.text('2 ターンめ'), findsOneWidget);
    expect(find.text('あか チームの ばん！'), findsOneWidget);

    final covers = await playFamilyBattle(tester);
    // Covers always alternate あか → あお.
    for (final (i, (title, hint)) in covers.indexed) {
      expect(title, i.isEven ? 'あか チームの ばん！' : 'あお チームの ばん！');
      expect(hint, i.isEven ? 'あお チームは みないでね' : 'あか チームは みないでね');
    }
    expect(find.textContaining('の かち！'), findsOneWidget);
    expect(find.textContaining('けいけんち'), findsNothing);

    // No XP, no level change for either character.
    final saved = await app.characters.loadAll();
    expect([for (final c in saved) (c.level, c.xp)], [(1, 0), (5, 0)]);

    // もういちど: a fresh battle with the same setup.
    await tapVisible(tester, find.byKey(const Key('family-rematch')));
    expect(find.text('1 ターンめ'), findsOneWidget);
    expect(find.text('あか チームの ばん！'), findsOneWidget);
    await tester.tap(find.byKey(const Key('family-cover-continue')));
    await tester.pumpAndSettle();
    expect(find.text('Lv8'), findsOneWidget);
    // Leave mid-battle via back → setup still holds the choices.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(level(Side.a).data, 'Lv8');
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

    await tapVisible(tester, find.byKey(const Key('family-start')));
    expect(find.text('おとうさんの ばん！'), findsOneWidget);
    expect(find.text('いもうとは みないでね'), findsOneWidget);
    await tester.tap(find.byKey(const Key('family-cover-continue')));
    await tester.pumpAndSettle();
    expect(find.text('ねこまる（あか）'), findsOneWidget);
    expect(find.text('ねこまる（あお）'), findsOneWidget);

    final covers = await playFamilyBattle(tester);
    expect(covers.first, ('いもうとの ばん！', 'おとうさんは みないでね'));
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
