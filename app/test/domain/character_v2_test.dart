// Character v2 model: JSON round trip, v1 migration, growth, rig blob and
// the "hidden state is never persisted" rule.
import 'dart:convert';

import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/character_v2.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/rig_blob.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:flutter_test/flutter_test.dart';

const _raw = <String, num>{
  'inkCoverage': 0.18,
  'silhouetteCoverage': 0.22,
  'colorCount': 3,
  'achromaticCount': 1,
  'balancedHueCount': 2,
  'redShare': 0.31,
  'darkness': 0.44,
  'symmetry': 0.62,
  'detailDensity': 0.12,
  'spikiness': 0.08,
  'convexityDefects': 4,
  'roundness': 0.71,
  'solidity': 0.86,
  'elongation': 1.3,
  'lineThickness': 6.4,
};

Character _v1({double skill = 18.3, int level = 12, int xp = 40}) => Character(
  id: 'c1',
  name: 'ねこまる',
  imagePath: '/tmp/c1.png',
  imageHash: 'a1b2c3d4${'e' * 56}',
  element: ElementType.fire,
  baseStats: const Stats(hp: 100, atk: 90, def: 80, spd: 70),
  energy: 82.4,
  skill: skill,
  features: _raw,
  createdAt: DateTime.utc(2026, 9, 1),
  level: level,
  xp: xp,
  seedAllocations: const {StatKind.atk: 3},
  elementMoveName: 'ほのおパンチ',
  specialMoveName: 'Super Beam',
  onlineId: 'snap1',
);

CharacterV2 _fresh({String? verdict, double skill = 20}) => CharacterV2.create(
  id: 'n1',
  name: 'ぴょんた',
  imagePath: '/tmp/n1.png',
  imageHash: '0badcafe${'0' * 56}',
  rawFeatures: _raw,
  energy: 77.7,
  skill: skill,
  createdAt: DateTime.utc(2026, 10, 1),
  verdict: verdict,
);

