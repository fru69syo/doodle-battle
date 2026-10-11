// Engine v3 — guards the balance targets of docs/GAME_DESIGN_V2.md §10
// with a small Monte Carlo (the full table: dart run tool/v3_sim.dart).
import 'package:doodle_battle/domain/battle_v3/battle_v3.dart';
import 'package:doodle_battle/domain/battle_v3/sim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V3Spec();
  const n = 500;

  test('equal stats ≈ 50 %', () {
    final r = runScenario(s, 'mirror', n, (r) {
      final f = setupAt(s, randomKid(s, r), 20);
      return (f, f);
    });
    expect(r.winRateA, closeTo(0.5, 0.06));
  });

  test('triangle advantage 60–78 %', () {
    final r = runScenario(s, 'tri', n, (r) {
      final g = randomKid(s, r);
      final a = Attr.values[r.nextInt(3)];
      return (setupAt(s, g, 10, attr: a), setupAt(s, g, 10, attr: a.beats));
    });
    expect(r.winRateA, inInclusiveRange(0.60, 0.78));
  });

  test('kid beats a hidden bloomer of the same low level ≥ 85 %', () {
    for (final lv in [1, 30]) {
      final r = runScenario(
        s,
        'kb$lv',
        n ~/ 2,
        (r) => (
          setupAt(s, randomKid(s, r), lv),
          setupAt(s, randomBloomer(s, r), lv),
        ),
      );
      expect(r.winRateA, greaterThanOrEqualTo(0.85));
    }
  });

  test('bloomer ≈ even at the rated sync level, 55–70 % at Lv100', () {
    final r50 = runScenario(
      s,
      'b50',
      n,
      (r) => (
        setupAt(s, randomBloomer(s, r), 50),
        setupAt(s, randomKid(s, r), 50),
      ),
    );
    expect(r50.winRateA, inInclusiveRange(0.40, 0.56));
    final r100 = runScenario(
      s,
      'b100',
      n,
      (r) => (
        setupAt(s, randomBloomer(s, r), 100),
        setupAt(s, randomKid(s, r), 100),
      ),
    );
    expect(r100.winRateA, inInclusiveRange(0.55, 0.70));
  });

  test('average battle length 40–90 s for different drawings', () {
    final r = runScenario(
      s,
      'len',
      n,
      (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)),
    );
    expect(r.avgSeconds, inInclusiveRange(40, 90));
    expect(r.timeUps, lessThan(n ~/ 100));
  });

  test('つよい beats ふつう ≥ 60 % (≥ 57 % at this sample size)', () {
    final r = runScenario(
      s,
      'strong',
      800,
      (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)),
      tierA: AiTier.strong,
    );
    expect(r.winRateA, greaterThanOrEqualTo(0.57));
  });

  test('ふつう beats よわい', () {
    final r = runScenario(
      s,
      'weak',
      n,
      (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)),
      tierB: AiTier.weak,
    );
    expect(r.winRateA, greaterThan(0.5));
  });
}
