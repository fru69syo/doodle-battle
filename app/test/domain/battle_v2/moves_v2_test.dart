// PROTOTYPE v2 tests — move budget, validator, offline generator (§5).
import 'package:doodle_battle/domain/battle/rng.dart';
import 'package:doodle_battle/domain/battle_v2/battle_v2.dart';
import 'package:doodle_battle/domain/battle_v2/sim_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V2Spec();

  test('standard move costs exactly 100', () {
    const m = MoveV2(template: 'strike', attr: Attr.gu, power: 100);
    expect(moveCost(s, m), 100);
  });

  test('discount is capped at 50 % of the value', () {
    const m = MoveV2(
      template: 'strike',
      attr: Attr.gu,
      power: 200,
      spCost: 50,
      castTicks: 20,
      cooldownTicks: 150,
    );
    expect(moveValue(m), 200);
    expect(moveDiscount(s, m), 100);
  });

  test('offline moves always respect budgets and slot rules', () {
    final r = Mulberry32(21);
    for (var i = 0; i < 400; i++) {
      final g = i % 5 == 0 ? randomBloomer(s, r) : randomKid(s, r);
      for (final lv in [1, 50]) {
        final f = g.moveFactorPct(lv);
        final ms = generateOfflineMoves(
          s,
          g,
          moveFactorPct: f,
          stream: g.rebornAt(lv) ? 14 : 12,
        );
        expect(ms, hasLength(4));
        for (var slot = 0; slot < 4; slot++) {
          expect(
            moveCost(s, ms[slot]),
            lessThanOrEqualTo(slotBudget(s, slot, f)),
            reason: '$slot',
          );
          for (final e in ms[slot].tpl.ranges.entries) {
            final v = ms[slot].toJson()[e.key];
            if (v is int) expect(v, inInclusiveRange(e.value.min, e.value.max));
          }
          expect(ms[slot].name.length, inInclusiveRange(1, 10));
        }
        expect(ms[0].attr, g.attr);
        expect(ms[0].spCost, 0);
        expect(ms[0].cooldownTicks, 0);
        expect(ms[1].attr, isNot(g.attr));
        expect(ms[3].attr, Attr.none);
        expect(ms[3].isDamage, isTrue);
      }
    }
  });

  group('validator', () {
    MoveValidation v(int slot, Map<String, Object?> j, {Attr own = Attr.gu}) =>
        validateAiMove(
          s,
          j,
          slot: slot,
          own: own,
          moveFactorPct: 100,
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
      expect(r.move!.spCost, 0);
      expect(r.move!.castTicks, lessThanOrEqualTo(5));
      expect(moveCost(s, r.move!), lessThanOrEqualTo(100));
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
