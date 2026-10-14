import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/domain/character_v2_view.dart';
import 'package:doodle_battle/domain/cosmetics.dart';
import 'package:doodle_battle/features/video_export/battle_highlight.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/harness.dart';

/// Characters of each attribute (features chosen to tip the shape score).
final _byAttr = <Attr, Map<String, num>>{
  Attr.gu: {'solidity': 0.95, 'roundness': 0.8, 'lineThickness': 12},
  Attr.choki: {'spikiness': 0.3, 'elongation': 3.0, 'lineThickness': 1},
  Attr.pa: {'colorCount': 5, 'balancedHueCount': 4, 'silhouetteCoverage': 0.35},
};

CharacterV2 _char(Attr a, {int level = 3, String id = 'c_1'}) =>
    testCharacter(id: id, level: level, features: _byAttr[a]!);

void main() {
  for (final a in [Attr.gu, Attr.choki, Attr.pa]) {
    test('${a.name}: super-effective slot-1 hit against a weaker CPU', () {
      final player = _char(a);
      expect(player.attribute(), a, reason: 'fixture features');
      final h = scriptBattleHighlight(roster: testRoster, player: player)!;
      expect(h.cpu.genome().attr, a.beats);
      expect(h.hits, isNotEmpty);
      expect(h.hits.length, lessThanOrEqualTo(2));
      final first = h.hits.first;
      expect(first.superEffective, isTrue);
      expect(first.move, DrawnMove.element);
      expect(first.moveLabel, player.elementMoveName);
      expect(first.damage, greaterThan(0));
      expect(first.targetHpBefore - first.targetHpAfter, first.damage);
      expect(h.superText, 'こうかは ばつぐんだ！');
      expect(h.cpuLevel, player.level);
      expect(h.endsWithKo, isTrue);
      expect(h.hits.last.targetHpAfter, 0);
    });
  }

  test('deterministic for the same character', () {
    final a = scriptBattleHighlight(
      roster: testRoster,
      player: _char(Attr.pa),
    )!;
    final b = scriptBattleHighlight(
      roster: testRoster,
      player: _char(Attr.pa),
    )!;
    expect(a.seed, b.seed);
    expect(a.cpu.id, b.cpu.id);
    expect(
      [for (final h in a.hits) h.damage],
      [for (final h in b.hits) h.damage],
    );
  });

  test('matches a replay with engine v3', () {
    const spec = V3Spec();
    final player = _char(Attr.gu, level: 7);
    final h = scriptBattleHighlight(roster: testRoster, player: player)!;
    final battle = Battle(
      spec,
      player.battleSetup(),
      setupAt(
        spec,
        h.cpu.genome(),
        h.cpuLevel,
        powerPct: kHighlightCpuPowerPct,
      ),
      seed: h.seed,
    );
    int? slot0(Battle _, int _) => 0;
    while (!battle.finished) {
      battle.step(a: slot0, b: slot0);
    }
    final damages = [
      for (final e in battle.events)
        if (e.type == 'hit' && e.i('target') == 1) e.i('amount')!,
    ];
    expect(damages.first, h.hits.first.damage);
    expect(battle.winner, 0);
    expect(h.hits.last.damage, damages.last);
  });
}
