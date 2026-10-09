import 'package:doodle_battle/domain/character.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Character round-trips through JSON', () {
    final c = Character(
      id: 'c1',
      name: 'もこもこ',
      imagePath: '/tmp/c1.png',
      imageHash: 'abc',
      element: ElementType.leaf,
      baseStats: const Stats(hp: 80, atk: 70, def: 60, spd: 90),
      energy: 72.5,
      skill: 20,
      features: const {'inkCoverage': 0.31, 'colorCount': 4},
      createdAt: DateTime.utc(2026, 10, 9),
      level: 12,
      xp: 30,
      seedAllocations: const {StatKind.atk: 2},
      subject: 'ねこ',
    );
    final back = Character.fromJson(c.toJson());
    expect(back.toJson(), c.toJson());
    expect(back.stage, EvolutionStage.kagayaki);
    expect(back.onlineUnlocked, isTrue);
    expect(back.isShobo, isFalse);
  });
}