void main() {
  const s = V3Spec();

  test('new character: quantised once, derived stats, 2 moves at Lv1', () {
    final c = _fresh();
    expect(c.energy10, 777);
    expect(c.skill10, 200);
    expect(c.features['lineThickness'], 64);
    expect(c.features['colorUnits'], 7);
    expect(c.stats(), hasLength(10));
    expect(c.unlockedSlotCount(), 2);
    expect(c.battleSetup().moves, hasLength(2));
    expect(c.allMoves(), hasLength(4));
    expect(c.maxHp(), maxHpOf(s, c.stats()));
  });

  test('JSON round trip (schema 2) keeps every input', () {
    final c = _fresh(verdict: 'digital').copyWith(
      level: 20,
      xp: 12,
      rig: () => {
        'v': 1,
        'width': 200,
        'height': 300,
        'root': [100, 250],
        'chest': [100, 150],
        'limbs': <Object?>[],
      },
    );
    final j = jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>;
    expect(j['schema'], 2);
    final d = CharacterV2.fromJson(j);
    expect(d.toJson(), c.toJson());
    expect(d.stats(), c.stats());
    expect(d.rig, isNotNull);
  });

  test('hidden state is derived, never persisted', () {
    final c = _fresh(skill: 90); // a polished picture
    expect(c.genome().isBloomer, isTrue);
    final text = jsonEncode(c.toJson()).toLowerCase();
    for (final w in ['bloomer', 'kid', 'reborn', 'rebirth', 'hidden']) {
      expect(text, isNot(contains(w)));
    }
  });

  test('canvas drawings are never judged digital', () {
    final c = CharacterV2.create(
      id: 'k',
      name: 'かく',
      imagePath: '/x.png',
      imageHash: '12345678',
      rawFeatures: _raw,
      energy: 70,
      skill: 20,
      createdAt: DateTime.utc(2026),
      source: DrawingSource.canvas,
      verdict: 'digital',
    );
    expect(c.verdict, isNull);
    expect(c.genome().isBloomer, isFalse);
  });

  test('v1 migration re-derives stats and moves from stored features', () {
    final v1 = _v1();
    final c = CharacterV2.fromJson(v1.toJson());
    expect(c.energy10, 824);
    expect(c.skill10, 183);
    expect(c.level, 12);
    expect(c.xp, 40);
    expect(c.features.values, FeatureVector.quantize(_raw).values);
    expect(c.legacyElement, ElementType.fire);
    expect(c.onlineId, isNull); // must register again for v2 online play
    expect(c.allMoves().first.name, 'ほのおパンチ'); // valid kana kept
    expect(c.allMoves()[3].name, isNot('Super Beam')); // invalid dropped
    expect(c.genome().isBloomer, isFalse);
    expect(c.unlockedSlotCount(), 3);
    // Saving and loading again is stable.
    final again = CharacterV2.fromJson(
      jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>,
    );
    expect(again.toJson(), c.toJson());
  });

  test('v1 しょぼキャラ migrate to hidden bloomers; XP is clamped', () {
    final c = CharacterV2.fromJson(_v1(skill: 82, xp: 999999).toJson());
    expect(c.genome().isBloomer, isTrue);
    expect(c.xp, xpToNext(s, 12) - 1);
  });

  test('v1 migration survives missing / odd fields', () {
    final j = _v1().toJson()
      ..['features'] = {'roundness': 'x'}
      ..remove('energy')
      ..['level'] = 0;
    final c = CharacterV2.fromJson(j);
    expect(c.level, 1);
    expect(c.stats(), hasLength(10));
  });

  test('levelling: Lv10 slot, Lv50 bloomer rebirth regenerates moves', () {
    final c = _fresh(skill: 90).withAiMoves(
      validateAiMoveSet(
        s,
        {
          'moves': [
            {
              'template': 'strike',
              'attribute': _fresh(skill: 90).attribute().name,
              'name': 'ぴょんパンチ',
              'power': 100,
            },
          ],
        },
        own: _fresh(skill: 90).attribute(),
        moveFactorPct: 70,
      ),
    );
    expect(c.allMoves().first.name, 'ぴょんパンチ');
    var (d, p) = c.gainXp(totalXpTo(s, 10));
    expect(d.level, 10);
    expect(p.newSlots, [2]);
    (d, p) = d.copyWith(level: 49, xp: 0).gainXp(xpToNext(s, 49));
    expect(d.level, 50);
    expect(p.rebirth, isTrue);
    expect(d.moveSet, 1);
    expect(d.moves, isEmpty);
    expect(d.allMoves().first.name, isNot('ぴょんパンチ'));
    int sum(List<int> x) => x.fold<int>(0, (a, v) => a + v);
    expect(sum(d.stats()), greaterThan(sum(c.copyWith(level: 49).stats()) * 2));
  });

  test('AI proposals are re-fitted to the budget at every level', () {
    final c0 = _fresh();
    final own = c0.attribute();
    final c = c0.withAiMoves(
      validateAiMoveSet(
        s,
        {
          'moves': [
            {
              'template': 'strike',
              'attribute': own.name,
              'name': 'ぴょんパンチ',
              'power': 200,
            },
          ],
        },
        own: own,
        moveFactorPct: c0.genome().moveFactorPct(1),
      ),
    );
    for (final m in c.allMoves()) {
      expect(m.name, isNotEmpty);
    }
    final m0 = c.allMoves().first;
    expect(m0.name, 'ぴょんパンチ');
    expect(
      moveCost(s, m0),
      lessThanOrEqualTo(slotBudget(s, 0, c.genome().moveFactorPct(1))),
    );
  });

  test('rig blob validation', () {
    expect(validateRigJson({'v': 2}), isNull);
    expect(rigProblem('x'), 'not an object');
    final ok = {
      'v': 1,
      'width': 10,
      'height': 10,
      'root': [5, 5],
      'chest': [5, 4],
      'limbs': [
        {
          'kind': 'leg',
          'base': [5, 5],
          'mid': [5, 7],
          'tip': [5, 9],
        },
      ],
    };
    expect(rigProblem(ok), isNull);
    expect(_fresh().copyWith(rig: () => {'v': 1}).rig, isNull);
  });
}
