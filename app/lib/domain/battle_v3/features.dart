/// Quantised appearance features: the integer contract between the drawing
/// analyser and every engine port (docs/GAME_DESIGN_V2.md §3.2, §9).
library;

import 'spec.dart';

/// Keys of the quantised feature vector, in canonical order.
const List<String> kFeatureKeys = [
  'roundness',
  'silhouetteCoverage',
  'inkCoverage',
  'solidity',
  'spikiness',
  'redShare',
  'lineThickness',
  'darkness',
  'colorUnits',
  'balancedHueCount',
  'detailDensity',
  'convexityDefects',
  'elongation',
  'symmetry',
];

/// Inclusive valid range of every quantised feature (anything outside is
/// rejected by the server validator and clamped by [FeatureVector.clamped]).
const Map<String, (int, int)> kFeatureRanges = {
  'roundness': (0, 1000),
  'silhouetteCoverage': (0, 1000),
  'inkCoverage': (0, 1000),
  'solidity': (0, 1000),
  'spikiness': (0, 1000),
  'redShare': (0, 1000),
  'lineThickness': (0, 600),
  'darkness': (0, 1000),
  'colorUnits': (0, 30),
  'balancedHueCount': (0, 12),
  'detailDensity': (0, 1000),
  'convexityDefects': (0, 50),
  'elongation': (100, 1000),
  'symmetry': (0, 1000),
};

/// Quantised feature vector. Missing keys default to a "neutral" value.
class FeatureVector {
  const FeatureVector(this.values);

  /// Integer features (units in [kFeatureUnits]).
  final Map<String, int> values;

  static const Map<String, int> defaults = {
    'roundness': 500,
    'silhouetteCoverage': 150,
    'inkCoverage': 120,
    'solidity': 750,
    'spikiness': 100,
    'redShare': 200,
    'lineThickness': 50,
    'darkness': 500,
    'colorUnits': 5,
    'balancedHueCount': 2,
    'detailDensity': 150,
    'convexityDefects': 3,
    'elongation': 160,
    'symmetry': 600,
  };

  int operator [](String k) => values[k] ?? defaults[k] ?? 0;

  /// Quantises the analyser's double features (`DrawingFeatures.toMap()`).
  /// This is the only floating-point step; the result is persisted and sent
  /// to the server so every engine starts from the same integers.
  factory FeatureVector.quantize(Map<String, num> raw) {
    int mille(String k) => ((raw[k] ?? 0) * 1000).round().clamp(0, 1000);
    return FeatureVector({
      for (final k in const [
        'roundness',
        'silhouetteCoverage',
        'inkCoverage',
        'solidity',
        'spikiness',
        'redShare',
        'darkness',
        'detailDensity',
        'symmetry',
      ])
        k: mille(k),
      'lineThickness': ((raw['lineThickness'] ?? 0) * 10).round().clamp(0, 600),
      'colorUnits':
          ((raw['colorCount'] ?? 0) * 2 + (raw['achromaticCount'] ?? 0))
              .round()
              .clamp(0, 30),
      'balancedHueCount': (raw['balancedHueCount'] ?? 0).round().clamp(0, 12),
      'convexityDefects': (raw['convexityDefects'] ?? 0).round().clamp(0, 50),
      'elongation': ((raw['elongation'] ?? 1) * 100).round().clamp(100, 1000),
    });
  }

  /// Parses a persisted / transmitted vector. Unknown keys are ignored,
  /// non-integers are rejected (null), values are clamped to range.
  static FeatureVector? tryParse(Object? json) {
    if (json is! Map) return null;
    final out = <String, int>{};
    for (final k in kFeatureKeys) {
      final v = json[k];
      if (v == null) continue;
      if (v is! int) return null;
      final (lo, hi) = kFeatureRanges[k]!;
      out[k] = v < lo ? lo : (v > hi ? hi : v);
    }
    return FeatureVector(out);
  }

  /// Every key present, in canonical order (persisted form).
  Map<String, int> toJson() => {for (final k in kFeatureKeys) k: this[k]};

  /// Ramp term by name (`round`, `inv:thick`, …) → 0..1000.
  int term(String name) {
    if (name.startsWith('inv:')) return 1000 - term(name.substring(4));
    final r = kRampTable[name];
    if (r == null) throw ArgumentError('unknown ramp $name');
    final v = this[r[0] as String];
    final lo = r[1] as int;
    final hi = r[2] as int;
    if (v <= lo) return 0;
    if (v >= hi) return 1000;
    return (v - lo) * 1000 ~/ (hi - lo);
  }
}
