import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/features/battle_ui/move_labels.dart';
import 'package:doodle_battle/features/video_export/battle_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

import 'package:doodle_battle/domain/character.dart';

Character _char(ElementType e, {int level = 3, String id = 'c_1'}) {
  final c = testCharacter(id: id, level: level);
  return Character(
    id: c.id,
    name: c.name,
    imagePath: c.imagePath,
    imageHash: c.imageHash,
    element: e,
    baseStats: c.baseStats,
    energy: c.energy,
    skill: c.skill,
    features: c.features,
    createdAt: c.createdAt,
    level: level,
  );
}

void main() {
  for (final e in ElementType.values) {
    test('${e.name}: super-effective element hit against a weaker CPU', () {
      final player = _char(e);
      final h = scriptBattleHighlight(
        spec: testSpec,
        roster: testRoster,
        player: player,
      )!;
      expect(
        typeMultiplierPct(testSpec, BattleAction.element, e, h.cpu.element),
        greaterThan(testSpec.typeChart.neutralPct),
      );
      expect(h.hits, isNotEmpty);
      expect(h.hits.length, lessThanOrEqualTo(2));
      final first = h.hits.first;
      expect(first.superEffective, isTrue);
      expect(first.action, BattleAction.element);
      expect(first.moveLabel, characterMoveLabel(player, BattleAction.element));
      expect(first.damage, greaterThan(0));
      expect(first.targetHpBefore - first.targetHpAfter, first.damage);
      expect(h.superText, 'こうかは ばつぐんだ！');
      expect(h.cpuLevel, player.level);
      // The script ends with the player's KO when a winning seed exists.
      expect(h.endsWithKo, isTrue);
      expect(h.hits.last.targetHpAfter, 0);
    });
  }

  test('deterministic for the same character, varies by character', () {
    final a = scriptBattleHighlight(
      spec: testSpec,
      roster: testRoster,
      player: _char(ElementType.water),
    )!;
    final b = scriptBattleHighlight(
      spec: testSpec,
      roster: testRoster,
      player: _char(ElementType.water),
    )!;
    expect(a.seed, b.seed);
    expect(a.cpu.id, b.cpu.id);
    expect(
      [for (final h in a.hits) h.damage],
      [for (final h in b.hits) h.damage],
    );
  });

  test('matches a replay with the real engine', () {
    final player = _char(ElementType.leaf, level: 7);
    final h = scriptBattleHighlight(
      spec: testSpec,
      roster: testRoster,
      player: player,
    )!;
    // Replay the chosen seed and check the first hit's damage.
    final cpuSetup = FighterSetup(
      element: h.cpu.element,
      level: h.cpuLevel,
      stats: statsAtLevel(
        testSpec,
        h.cpu.baseStats,
        h.cpuLevel,
        const {},
        isShobo: h.cpu.isShobo,
      ),
    );
    var state = initBattle(
      testSpec,
      fighterSetupFor(testSpec, player),
      cpuSetup,
    );
    final rng = Mulberry32(deriveSeed(h.seed, 0));
    final damages = <int>[];
    while (!state.isOver) {
      final act = state.a.gauge >= testSpec.gauge.max
          ? BattleAction.special
          : BattleAction.element;
      final r = resolveTurn(testSpec, state, act, BattleAction.tackle, rng);
      for (final e in r.events) {
        if (e is DamageEvent && e.target == Side.b) damages.add(e.amount);
      }
      state = r.state;
    }
    expect(damages.first, h.hits.first.damage);
    expect(state.winner, Side.a);
    expect(h.hits.last.damage, damages.last);
  });
}
