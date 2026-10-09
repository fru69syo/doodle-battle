import 'package:doodle_battle/domain/battle/balance_sim.dart';
import 'package:doodle_battle/domain/battle/cpu_roster.dart';
import 'package:flutter_test/flutter_test.dart';

import '_support.dart';

/// Guards the balance targets documented in docs/BATTLE.md §7.
void main() {
  final spec = loadSpecFromFile();
  final results = {for (final r in standardScenarios(spec, n: 2000)) r.name: r};
  SimResult r(String name) => results[name]!;

  test('しょぼ stays < 20% against a kid scribble at the same level', () {
    for (final lv in [1, 10, 20, 30]) {
      expect(r('shobo vs kid, both Lv$lv').winRateA, lessThan(0.20));
    }
    for (final lv in [10, 20, 30]) {
      expect(
        r('shobo vs kid, both Lv$lv, seeds spent').winRateA,
        lessThan(0.20),
      );
    }
  });

  test('「育てれば戦える」: Lv30 しょぼ vs Lv15 kid is 40-60%', () {
    expect(r('shobo Lv30 vs kid Lv15').winRateA, inInclusiveRange(0.40, 0.60));
    expect(
      r('shobo Lv30 vs kid Lv15, seeds spent').winRateA,
      inInclusiveRange(0.40, 0.60),
    );
  });

  test('equal stats ~50%', () {
    expect(r('mirror (equal stats)').winRateA, closeTo(0.5, 0.04));
    expect(r('kid vs kid (random spreads)').winRateA, closeTo(0.5, 0.04));
    expect(r('shadow vs rainbow (mutual)').winRateA, closeTo(0.5, 0.04));
  });

  test('type advantage ~65-75% (realistic stat spreads)', () {
    expect(
      r('type advantage (fire vs leaf)').winRateA,
      inInclusiveRange(0.65, 0.77),
    );
  });

  test('Lv+5 is meaningful but not absolute', () {
    for (final n in ['Lv6 vs Lv1', 'Lv15 vs Lv10', 'Lv30 vs Lv25']) {
      expect(r(n).winRateA, inInclusiveRange(0.65, 0.92), reason: n);
    }
  });

  test('typical battles last 4-8 turns on average and never run forever', () {
    for (final n in [
      'mirror (equal stats)',
      'kid vs kid (random spreads)',
      'type advantage (fire vs leaf)',
      'Lv6 vs Lv1',
      'strong AI vs normal AI',
      'weak vs weak (guard-heavy)',
    ]) {
      expect(r(n).avgTurns, inInclusiveRange(4.0, 8.0), reason: n);
    }
    for (final res in results.values) {
      expect(res.maxTurns, lessThanOrEqualTo(spec.turnCap), reason: res.name);
    }
  });

  test('AI tiers are ordered', () {
    expect(r('strong AI vs normal AI').winRateA, greaterThan(0.5));
    expect(r('normal AI vs weak AI').winRateA, greaterThan(0.55));
    expect(r('strong AI vs weak AI').winRateA, greaterThan(0.6));
  });

  test('CPU stages form a difficulty curve at the recommended level', () {
    final roster = CpuRoster.fromManifestJson(readJson(cpuManifestPath));
    final rates = {
      for (final st in spec.cpu.stages)
        st.stage: simulateStage(spec, roster, st, n: 600).winRateA,
    };
    for (final e in rates.entries) {
      final boss = e.key % 10 == 0;
      expect(
        e.value,
        boss ? inInclusiveRange(0.30, 0.62) : inInclusiveRange(0.52, 0.95),
        reason: 'stage ${e.key}',
      );
    }
    double avg(Iterable<int> stages) =>
        stages.map((s) => rates[s]!).reduce((a, b) => a + b) / stages.length;
    expect(avg([1, 2, 3, 4, 5]), greaterThan(avg([25, 26, 27, 28, 29])));
  });
}
