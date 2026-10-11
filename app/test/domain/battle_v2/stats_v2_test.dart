// PROTOTYPE v2 tests — character generation (docs/GAME_DESIGN_V2.md §2–4).
import 'package:doodle_battle/domain/battle/rng.dart';
import 'package:doodle_battle/domain/battle_v2/battle_v2.dart';
import 'package:doodle_battle/domain/battle_v2/sim_v2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V2Spec();

  test('kid-likeness merges energy and skill (0..100)', () {
    expect(kidLikeness(s, 1000, 0), 100);
    expect(kidLikeness(s, 0, 1000), 0);
    expect(kidLikeness(s, 914, 83), 92); // crayon scribble (VISION §6)
    expect(kidLikeness(s, 398, 203), 56); // marker stick figure
  });

  test('largestRemainder sums exactly and favours bigger remainders', () {
    expect(largestRemainder(10, [1, 1, 1]), [4, 3, 3]);
    expect(largestRemainder(7, [0, 0]), [4, 3]);
    final r = Mulberry32(3);
    for (var i = 0; i < 200; i++) {
      final shares = [for (var k = 0; k < 10; k++) r.nextInt(5000)];
      final t = r.nextInt(900);
      expect(largestRemainder(t, shares).fold<int>(0, (a, b) => a + b), t);
    }
  });

  test('genome is deterministic and budget/growth invariants hold', () {
    final r = Mulberry32(11);
    for (var i = 0; i < 300; i++) {
      final f = randomFeatures(r);
      final hash = r.nextUint32().toRadixString(16).padLeft(8, '0');
      Genome mk() => Genome.derive(
        s,
        features: f,
        energy10: 700,
        skill10: i.isEven ? 100 : 900,
        imageHash: hash,
      );
      final g = mk();
      final h = mk();
      expect(g.base, h.base);
      expect(g.growthMille, h.growthMille);
      expect(g.base.fold<int>(0, (a, b) => a + b), g.budget);
      expect(g.growthMille.fold<int>(0, (a, b) => a + b), 400);
      for (final v in g.base) {
        expect(v, greaterThanOrEqualTo(g.budget * 50 ~/ 1000 - 1));
      }
      expect(g.isBloomer, i.isOdd);
    }
  });

  test('appearance drives the distribution', () {
    const hard = FeatureVector({
      'lineThickness': 140,
      'darkness': 850,
      'solidity': 970,
      'elongation': 100,
      'spikiness': 0,
      'roundness': 500,
    });
    const slim = FeatureVector({
      'lineThickness': 15,
      'darkness': 200,
      'solidity': 550,
      'elongation': 400,
      'spikiness': 300,
      'silhouetteCoverage': 40,
    });
    Genome g(FeatureVector f) => Genome.derive(
      s,
      features: f,
      energy10: 800,
      skill10: 100,
      imageHash: '0badc0de',
    );
    final a = g(hard).base;
    final b = g(slim).base;
    expect(a[Stat.def.index], greaterThan(a[Stat.agi.index] * 2));
    expect(a[Stat.vit.index], greaterThan(b[Stat.vit.index]));
    expect(a[Stat.res.index], greaterThan(b[Stat.res.index]));
    expect(b[Stat.agi.index], greaterThan(b[Stat.def.index]));
    expect(b[Stat.dex.index], greaterThan(a[Stat.dex.index]));
    expect(attributeOf(hard), Attr.gu);
    expect(attributeOf(slim), Attr.choki);
  });

  test('origin verdicts make a hidden bloomer', () {
    for (final o in kBloomerOrigins) {
      final g = Genome.derive(
        s,
        features: const FeatureVector({}),
        energy10: 800,
        skill10: 100,
        imageHash: '12345678',
        origin: o,
      );
      expect(g.isBloomer, isTrue);
    }
  });

  test('bloomer: weak until Lv50, re-generated at Lv50, stronger at 100', () {
    final r = Mulberry32(5);
    var sumKid100 = 0, sumBloom100 = 0;
    for (var i = 0; i < 200; i++) {
      final k = randomKid(s, r);
      final b = randomBloomer(s, r);
      int tot(List<int> x) => x.fold<int>(0, (a, c) => a + c);
      expect(tot(b.statsAt(49)), lessThan(tot(k.statsAt(20))));
      expect(tot(b.statsAt(50)), greaterThan(tot(b.statsAt(49)) * 3 ~/ 2));
      expect(b.moveFactorPct(49), s.bloomerPreMoveFactorPct);
      sumKid100 += tot(k.statsAt(100));
      sumBloom100 += tot(b.statsAt(100));
    }
    expect(sumBloom100, greaterThan(sumKid100));
  });

  test('rated sync: Lv50 stats; an un-reborn bloomer keeps its weak form', () {
    final r = Mulberry32(12);
    final k = randomKid(s, r);
    final b = randomBloomer(s, r);
    expect(k.ratedStats(7), k.statsAt(50));
    expect(b.ratedStats(60), b.statsAt(50));
    int tot(List<int> x) => x.fold<int>(0, (a, c) => a + c);
    expect(tot(b.ratedStats(30)), lessThan(tot(b.statsAt(50)) ~/ 2 + 1));
  });

  test('stats never decrease with level (normal)', () {
    final g = randomKid(s, Mulberry32(9));
    var prev = g.statsAt(1);
    for (var l = 2; l <= 100; l++) {
      final cur = g.statsAt(l);
      for (var i = 0; i < 10; i++) {
        expect(cur[i], greaterThanOrEqualTo(prev[i]));
      }
      prev = cur;
    }
  });
}
