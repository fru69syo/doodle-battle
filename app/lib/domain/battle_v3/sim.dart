/// Monte Carlo harness for the v3 balance (dev tooling: `tool/v3_sim.dart`,
/// the balance tests and the golden-vector generator). Not used by the app.
library;

import 'ai.dart';
import 'engine.dart';
import 'features.dart';
import 'genome.dart';
import 'loadout.dart';
import 'rng.dart';
import 'spec.dart';
import 'stages.dart';

int _between(Mulberry32 r, int lo, int hi) => lo + r.nextInt(hi - lo + 1);

/// Plausible quantised features of a child's drawing.
FeatureVector randomFeatures(Mulberry32 r) => FeatureVector({
  'roundness': _between(r, 150, 900),
  'silhouetteCoverage': _between(r, 40, 400),
  'inkCoverage': _between(r, 30, 350),
  'solidity': _between(r, 500, 980),
  'spikiness': _between(r, 0, 350),
  'redShare': _between(r, 0, 800),
  'lineThickness': _between(r, 15, 150),
  'darkness': _between(r, 150, 850),
  'colorUnits': _between(r, 1, 12),
  'balancedHueCount': _between(r, 1, 5),
  'detailDensity': _between(r, 0, 400),
  'convexityDefects': _between(r, 0, 10),
  'elongation': _between(r, 100, 400),
  'symmetry': _between(r, 400, 850),
});

String _hash(Mulberry32 r) =>
    r.nextUint32().toRadixString(16).padLeft(8, '0') + 'ab' * 28;

/// A child's drawing: energy 50–97, skill 3–40 (kid-likeness ≈ 60–93).
Genome randomKid(V3Spec s, Mulberry32 r, {int? energy10, int? skill10}) =>
    Genome.derive(
      s,
      features: randomFeatures(r),
      energy10: energy10 ?? _between(r, 500, 970),
      skill10: skill10 ?? _between(r, 30, 400),
      imageHash: _hash(r),
    );

/// A polished / AI-like picture: hidden late bloomer.
Genome randomBloomer(V3Spec s, Mulberry32 r) => Genome.derive(
  s,
  features: randomFeatures(r),
  energy10: _between(r, 400, 900),
  skill10: _between(r, 760, 990),
  imageHash: _hash(r),
);

class SimStats {
  SimStats(this.name);
  final String name;
  int n = 0;
  int winsA = 0;
  int timeUps = 0;
  int heatUps = 0;
  final List<int> ticks = [];
  int actions = 0;

  double get winRateA => winsA / n;
  double get avgSeconds => ticks.fold<int>(0, (a, b) => a + b) / n / 10;
  int pct(int p) {
    final s = [...ticks]..sort();
    return s[(s.length - 1) * p ~/ 100];
  }

  double get actionsPerSide => actions / n / 2;

  @override
  String toString() =>
      '${name.padRight(52)} A ${(winRateA * 100).toStringAsFixed(1).padLeft(5)}% '
      '| avg ${avgSeconds.toStringAsFixed(1).padLeft(5)}s '
      'p10 ${(pct(10) / 10).toStringAsFixed(0).padLeft(3)}s '
      'p90 ${(pct(90) / 10).toStringAsFixed(0).padLeft(3)}s '
      'max ${(pct(100) / 10).toStringAsFixed(0).padLeft(3)}s '
      '| acts/side ${actionsPerSide.toStringAsFixed(1)} '
      '| heat ${(heatUps * 100 / n).toStringAsFixed(0)}% cap $timeUps';
}

typedef PairMaker = (FighterSetup, FighterSetup) Function(Mulberry32 r);

