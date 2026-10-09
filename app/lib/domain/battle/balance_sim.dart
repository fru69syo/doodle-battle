/// Monte Carlo balance simulation (dev tooling; used by
/// `tool/balance_sim.dart` and `test/domain/battle/balance_sim_test.dart`).
/// Not exported from `battle.dart`.
library;

import '../element_type.dart';
import '../stats.dart';
import 'battle_engine.dart';
import 'battle_spec.dart';
import 'battle_types.dart';
import 'cpu_ai.dart';
import 'cpu_roster.dart';
import 'growth.dart';
import 'rng.dart';

/// SPEC §3.2 skill multiplier.
double skillMultiplier(double s) {
  if (s <= 30) return 1.0;
  if (s <= 60) return 1.0 - 0.10 * (s - 30) / 30;
  if (s <= 75) return 0.90 - 0.20 * (s - 60) / 15;
  return 0.35;
}

/// Lv1 stats roughly as Vision will generate them (SPEC §3.2): budget split
/// with random weights, each weight >= 0.15. [rng] drives the weights.
Stats syntheticBaseStats(
  double energy,
  double skill,
  Mulberry32 rng, {
  bool even = false,
}) {
  final budget = (200 + 2 * energy) * skillMultiplier(skill);
  List<double> w;
  if (even) {
    w = [0.25, 0.25, 0.25, 0.25];
  } else {
    final raw = [for (var i = 0; i < 4; i++) 1 + rng.nextInt(1000)];
    final sum = raw.fold<int>(0, (a, b) => a + b);
    w = [for (final r in raw) 0.15 + 0.40 * r / sum];
  }
  return Stats(
    hp: (budget * w[0]).round(),
    atk: (budget * w[1]).round(),
    def: (budget * w[2]).round(),
    spd: (budget * w[3]).round(),
  );
}

class SimResult {
  SimResult(this.name);
  final String name;
  int battles = 0;
  int winsA = 0;
  int totalTurns = 0;
  int maxTurns = 0;
  int turnCapEnds = 0;
  final Map<int, int> turnHistogram = {};

  double get winRateA => winsA / battles;
  double get avgTurns => totalTurns / battles;

  /// Share of battles lasting [lo]..[hi] turns.
  double shareWithin(int lo, int hi) {
    var n = 0;
    turnHistogram.forEach((t, c) {
      if (t >= lo && t <= hi) n += c;
    });
    return n / battles;
  }

  @override
  String toString() =>
      '$name: A wins ${(winRateA * 100).toStringAsFixed(1)}% '
      '| avg ${avgTurns.toStringAsFixed(2)} turns '
      '| 4-8 turns ${(shareWithin(4, 8) * 100).toStringAsFixed(0)}% '
      '| max $maxTurns | turnCap $turnCapEnds/$battles';
}

/// Describes one side of a scenario.
class SimSide {
  const SimSide({
    required this.energy,
    required this.skill,
    this.level = 1,
    this.element,
    this.tier = AiTier.normal,
    this.even = false,
    this.seeds = false,
  });

  final double energy;
  final double skill;
  final int level;

  /// Fixed element, or random when null.
  final ElementType? element;
  final AiTier tier;

  /// Use an even 25% split instead of random weights.
  final bool even;

  /// Spend all (level-1) パワーのたね round-robin hp, atk, def, spd.
  final bool seeds;

  SimSide at(int level, {bool seeds = false}) => SimSide(
    energy: energy,
    skill: skill,
    level: level,
    element: element,
    tier: tier,
    even: even,
    seeds: seeds,
  );
}

Map<StatKind, int> _spreadSeeds(int n) => {
  for (var i = 0; i < StatKind.values.length; i++)
    StatKind.values[i]: n ~/ 4 + (i < n % 4 ? 1 : 0),
};

