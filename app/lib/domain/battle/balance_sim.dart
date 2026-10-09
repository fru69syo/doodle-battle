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
  });

  final double energy;
  final double skill;
  final int level;

  /// Fixed element, or random when null.
  final ElementType? element;
  final AiTier tier;

  /// Use an even 25% split instead of random weights.
  final bool even;
}

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
    var state = initBattle(
      spec,
      FighterSetup(
        element: elA,
        level: a.level,
        stats: statsAtLevel(spec, baseA, a.level, const {}),
      ),
      FighterSetup(
        element: elB,
        level: b.level,
        stats: statsAtLevel(spec, baseB, b.level, const {}),
      ),
    );
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

const kid = SimSide(energy: 80, skill: 15);
const shobo = SimSide(energy: 80, skill: 90);

/// The standard scenario set documented in docs/BATTLE.md.
List<SimResult> standardScenarios(BattleSpec spec, {int n = 4000}) => [
  simulate(spec, 'kid vs shobo (Lv1)', kid, shobo, n: n, seed: 11),
  simulate(
    spec,
    'kid vs shobo (Lv10)',
    const SimSide(energy: 80, skill: 15, level: 10),
    const SimSide(energy: 80, skill: 90, level: 10),
    n: n,
    seed: 12,
  ),
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
  simulate(
    spec,
    'Lv6 vs Lv1',
    const SimSide(energy: 80, skill: 15, level: 6),
    kid,
    n: n,
    seed: 18,
  ),
  simulate(
    spec,
    'Lv15 vs Lv10',
    const SimSide(energy: 80, skill: 15, level: 15),
    const SimSide(energy: 80, skill: 15, level: 10),
    n: n,
    seed: 19,
  ),
  simulate(
    spec,
    'Lv30 vs Lv25',
    const SimSide(energy: 80, skill: 15, level: 30),
    const SimSide(energy: 80, skill: 15, level: 25),
    n: n,
    seed: 20,
  ),
  simulate(
    spec,
    'shobo Lv6 vs kid Lv1',
    const SimSide(energy: 80, skill: 90, level: 6),
    kid,
    n: n,
    seed: 21,
  ),
  simulate(spec, 'shobo vs shobo', shobo, shobo, n: n, seed: 26),
  simulate(
    spec,
    'shobo Lv30 vs kid Lv1',
    const SimSide(energy: 80, skill: 90, level: 30),
    kid,
    n: n,
    seed: 27,
  ),
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
];