SimStats runScenario(
  V3Spec s,
  String name,
  int n,
  PairMaker make, {
  int seed = 1,
  int? thinkTicks,
  int? thinkTicksA,
  AiTier tierA = AiTier.normal,
  AiTier tierB = AiTier.normal,
}) {
  final r = Mulberry32(fnv1a32('$name/$seed'));
  final out = SimStats(name);
  final ca = aiController(thinkTicks: thinkTicksA ?? thinkTicks, tier: tierA);
  final cb = aiController(thinkTicks: thinkTicks, tier: tierB);
  for (var i = 0; i < n; i++) {
    final (a, b) = make(r);
    final battle = Battle(s, a, b, seed: r.nextUint32(), recordEvents: false);
    final w = battle.run(ca, cb);
    out.n++;
    if (w == 0) out.winsA++;
    if (battle.endReason == 'timeUp') out.timeUps++;
    if (battle.tick > s.heatUpStartTick) out.heatUps++;
    out.ticks.add(battle.tick);
    out.actions += battle.fighters[0].actions + battle.fighters[1].actions;
  }
  return out;
}

/// Same stats with one stat scaled to [pct] %, the difference taken from /
/// given to the other eight combat stats (HP and that stat excluded) so the
/// total is unchanged.
List<int> reshape(List<int> st, Stat which, int pct) {
  final out = List.of(st);
  final delta = st[which.index] * pct ~/ 100 - st[which.index];
  out[which.index] += delta;
  final others = [
    for (final x in Stat.values)
      if (x != which && x != Stat.hp) x.index,
  ];
  final share = largestRemainder(delta, [for (final i in others) st[i]]);
  for (var k = 0; k < others.length; k++) {
    out[others[k]] -= share[k];
    if (out[others[k]] < 1) out[others[k]] = 1;
  }
  return out;
}

FighterSetup withStats(FighterSetup f, List<int> st) => f.withStats(st);

/// The standard scenario list (docs §10). [n] battles each.
List<SimStats> standardScenarios(V3Spec s, {int n = 4000}) {
  final res = <SimStats>[];
  SimStats run(
    String name,
    PairMaker m, {
    AiTier ta = AiTier.normal,
    AiTier tb = AiTier.normal,
    int? thinkA,
  }) {
    final x = runScenario(
      s,
      name,
      n,
      m,
      tierA: ta,
      tierB: tb,
      thinkTicksA: thinkA,
    );
    res.add(x);
    return x;
  }

  for (final lv in [1, 50, 100]) {
    run('mirror Lv$lv', (r) {
      final g = randomKid(s, r);
      final f = setupAt(s, g, lv);
      return (f, f);
    });
  }
  run(
    'kid vs kid Lv20 (random drawings)',
    (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)),
  );
  for (final lv in [1, 10, 50]) {
    run('triangle: same stats, A beats B, Lv$lv', (r) {
      final g = randomKid(s, r);
      final a = Attr.values[r.nextInt(3)];
      return (setupAt(s, g, lv, attr: a), setupAt(s, g, lv, attr: a.beats));
    });
  }
  run('triangle: random kids, A beats B, Lv20', (r) {
    final a = Attr.values[r.nextInt(3)];
    return (
      setupAt(s, randomKid(s, r), 20, attr: a),
      setupAt(s, randomKid(s, r), 20, attr: a.beats),
    );
  });
  for (final pct in [150, 200]) {
    run('AGI x${pct / 100} same total, Lv20', (r) {
      final g = randomKid(s, r);
      final f = setupAt(s, g, 20);
      return (withStats(f, reshape(f.stats, Stat.agi, pct)), f);
    });
  }
  for (final st in Stat.values) {
    run('${st.code} +50% (others equal), Lv20', (r) {
      final f = setupAt(s, randomKid(s, r), 20);
      final x = List.of(f.stats);
      x[st.index] = x[st.index] * 3 ~/ 2;
      return (withStats(f, x), f);
    });
  }
  run(
    'kid K~95 vs kid K~60, Lv20',
    (r) => (
      setupAt(s, randomKid(s, r, energy10: 960, skill10: 60), 20),
      setupAt(s, randomKid(s, r, energy10: 520, skill10: 380), 20),
    ),
  );
  for (final lv in [1, 10, 30, 49]) {
    run(
      'kid vs hidden bloomer, both Lv$lv',
      (r) => (
        setupAt(s, randomKid(s, r), lv),
        setupAt(s, randomBloomer(s, r), lv),
      ),
    );
  }
  for (final lv in [50, 75, 100]) {
    run(
      'bloomer vs kid, both Lv$lv',
      (r) => (
        setupAt(s, randomBloomer(s, r), lv),
        setupAt(s, randomKid(s, r), lv),
      ),
    );
  }
  run(
    'bloomer Lv100 vs kid K~95 Lv100',
    (r) => (
      setupAt(s, randomBloomer(s, r), 100),
      setupAt(s, randomKid(s, r, energy10: 960, skill10: 60), 100),
    ),
  );
  for (final (hi, lo) in [(6, 1), (15, 10), (55, 50), (100, 95), (60, 50)]) {
    run('kid Lv$hi vs kid Lv$lo', (r) {
      final g = randomKid(s, r);
      return (setupAt(s, g, hi), setupAt(s, randomKid(s, r), lo));
    });
  }
  run(
    'AI strong vs normal, Lv20',
    (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)),
    ta: AiTier.strong,
  );
  run(
    'AI normal vs weak, Lv20',
    (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)),
    tb: AiTier.weak,
  );
  run(
    'pre-selecting kid (0 s) vs おまかせ (1 s), Lv20',
    (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)),
    thinkA: 0,
  );
  run(
    'slow chooser (3 s) vs fast (1 s), Lv20',
    (r) => (setupAt(s, randomKid(s, r), 20), setupAt(s, randomKid(s, r), 20)),
    thinkA: 30,
  );
  return res;
}

