import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/features/battle_stage/stage_overlay.dart';
import 'package:doodle_battle/features/battle_ui/battle_outcome.dart';
import 'package:doodle_battle/features/monetization/monetization_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

/// ホーム → バトル → キャラ → ワールド → ステージ.
Future<void> openStage(WidgetTester tester, int stage) async {
  await tapVisible(tester, find.byKey(const Key('home-battle')));
  await tapVisible(tester, find.byKey(const Key('select-c_1')));
  await tapVisible(tester, find.byKey(Key('world-${(stage - 1) ~/ 10 + 1}')));
  // The battle animates forever: no pumpAndSettle after this tap.
  await tapNoSettle(tester, find.byKey(Key('stage-$stage')));
}

void main() {
  test('stars: win, HP ≥ 50 %, within 60 s', () {
    expect(stageStars(won: false, hp: 100, maxHp: 100, ticks: 10), 0);
    expect(stageStars(won: true, hp: 10, maxHp: 100, ticks: 900), 1);
    expect(stageStars(won: true, hp: 50, maxHp: 100, ticks: 900), 2);
    expect(stageStars(won: true, hp: 50, maxHp: 100, ticks: 600), 3);
  });

  testWidgets('10 worlds × 10 stages: locks, stars and the boss', (
    tester,
  ) async {
    await pumpApp(
      tester,
      characters: [testCharacter()],
      progress: const GameProgress(
        clearedStage: 10,
        stageStars: {1: 3, 2: 2, 10: 1},
      ),
    );
    await tapVisible(tester, find.byKey(const Key('home-battle')));
    await tapVisible(tester, find.byKey(const Key('select-c_1')));
    expect(find.text(kWorldNames.first), findsOneWidget);
    expect(find.byKey(const Key('world-stars-1')), findsOneWidget);
    expect(find.text('6 / 30'), findsOneWidget);
    // World 2 opens after the world-1 boss; world 3 is still locked.
    expect(find.text(kWorldNames[1]), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('world-3')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(kWorldNames[2]), findsNothing);
    await tapVisible(tester, find.byKey(const Key('world-1')));
    expect(find.byKey(const Key('stage-1')), findsOneWidget);
    final stars = find.descendant(
      of: find.byKey(const Key('stage-stars-1')),
      matching: find.byIcon(Icons.star),
    );
    expect(stars, findsNWidgets(3));
    await tester.scrollUntilVisible(
      find.byKey(const Key('stage-10')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('stage-10')),
        matching: find.byIcon(Icons.workspace_premium),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a locked stage cannot be opened', (tester) async {
    await pumpApp(
      tester,
      characters: [testCharacter()],
      progress: const GameProgress(clearedStage: 2),
    );
    await tapVisible(tester, find.byKey(const Key('home-battle')));
    await tapVisible(tester, find.byKey(const Key('select-c_1')));
    await tapVisible(tester, find.byKey(const Key('world-1')));
    await tapVisible(tester, find.byKey(const Key('stage-4')));
    expect(find.byKey(const Key('stage-4')), findsOneWidget); // still here
  });

  testWidgets('ATB battle: さきどり, unlocked moves, おまかせ, XP and stars', (
    tester,
  ) async {
    final app = await pumpApp(tester, characters: [testCharacter(level: 10)]);
    await openStage(tester, 1);
    await settleReal(tester, rounds: 10);
    // Lv10: three moves, ひっさつ locked until Lv50.
    expect(find.byKey(const Key('move-0')), findsOneWidget);
    expect(find.byKey(const Key('move-2')), findsOneWidget);
    expect(find.byKey(const Key('move-3')), findsNothing);
    expect(find.byType(LockedMoveSlot), findsOneWidget);
    // さきどり: pick while the gauge is still filling.
    await tester.tap(find.byKey(const Key('move-1')));
    await tester.pump();
    expect(
      tester.widget<MoveButton>(find.byKey(const Key('move-1'))).selected,
      isTrue,
    );
    // おまかせ is remembered for the next battle.
    await tester.tap(find.byType(OmakaseToggle));
    await tester.pump();
    await playBattle(tester);
    expect(find.text('かった！'), findsOneWidget);
    expect(app.settingsRepo.progress.omakase, isTrue);
    // Win, stage 1 at Lv10, first clear ×2 = 200 XP (stays Lv10).
    expect(find.text('けいけんち +200'), findsOneWidget);
    final c = (await app.characters.loadAll()).single;
    expect((c.level, c.xp), (10, 200));
    expect(app.settingsRepo.progress.clearedStage, 1);
    expect(app.settingsRepo.progress.starsOf(1), inInclusiveRange(1, 3));
    expect(find.byKey(const Key('result-stars')), findsOneWidget);
    // Ads are not allowed by default: no ad button.
    expect(find.byKey(const Key('ad-double-xp')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('result-home')));
    expect(find.byKey(const Key('home-draw')), findsOneWidget);
  });

  testWidgets('Lv10: new move celebrated, its name asked from the cloud', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..moveProposal = {
        'template': 'blast',
        'attribute': 'none',
        'name': 'きらきらビーム',
        'vfx': 'beam',
        'colour': 'yellow',
        'atkFormula': 'INT80_DEX20',
        'power': 100,
        'hits': 1,
        'accuracy': 100,
        'critBonus': 0,
        'spCost': 20,
        'castTicks': 6,
        'cooldownTicks': 40,
      };
    final app = await pumpApp(
      tester,
      backend: backend,
      characters: [testCharacter(level: 9, xp: 299)],
      settings: setupDone.copyWith(
        consents: const ParentConsents(cloudJudge: true),
      ),
    );
    await openStage(tester, 1);
    await playBattle(tester);
    expect(find.byKey(const Key('result-levelup')), findsOneWidget);
    expect(find.byKey(const Key('result-newmove-2')), findsOneWidget);
    expect(find.byKey(const Key('result-evo-kagayaki')), findsOneWidget);
    expect(backend.generated.single.slot, 2);
    expect(find.textContaining('きらきらビーム'), findsOneWidget);
    final c = (await app.characters.loadAll()).single;
    expect(c.level, 10);
    expect(c.allMoves()[2].name, 'きらきらビーム');
  });

  testWidgets('Lv50 しんか looks the same for every character', (tester) async {
    // skill 90 = the hidden late bloomer (internal); the screen must not
    // differ from an ordinary character's Lv50 evolution.
    for (final skill in [20.0, 90.0]) {
      final app = await pumpApp(
        tester,
        characters: [testCharacter(level: 49, xp: 2839, skill: skill)],
      );
      await openStage(tester, 1);
      await playBattle(tester);
      expect(find.byKey(const Key('result-evo-densetsu')), findsOneWidget);
      expect(find.byKey(const Key('result-newmove-3')), findsOneWidget);
      expect(find.textContaining('しんか！'), findsOneWidget);
      for (final w in ['たいき', 'ばんせい', 'うまれかわ', 'ほんとう', 'ひみつ']) {
        expect(find.textContaining(w), findsNothing);
      }
      expect((await app.characters.loadAll()).single.level, 50);
      await unmount(tester);
    }
  });

  testWidgets('rewarded ad (allowed, Android): notice first, then XP ×2', (
    tester,
  ) async {
    final monetization = FakeMonetization();
    final app = await pumpApp(
      tester,
      monetization: monetization,
      characters: [testCharacter(level: 10)],
      settings: setupDone.copyWith(consents: const ParentConsents(ads: true)),
    );
    await openStage(tester, 1);
    await playBattle(tester);
    await tapVisible(tester, find.byKey(const Key('ad-double-xp')));
    expect(find.textContaining('おうちのひとに きいてから みてね'), findsOneWidget);
    expect(monetization.adsShown, 0);
    await tester.tap(find.byKey(const Key('kid-ask-yes')));
    await tester.pumpAndSettle();
    expect(monetization.adsShown, 1);
    expect(find.text('けいけんち +400'), findsOneWidget);
    final c = (await app.characters.loadAll()).single;
    // 400 XP at Lv10 (335 needed): Lv11 with 65 left.
    expect((c.level, c.xp), (11, 65));
  });

  testWidgets('no ads at all where the build has none (iPhone)', (
    tester,
  ) async {
    await pumpApp(
      tester,
      adsSupported: false,
      characters: [testCharacter(level: 10)],
      settings: setupDone.copyWith(consents: const ParentConsents(ads: true)),
    );
    await openStage(tester, 1);
    await playBattle(tester);
    expect(find.byKey(const Key('ad-double-xp')), findsNothing);
  });

  testWidgets('losing still gives XP and no way forward', (tester) async {
    final app = await pumpApp(
      tester,
      characters: [testCharacter()],
      progress: const GameProgress(clearedStage: 29),
    );
    await openStage(tester, 30);
    await playBattle(tester);
    expect(find.text('まけちゃった…'), findsOneWidget);
    // lose 40 × (100 + 4·29) % = 86
    expect(find.text('けいけんち +86'), findsOneWidget);
    expect(app.settingsRepo.progress.clearedStage, 29);
    expect(find.byKey(const Key('result-next')), findsNothing);
    expect(find.byKey(const Key('result-retry')), findsOneWidget);
  });

  test('Product ids are stable', () {
    expect(Product.values.map((p) => p.id), [
      'slots_24',
      'frame_pack_1',
      'no_ads_pass',
    ]);
  });
}
