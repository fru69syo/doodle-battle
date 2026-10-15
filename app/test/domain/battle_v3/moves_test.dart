// Engine v3 tests — move budget, validator, offline generator (§5).
import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V3Spec();

  test('standard move is worth exactly 100 points = 1 bar', () {
    const m = Move(template: 'strike', attr: Attr.gu, power: 100);
    expect(movePoints(s, m), 100);
    expect(moveBars(s, m, 100), 1);
    expect(moveBars(s, m, 95), 2);
  });

  test('discount: cast and a quarter of the extra cooldown, capped', () {
    const m = Move(
      template: 'strike',
      attr: Attr.gu,
      power: 200,
      castTicks: 20,
      cooldownTicks: 150,
    );
    expect(moveValue(m), 200);
    expect(moveDiscount(s, m), 200 * s.maxDiscountPct ~/ 100);
    const n = Move(
      template: 'strike',
      attr: Attr.gu,
      power: 400,
      castTicks: 6,
      cooldownTicks: 40,
    );
    expect(moveDiscount(s, n), 6 * 2 + (40 - 20) ~/ 4);
  });

  test('bars grow with points; n bars ≈ n one-bar moves + a premium', () {
    for (var n = 1; n <= 5; n++) {
      expect(barsForPoints(s, s.barBudgets[n - 1], 100), n);
      expect(
        barsForPoints(s, s.barBudgets[n - 1] + 1, 100),
        n == 5 ? 0 : n + 1,
      );
      expect(s.barBudgets[n - 1], greaterThanOrEqualTo(100 * n));
    }
    // Per bar the value never falls as the cost grows.
    for (var n = 2; n <= 5; n++) {
      expect(
        s.barBudgets[n - 1] * (n - 1),
        greaterThanOrEqualTo(s.barBudgets[n - 2] * n),
      );
    }
  });

  test('max bars from the Lv1 SP: SP / 10 clamped to 2..5', () {
    expect(s.maxBarsFor(0), 2);
    expect(s.maxBarsFor(29), 2);
    expect(s.maxBarsFor(30), 3);
    expect(s.maxBarsFor(49), 4);
    expect(s.maxBarsFor(50), 5);
    expect(s.maxBarsFor(99), 5);
  });

  test('offline moves always respect budgets and slot rules', () {
    final r = Mulberry32(21);
    for (var i = 0; i < 400; i++) {
      final g = i % 5 == 0 ? randomBloomer(s, r) : randomKid(s, r);
      for (final lv in [1, 50]) {
        final f = g.moveFactorPct(lv);
        final mb = g.maxBarsAt(lv);
        final ms = generateOfflineMoves(
          s,
          g,
          moveFactorPct: f,
          stream: g.rebornAt(lv) ? 14 : 12,
        );
        expect(ms, hasLength(4));
        for (var slot = 0; slot < 4; slot++) {
          expect(
            movePoints(s, ms[slot]),
            lessThanOrEqualTo(slotBudget(s, slot, f, mb)),
            reason: '$slot',
          );
          expect(ms[slot].bars, moveBars(s, ms[slot], f));
          expect(ms[slot].bars, inInclusiveRange(1, mb));
          for (final e in ms[slot].tpl.ranges.entries) {
            final v = ms[slot].toJson()[e.key];
            if (v is int) expect(v, inInclusiveRange(e.value.min, e.value.max));
          }
          expect(ms[slot].name.length, inInclusiveRange(1, 10));
        }
        expect(ms[0].attr, g.attr);
        expect(ms[0].bars, 1);
        expect(ms[0].cooldownTicks, 0);
        expect(ms[3].bars, mb, reason: 'ひっさつ uses every bar');
        expect(ms[1].attr, isNot(g.attr));
        expect(ms[3].attr, Attr.none);
        expect(ms[3].isDamage, isTrue);
      }
    }
  });

  group('validator', () {
    MoveValidation v(
      int slot,
      Map<String, Object?> j, {
      Attr own = Attr.gu,
      int maxBars = 5,
    }) => validateAiMove(
      s,
      j,
      slot: slot,
      own: own,
      moveFactorPct: 100,
      maxBars: maxBars,
      ngCheck: (t) => t.contains('ばか'),
    );

    test('accepts an in-budget move unchanged', () {
      final r = v(0, {
        'template': 'strike',
        'attribute': 'gu',
        'name': 'ごつごつパンチ',
        'vfx': 'punch',
        'colour': 'red',
        'atkFormula': 'STR70_VIT30',
        'power': 100,
        'hits': 1,
        'accuracy': 100,
        'spCost': 0,
        'castTicks': 0,
        'cooldownTicks': 0,
      });
      expect(r.rejected, isFalse);
      expect(r.warnings, isEmpty);
      expect(r.move!.atkFormula, AtkFormula.strVit);
    });

    test('clamps, forces slot rules and scales to budget', () {
      final r = v(0, {
        'template': 'strike',
        'attribute': 'pa',
        'name': 'すごいパンチ',
        'power': 999,
        'spCost': 30,
        'castTicks': 30,
      });
      expect(r.rejected, isFalse);
      expect(r.move!.attr, Attr.gu);
      expect(r.move!.bars, 1);
      expect(r.move!.castTicks, lessThanOrEqualTo(5));
      expect(movePoints(s, r.move!), lessThanOrEqualTo(100));
    });

    test('the cost is derived, never taken from the AI, and fits max bars', () {
      final big = {
        'template': 'blast',
        'name': 'おおきなビーム',
        'atkFormula': 'INT80_DEX20',
        'power': 900,
        'castTicks': 12,
        'cooldownTicks': 80,
        'bars': 1,
        'spCost': 0,
      };
      final five = v(3, big);
      expect(five.move!.bars, 5);
      expect(five.move!.toJson().containsKey('spCost'), isFalse);
      for (final mb in [2, 3, 4]) {
        final r = v(3, big, maxBars: mb);
        expect(r.move!.bars, mb);
        expect(r.warnings, contains('scaled to budget'));
        expect(r.move!.power, lessThan(five.move!.power));
      }
    });

    test('rejects unknown templates, bad names and NG words', () {
      expect(v(1, {'template': 'nuke', 'name': 'ドカン'}).rejected, isTrue);
      expect(v(1, {'template': 'blast', 'name': 'Beam'}).rejected, isTrue);
      expect(v(1, {'template': 'blast', 'name': 'ばかビーム'}).rejected, isTrue);
      expect(v(1, {'template': 'heal', 'name': 'おひるね'}).rejected, isFalse);
      expect(v(0, {'template': 'heal', 'name': 'おひるね'}).rejected, isTrue);
    });

    test('drops a flavour text with NG words or non-kana', () {
      final r = v(1, {'template': 'heal', 'name': 'ヒール', 'flavor': 'ばか'});
      expect(r.move!.flavor, '');
      final q = v(1, {'template': 'heal', 'name': 'ヒール', 'flavor': '<b>hi'});
      expect(q.move!.flavor, '');
    });

    test('support moves are neutral and buffs cannot be chained', () {
      final r = v(2, {
        'template': 'power_up',
        'attribute': 'choki',
        'name': 'きあい',
        'stat': 'STR',
        'stages': 1,
        'durationTicks': 80,
        'cooldownTicks': 0,
      });
      expect(r.move!.attr, Attr.none);
      expect(r.move!.cooldownTicks, greaterThanOrEqualTo(80));
    });
  });
}