/// Player = random kid at the recommended level (ふつう おまかせ, 1 s), CPU
/// = the stage's bundled doodle from [cpuGenomes] (or a random kid when the
/// id is missing) at the stage's CPU level, power % and AI tier.
SimStats simulateStage(
  V3Spec s,
  Stage st, {
  int n = 1000,
  Map<String, Genome> cpuGenomes = const {},
  int? powerPct,
  int seed = 1,
}) => runScenario(
  s,
  'stage ${st.stage} (Lv${st.recommendedLevel}, ${st.cpuId}, '
  'cpu ${st.cpuPowerPct}%, ${st.tier.name})',
  n,
  (r) {
    final g =
        cpuGenomes[st.cpuId] ??
        randomKid(
          s,
          r,
          energy10: _between(r, 650, 900),
          skill10: _between(r, 50, 300),
        );
    return (
      setupAt(s, randomKid(s, r), st.recommendedLevel),
      setupAt(s, g, st.cpuLevel, powerPct: powerPct ?? st.cpuPowerPct),
    );
  },
  thinkTicksA: 10,
  tierB: st.tier,
  seed: seed,
);

/// Target win rate (%) of a child at the recommended level, by position in
/// a world (docs/GAME_DESIGN_V2.md §7: 85 → 63, boss ≈56).
const List<int> kStageTargetWinPct = [85, 82, 80, 77, 75, 71, 68, 65, 63, 56];

/// CPU stat % for [st] that brings the child's win rate to the target
/// (bisection over 50..140 %), with the stage's real CPU doodle and tier.
int tuneStagePower(
  V3Spec s,
  Stage st,
  Map<String, Genome> cpuGenomes, {
  int n = 400,
}) {
  final target = kStageTargetWinPct[st.position - 1] * 10;
  var lo = 50; // child wins more than the target here
  var hi = 140;
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    final r = simulateStage(
      s,
      st,
      n: n,
      cpuGenomes: cpuGenomes,
      powerPct: mid,
      seed: 7,
    );
    if (r.winsA * 1000 ~/ r.n > target) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}
