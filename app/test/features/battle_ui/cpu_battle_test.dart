import 'package:doodle_battle/data/app_settings.dart';
import 'package:doodle_battle/data/game_progress.dart';
import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:doodle_battle/features/battle_ui/battle_display.dart';
import 'package:doodle_battle/features/battle_ui/cpu_battle_session.dart';
import 'package:doodle_battle/features/battle_ui/cpu_display.dart';
import 'package:doodle_battle/features/monetization/monetization_service.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import '../../support/harness.dart';

Future<void> openStage(WidgetTester tester, int stage) async {
  await tapVisible(tester, find.byKey(const Key('home-battle')));
  await tapVisible(tester, find.byKey(const Key('select-c_1')));
  await tapVisible(tester, find.byKey(Key('stage-$stage')));
}

void main() {
  test('session: deterministic for a seed and matches the engine', () {
    final stage = testSpec.cpu.stage(1);
    CpuBattleSession make() => CpuBattleSession(
      spec: testSpec,
      player: testCharacter(),
      cpu: cpuDisplayCharacter(testRoster[stage.cpuId], stage),
      stage: stage,
      roster: testRoster,
      seed: 42,
    );
    final a = make();
    final b = make();
    while (!a.isOver) {
      final ea = a.playTurn(BattleAction.tackle);
      final eb = b.playTurn(BattleAction.tackle);
      expect(ea, eb);
    }
    expect(a.state, b.state);
    expect(
      a.state.b.maxHp,
      cpuFighterSetup(testSpec, stage, testRoster).stats.hp *
          testSpec.hpMultiplier,
    );
  });

  test('applyBattleEvent updates hp, gauge, faint and messages', () {
    final d = BattleDisplay(
      a: FighterDisplay(
        name: 'あ',
        level: 1,
        element: ElementType.fire,
        maxHp: 100,
        hp: 100,
      ),
      b: FighterDisplay(
        name: 'い',
        level: 1,
        element: ElementType.leaf,
        maxHp: 100,
        hp: 100,
      ),
    );
    const step = Duration(milliseconds: 100);
    String label(Side s, BattleAction a) => a.name;
    Duration apply(BattleEvent e) => applyBattleEvent(
      d,
      e,
      texts: testSpec.texts,
      moveName: label,
      step: step,
    );
    apply(
      const MoveEvent(Side.a, BattleAction.element, element: ElementType.fire),
    );
    expect(d.message, 'あの element！');
    expect(d[Side.a].hopTick, 1);
    apply(
      const EffectivenessEvent(Side.a, multiplierPct: 150, text: 'こうかは ばつぐんだ！'),
    );
    expect(d.banner, 'こうかは ばつぐんだ！');
    apply(const DamageEvent(Side.b, amount: 40, hp: 60, guarded: false));
    expect(
      (d[Side.b].hp, d[Side.b].lastDamage, d[Side.b].shakeTick),
      (60, 40, 1),
    );
    expect(
      apply(const GaugeEvent(Side.a, delta: 20, value: 20)),
      Duration.zero,
    );
    expect(d[Side.a].gauge, 20);
    apply(const GuardEvent(Side.b, damageTakenPct: 50, weakened: false));
    expect(d[Side.b].guarding, isTrue);
    apply(const TurnStartEvent(2));
    expect(d[Side.b].guarding, isFalse);
    apply(const FaintEvent(Side.b));
    expect(d[Side.b].fainted, isTrue);
    expect(d.message, contains('たおれた'));
  });

  testWidgets('a full CPU battle: animation, XP, level-up and stage progress', (
    tester,
  ) async {
    final app = await pumpApp(tester, characters: [testCharacter()]);
    await openStage(tester, 1);
    expect(find.byKey(const Key('battle-message')), findsOneWidget);
    expect(find.text('めらめらパンチ'), findsOneWidget);
    // ひっさつ is disabled until the gauge is full.
    expect(
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('move-special')))
          .enabled,
      isFalse,
    );

    final turns = await fightUntilResult(tester);
    expect(turns, greaterThan(0));
    expect(find.text('かった！'), findsOneWidget);
    final c = (await app.characters.loadAll()).single;
    expect(c.level, 2); // 100 XP ≥ 75 needed for Lv2
    expect(c.xp, 25);
    expect(find.byKey(const Key('result-levelup')), findsOneWidget);
    expect(find.byKey(const Key('result-seeds')), findsOneWidget);
    expect(app.settingsRepo.progress.clearedStage, 1);
    // Ads are not allowed by default: no ad button.
    expect(find.byKey(const Key('ad-double-xp')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('result-home')));
    expect(find.byKey(const Key('home-draw')), findsOneWidget);
  });

  testWidgets('locked stages cannot be opened', (tester) async {
    await pumpApp(
      tester,
      characters: [testCharacter()],
      progress: const GameProgress(clearedStage: 2),
    );
    await tapVisible(tester, find.byKey(const Key('home-battle')));
    await tapVisible(tester, find.byKey(const Key('select-c_1')));
    expect(find.textContaining('おすすめ Lv'), findsWidgets);
    await tapVisible(tester, find.byKey(const Key('stage-4')));
    expect(find.byKey(const Key('move-tackle')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('stage-3')));
    expect(find.byKey(const Key('move-tackle')), findsOneWidget);
  });

  testWidgets('rewarded ad (allowed): notice first, then XP ×2', (
    tester,
  ) async {
    final monetization = FakeMonetization();
    final app = await pumpApp(
      tester,
      monetization: monetization,
      characters: [testCharacter()],
      settings: setupDone.copyWith(consents: const ParentConsents(ads: true)),
    );
    await openStage(tester, 1);
    await fightUntilResult(tester);
    await tapVisible(tester, find.byKey(const Key('ad-double-xp')));
    // The notice is always shown before the ad.
    expect(find.textContaining('おうちのひとに きいてから みてね'), findsOneWidget);
    expect(find.textContaining('こうこくが ながれるよ'), findsOneWidget);
    expect(monetization.adsShown, 0);
    await tester.tap(find.byKey(const Key('kid-ask-yes')));
    await tester.pumpAndSettle();
    expect(monetization.adsShown, 1);
    expect(find.byKey(const Key('ad-done')), findsOneWidget);
    expect(find.text('けいけんち +200'), findsOneWidget);
    final c = (await app.characters.loadAll()).single;
    // 200 XP from Lv1: 75 → Lv2, 100 → Lv3, 25 left.
    expect((c.level, c.xp), (3, 25));
  });

  testWidgets('declining the ad notice shows no ad', (tester) async {
    final monetization = FakeMonetization();
    await pumpApp(
      tester,
      monetization: monetization,
      characters: [testCharacter()],
      settings: setupDone.copyWith(consents: const ParentConsents(ads: true)),
    );
    await openStage(tester, 1);
    await fightUntilResult(tester);
    await tapVisible(tester, find.byKey(const Key('ad-double-xp')));
    await tester.tap(find.byKey(const Key('kid-ask-no')));
    await tester.pumpAndSettle();
    expect(monetization.adsShown, 0);
    expect(find.byKey(const Key('ad-double-xp')), findsOneWidget);
  });

  testWidgets('a weak しょぼキャラ loses but still earns +50% XP', (tester) async {
    final app = await pumpApp(
      tester,
      characters: [
        testCharacter(
          skill: 90,
          stats: const Stats(hp: 20, atk: 15, def: 15, spd: 10),
        ),
      ],
      progress: const GameProgress(clearedStage: 29),
    );
    await openStage(tester, 30);
    await fightUntilResult(tester);
    expect(find.text('まけちゃった…'), findsOneWidget);
    final stage = testSpec.cpu.stage(30);
    final expected = xpForBattle(
      testSpec,
      won: false,
      isShobo: true,
      stageXpMultiplierPct: stage.xpMultiplierPct,
    );
    expect(find.text('けいけんち +$expected'), findsOneWidget);
    expect(app.settingsRepo.progress.clearedStage, 29);
    expect(find.byKey(const Key('result-next')), findsNothing);
  });

  test('Product ids are stable', () {
    expect(Product.values.map((p) => p.id), [
      'slots_24',
      'frame_pack_1',
      'ouen_pass',
    ]);
  });
}