/// Runs [n] battles of [a] vs [b]. If [mirror] is set, b gets a's exact
/// stats and element (pure symmetry check).
SimResult simulate(
  BattleSpec spec,
  String name,
  SimSide a,
  SimSide b, {
  int n = 4000,
  int seed = 1,
  bool mirror = false,
}) {
  final res = SimResult(name);
  final meta = Mulberry32(seed);
  FighterSetup setup(SimSide s, Stats base, ElementType e) => FighterSetup(
    element: e,
    level: s.level,
    stats: statsAtLevel(
      spec,
      base,
      s.level,
      s.seeds ? _spreadSeeds(s.level - 1) : const {},
      isShobo: isShoboSkill(spec, s.skill),
    ),
  );
  for (var i = 0; i < n; i++) {
    final matchSeed = meta.nextUint32();
    final gen = Mulberry32(deriveSeed(matchSeed, 3));
    ElementType pick(ElementType? e) =>
        e ?? ElementType.values[gen.nextInt(ElementType.values.length)];
    final baseA = syntheticBaseStats(a.energy, a.skill, gen, even: a.even);
    final elA = pick(a.element);
    final baseB = mirror
        ? baseA
        : syntheticBaseStats(b.energy, b.skill, gen, even: b.even);
    final elB = mirror ? elA : pick(b.element);
    var state = initBattle(spec, setup(a, baseA, elA), setup(b, baseB, elB));
    final rng = Mulberry32(deriveSeed(matchSeed, 0));
    final aiA = Mulberry32(deriveSeed(matchSeed, 1));
    final aiB = Mulberry32(deriveSeed(matchSeed, 2));
    while (!state.isOver) {
      final actA = chooseCpuAction(spec, state, Side.a, a.tier, aiA);
      final actB = chooseCpuAction(spec, state, Side.b, b.tier, aiB);
      state = resolveTurn(spec, state, actA, actB, rng).state;
    }
    res.battles++;
    if (state.winner == Side.a) res.winsA++;
    res.totalTurns += state.turn;
    if (state.turn > res.maxTurns) res.maxTurns = state.turn;
    if (state.endReason == EndReason.turnCap) res.turnCapEnds++;
    res.turnHistogram[state.turn] = (res.turnHistogram[state.turn] ?? 0) + 1;
  }
  return res;
}

/// Player (kid scribble at the stage's recommended level, seeds spent,
/// ふつう AI) vs the CPU of [stage] (its doodle, level and AI tier).
SimResult simulateStage(
  BattleSpec spec,
  CpuRoster roster,
  CpuStage stage, {
  int n = 2000,
}) {
  final level = stage.recommendedLevel;
  final res = SimResult(
    'stage ${stage.stage} (${stage.cpuId} Lv${stage.level} '
    '${stage.aiTier.name}, player Lv$level)',
  );
  final meta = Mulberry32(9000 + stage.stage);
  final cpu = cpuFighterSetup(spec, stage, roster);
  for (var i = 0; i < n; i++) {
    final matchSeed = meta.nextUint32();
    final gen = Mulberry32(deriveSeed(matchSeed, 3));
    final base = syntheticBaseStats(80, 15, gen);
    final player = FighterSetup(
      element: ElementType.values[gen.nextInt(ElementType.values.length)],
      level: level,
      stats: statsAtLevel(
        spec,
        base,
        level,
        _spreadSeeds(level - 1),
        isShobo: false,
      ),
    );
    var state = initBattle(spec, player, cpu);
    final rng = Mulberry32(deriveSeed(matchSeed, 0));
    final aiA = Mulberry32(deriveSeed(matchSeed, 1));
    final aiB = Mulberry32(deriveSeed(matchSeed, 2));
    while (!state.isOver) {
      final actA = chooseCpuAction(spec, state, Side.a, AiTier.normal, aiA);
      final actB = chooseCpuAction(spec, state, Side.b, stage.aiTier, aiB);
      state = resolveTurn(spec, state, actA, actB, rng).state;
    }
    res.battles++;
    if (state.winner == Side.a) res.winsA++;
    res.totalTurns += state.turn;
    if (state.turn > res.maxTurns) res.maxTurns = state.turn;
    if (state.endReason == EndReason.turnCap) res.turnCapEnds++;
    res.turnHistogram[state.turn] = (res.turnHistogram[state.turn] ?? 0) + 1;
  }
  return res;
}

const kid = SimSide(energy: 80, skill: 15);
const shobo = SimSide(energy: 80, skill: 90);

