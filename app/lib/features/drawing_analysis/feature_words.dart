/// Positive words about a drawing, derived from its features (SPEC §11.1).
///
/// They describe *what is special* about a drawing ("thick, bold lines",
/// "lots of colours"); they are never a ranking of how good it is, and they
/// never reveal skill / energy or whether the character is internally weak.
/// Every drawing gets at least two words.
library;

import 'dart:math' as math;

import 'src/raster.dart';

/// A positive trait shown on the birth screen and in the ずかん.
enum DrawingTrait {
  lineVigour('せんの いきおい'),
  colourful('いろの にぎやかさ'),
  uniqueShape('かたちの ユニークさ'),
  round('まんまる パワー'),
  spiky('とげとげ パワー'),
  big('かみ いっぱいの おおきさ'),
  filled('ぬりぬり パワー'),
  pattern('もようの たのしさ'),
  long('すらっと ながい かたち'),
  dark('くろの かっこよさ');

  const DrawingTrait(this.label);

  /// Hiragana/katakana label for children.
  final String label;
}

/// The [count] most characteristic traits of a drawing with feature map
/// [features] (`DrawingFeatures.toMap()` keys), strongest first.
///
/// Deterministic; scores are relative "how characteristic", never "how
/// good". Falls back to always-true traits so there are at least two.
List<DrawingTrait> positiveTraits(Map<String, num> features, {int count = 3}) {
  double f(String k, [double fallback = 0]) =>
      (features[k] ?? fallback).toDouble();
  final scores = <DrawingTrait, double>{
    DrawingTrait.lineVigour:
        0.6 * ramp(f('lineThickness'), 2, 10) + 0.4 * ramp(f('wobble'), 1, 5),
    DrawingTrait.colourful: ramp(
      f('colorCount') + 0.5 * f('achromaticCount'),
      1.5,
      5,
    ),
    DrawingTrait.uniqueShape:
        0.5 * ramp(f('convexityDefects'), 1, 6) +
        0.5 * (1 - ramp(f('symmetry', 0.5), 0.4, 0.85)),
    DrawingTrait.round: ramp(f('roundness'), 0.55, 0.85),
    DrawingTrait.spiky: ramp(f('spikiness'), 0.12, 0.35),
    DrawingTrait.big: ramp(math.sqrt(f('bboxCoverage')), 0.35, 0.7),
    DrawingTrait.filled: ramp(f('inkCoverage'), 0.08, 0.3),
    DrawingTrait.pattern: ramp(f('detailDensity'), 0.2, 0.6),
    DrawingTrait.long: ramp(f('elongation', 1), 1.6, 3),
    DrawingTrait.dark: f('dominantHue', -1) < 0
        ? 0.8
        : 1 - ramp(f('chromaticShare', 1), 0.1, 0.35),
  };
  final ranked = scores.entries.where((e) => e.value >= 0.3).toList()
    ..sort((a, b) {
      final d = b.value.compareTo(a.value);
      return d != 0 ? d : a.key.index.compareTo(b.key.index);
    });
  final out = [for (final e in ranked.take(count)) e.key];
  for (final t in [DrawingTrait.lineVigour, DrawingTrait.uniqueShape]) {
    if (out.length >= math.min(2, count)) break;
    if (!out.contains(t)) out.add(t);
  }
  return out;
}
