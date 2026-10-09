import 'dart:math' as math;

import '../../domain/stats.dart';
import 'drawing_features.dart';
import 'src/raster.dart';

/// Minimum share of the budget that every stat receives (SPEC §3.2).
const double kMinStatWeight = 0.15;

/// SPEC §3.2 skill multiplier.
double skillMultiplier(double skill) {
  if (skill <= 30) return 1.0;
  if (skill <= 60) return 1.0 - 0.10 * (skill - 30) / 30;
  if (skill <= 75) return 0.90 - 0.20 * (skill - 60) / 15;
  return 0.35;
}

/// SPEC §3.2: budget = (200 + 2 * energy) * skillMultiplier(skill).
double statBudget(double energy, double skill) =>
    (200 + 2 * energy.clamp(0, 100)) * skillMultiplier(skill.clamp(0, 100));

/// Final skill when the cloud judge answered (SPEC §3.3): 0.6 device + 0.4
/// cloud, clamped to 0..100.
double blendCloudSkill(double device, double cloud) =>
    (0.6 * device + 0.4 * cloud).clamp(0, 100).toDouble();

/// hp / atk / def / spd weights; each >= [kMinStatWeight], summing to 1.
///
/// Affinities (0..1) per stat:
/// * hp  ← 0.6 roundness + 0.4 ink coverage (saturating at 30%)
/// * atk ← 0.6 spikiness (saturating at 0.3) + 0.4 red share
/// * def ← 0.4 line thickness (saturating at 12px) + 0.3 darkness
///         + 0.3 solidity (blockiness)
/// * spd ← 0.6 elongation (1 → 0, 3 → 1) + 0.4 thinness of lines
///
/// weight_k = 0.15 + 0.40 * affinity_k / Σ affinity.
List<double> statWeights(DrawingFeatures f) {
  final thick = ramp(f.lineThickness, 1, 12);
  final aff = [
    0.6 * f.roundness + 0.4 * ramp(f.inkCoverage, 0, 0.3),
    0.6 * ramp(f.spikiness, 0, 0.3) + 0.4 * clamp01(f.redShare),
    0.4 * thick + 0.3 * clamp01(f.darkness) + 0.3 * clamp01(f.solidity),
    0.6 * ramp(f.elongation, 1, 3) + 0.4 * (1 - thick),
  ];
  final sum = aff.fold<double>(0, (a, b) => a + b);
  const free = 1 - 4 * kMinStatWeight;
  return [
    for (final a in aff)
      kMinStatWeight + (sum <= 1e-9 ? free / 4 : free * a / sum),
  ];
}

/// Level-1 stats from features and scores (SPEC §3.2). Pure and
/// deterministic, so stats can be re-derived after cloud blending or by the
/// server. The integer total equals `round(budget)` (largest remainder).
Stats computeBaseStats(DrawingFeatures f, double energy, double skill) {
  final budget = statBudget(energy, skill);
  final weights = statWeights(f);
  final total = budget.round();
  final exact = [for (final w in weights) w * budget];
  final ints = [for (final e in exact) e.floor()];
  var remaining = total - ints.fold<int>(0, (a, b) => a + b);
  final order = List.generate(4, (i) => i)
    ..sort((a, b) {
      final ra = exact[a] - ints[a];
      final rb = exact[b] - ints[b];
      final c = rb.compareTo(ra);
      return c != 0 ? c : a.compareTo(b);
    });
  for (var k = 0; remaining > 0; k = (k + 1) % 4, remaining--) {
    ints[order[k]]++;
  }
  return Stats(
    hp: math.max(0, ints[0]),
    atk: math.max(0, ints[1]),
    def: math.max(0, ints[2]),
    spd: math.max(0, ints[3]),
  );
}

/// Same as [computeBaseStats] but from a persisted feature map
/// (`Character.features`).
Stats computeBaseStatsFromMap(
        Map<String, num> features, double energy, double skill) =>
    computeBaseStats(DrawingFeatures.fromMap(features), energy, skill);