/// しょぼキャラ growth scenarios (SPEC §4.2 「育てれば戦える」); a = しょぼ.
List<SimResult> shoboScenarios(BattleSpec spec, {int n = 4000}) => [
  for (final lv in [1, 10, 20, 30])
    simulate(
      spec,
      'shobo vs kid, both Lv$lv',
      shobo.at(lv),
      kid.at(lv),
      n: n,
      seed: 100 + lv,
    ),
  for (final lv in [10, 20, 30])
    simulate(
      spec,
      'shobo vs kid, both Lv$lv, seeds spent',
      shobo.at(lv, seeds: true),
      kid.at(lv, seeds: true),
      n: n,
      seed: 140 + lv,
    ),
  simulate(
    spec,
    'shobo Lv30 vs kid Lv15',
    shobo.at(30),
    kid.at(15),
    n: n,
    seed: 131,
  ),
  simulate(
    spec,
    'shobo Lv30 vs kid Lv15, seeds spent',
    shobo.at(30, seeds: true),
    kid.at(15, seeds: true),
    n: n,
    seed: 132,
  ),
  simulate(
    spec,
    'shobo Lv30 vs kid Lv13',
    shobo.at(30),
    kid.at(13),
    n: n,
    seed: 133,
  ),
  simulate(
    spec,
    'shobo Lv30 vs kid Lv17',
    shobo.at(30),
    kid.at(17),
    n: n,
    seed: 134,
  ),
  simulate(spec, 'shobo vs shobo', shobo, shobo, n: n, seed: 26),
];

/// The standard scenario set documented in docs/BATTLE.md.
List<SimResult> standardScenarios(BattleSpec spec, {int n = 4000}) => [
  simulate(
    spec,
    'mirror (equal stats)',
    kid,
    kid,
    n: n,
    seed: 13,
    mirror: true,
  ),
  simulate(spec, 'kid vs kid (random spreads)', kid, kid, n: n, seed: 14),
  simulate(
    spec,
    'type advantage (fire vs leaf)',
    const SimSide(energy: 80, skill: 15, element: ElementType.fire),
    const SimSide(energy: 80, skill: 15, element: ElementType.leaf),
    n: n,
    seed: 15,
  ),
  simulate(
    spec,
    'type advantage, even stats (thunder vs water)',
    const SimSide(
      energy: 80,
      skill: 15,
      element: ElementType.thunder,
      even: true,
    ),
    const SimSide(
      energy: 80,
      skill: 15,
      element: ElementType.water,
      even: true,
    ),
    n: n,
    seed: 16,
  ),
  simulate(
    spec,
    'shadow vs rainbow (mutual)',
    const SimSide(energy: 80, skill: 15, element: ElementType.shadow),
    const SimSide(energy: 80, skill: 15, element: ElementType.rainbow),
    n: n,
    seed: 17,
  ),
  simulate(spec, 'Lv6 vs Lv1', kid.at(6), kid, n: n, seed: 18),
  simulate(spec, 'Lv15 vs Lv10', kid.at(15), kid.at(10), n: n, seed: 19),
  simulate(spec, 'Lv30 vs Lv25', kid.at(30), kid.at(25), n: n, seed: 20),
  simulate(
    spec,
    'strong AI vs normal AI',
    const SimSide(energy: 80, skill: 15, tier: AiTier.strong),
    kid,
    n: n,
    seed: 22,
  ),
  simulate(
    spec,
    'strong AI vs weak AI',
    const SimSide(energy: 80, skill: 15, tier: AiTier.strong),
    const SimSide(energy: 80, skill: 15, tier: AiTier.weak),
    n: n,
    seed: 25,
  ),
  simulate(
    spec,
    'normal AI vs weak AI',
    kid,
    const SimSide(energy: 80, skill: 15, tier: AiTier.weak),
    n: n,
    seed: 23,
  ),
  simulate(
    spec,
    'weak vs weak (guard-heavy)',
    const SimSide(energy: 80, skill: 15, tier: AiTier.weak),
    const SimSide(energy: 80, skill: 15, tier: AiTier.weak),
    n: n,
    seed: 24,
  ),
  ...shoboScenarios(spec, n: n),
];
