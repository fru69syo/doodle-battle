import 'package:doodle_battle/domain/battle/battle.dart';
import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/domain/stats.dart';
import 'package:flutter_test/flutter_test.dart';

import '_support.dart';

void main() {
  final spec = loadSpecFromFile();
  FighterSetup fs(ElementType e) => FighterSetup(
    element: e,
    level: 1,
    stats: const Stats(hp: 90, atk: 90, def: 90, spd: 90),
  );
  final base = initBattle(spec, fs(ElementType.fire), fs(ElementType.leaf));

  test('never chooses an unavailable special, never times out', () {
    for (final tier in AiTier.values) {
      final rng = Mulberry32(tier.index + 1);
      for (var i = 0; i < 500; i++) {
        final a = chooseCpuAction(spec, base, Side.a, tier, rng);
        expect(a, isNot(BattleAction.special));
        expect(a, isNot(BattleAction.timeout));
      }
    }
  });

  test('weak picks every basic move sometimes', () {
    final rng = Mulberry32(1);
    final seen = {
      for (var i = 0; i < 300; i++)
        chooseCpuAction(spec, base, Side.a, AiTier.weak, rng),
    };
    expect(seen, {
      BattleAction.tackle,
      BattleAction.element,
      BattleAction.guard,
    });
  });

  test('normal is type-aware and uses a ready special', () {
    final rng = Mulberry32(2);
    final aMoves = {
      for (var i = 0; i < 200; i++)
        chooseCpuAction(spec, base, Side.a, AiTier.normal, rng),
    };
    expect(aMoves, {BattleAction.element, BattleAction.guard});
    final bMoves = {
      for (var i = 0; i < 200; i++)
        chooseCpuAction(spec, base, Side.b, AiTier.normal, rng),
    };
    expect(bMoves, {BattleAction.tackle, BattleAction.guard});
    final ready = base.withFighter(Side.a, base.a.copyWith(gauge: 100));
    expect(
      chooseCpuAction(spec, ready, Side.a, AiTier.normal, rng),
      BattleAction.special,
    );
  });

  test(
    'strong finishes a weakened opponent and braces for a lethal special',
    () {
      final rng = Mulberry32(3);
      final low = base.withFighter(Side.b, base.b.copyWith(hp: 3));
      expect(
        chooseCpuAction(spec, low, Side.a, AiTier.strong, rng),
        BattleAction.tackle,
      );
      final threatened = BattleState(
        a: base.a.copyWith(hp: 60),
        b: base.b.copyWith(gauge: 100),
      );
      final picks = [
        for (var i = 0; i < 200; i++)
          chooseCpuAction(spec, threatened, Side.a, AiTier.strong, rng),
      ];
      final guards = picks.where((p) => p == BattleAction.guard).length;
      expect(guards, inInclusiveRange(130, 190)); // ~80%
    },
  );

  test('strong holds its special against a habitual guarder', () {
    final rng = Mulberry32(4);
    final s = BattleState(
      a: base.a.copyWith(gauge: 100),
      b: base.b.copyWith(usage: const MoveUsage(guard: 3, tackle: 1)),
    );
    expect(
      chooseCpuAction(spec, s, Side.a, AiTier.strong, rng),
      BattleAction.element,
    );
    final justGuarded = s.withFighter(Side.b, s.b.copyWith(guardStreak: 1));
    expect(
      chooseCpuAction(spec, justGuarded, Side.a, AiTier.strong, rng),
      BattleAction.special,
    );
  });
}
