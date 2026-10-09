import 'package:doodle_battle/domain/element_type.dart';
import 'package:doodle_battle/features/drawing_analysis/drawing_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

DrawingFeatures _features({
  double roundness = 0.5,
  double inkCoverage = 0.2,
  double spikiness = 0.1,
  double redShare = 0.2,
  double lineThickness = 6,
  double darkness = 0.3,
  double solidity = 0.8,
  double elongation = 1.3,
  double chromaticShare = 0.8,
  double dominantHue = 0,
  double dominantHueShare = 1,
  int balancedHueCount = 1,
}) => DrawingFeatures.fromMap({
  'inkCoverage': inkCoverage,
  'bboxCoverage': 0.4,
  'roundness': roundness,
  'spikiness': spikiness,
  'redShare': redShare,
  'lineThickness': lineThickness,
  'darkness': darkness,
  'solidity': solidity,
  'elongation': elongation,
  'chromaticShare': chromaticShare,
  'dominantHue': dominantHue,
  'dominantHueShare': dominantHueShare,
  'balancedHueCount': balancedHueCount,
});

void main() {
  group('skillMultiplier (SPEC §3.2)', () {
    test('piecewise linear knots', () {
      expect(skillMultiplier(0), 1.0);
      expect(skillMultiplier(30), 1.0);
      expect(skillMultiplier(45), closeTo(0.95, 1e-9));
      expect(skillMultiplier(60), closeTo(0.90, 1e-9));
      expect(skillMultiplier(67.5), closeTo(0.80, 1e-9));
      expect(skillMultiplier(75), closeTo(0.70, 1e-9));
      expect(skillMultiplier(75.01), 0.35);
      expect(skillMultiplier(100), 0.35);
    });

    test('budget = (200 + 2 * energy) * multiplier', () {
      expect(statBudget(0, 0), 200);
      expect(statBudget(100, 10), 400);
      expect(statBudget(50, 60), closeTo(270, 1e-9));
      expect(statBudget(100, 90), closeTo(140, 1e-9));
    });
  });

  group('stat distribution', () {
    test('every weight >= 0.15 and weights sum to 1', () {
      final extremes = [
        _features(),
        _features(
          roundness: 1,
          inkCoverage: 0.5,
          spikiness: 0,
          redShare: 0,
          lineThickness: 1,
          darkness: 0,
          solidity: 0,
          elongation: 1,
        ),
        _features(
          roundness: 0,
          inkCoverage: 0,
          spikiness: 0.6,
          redShare: 1,
          lineThickness: 1,
          darkness: 0,
          solidity: 0,
          elongation: 1,
        ),
        _features(
          roundness: 0,
          inkCoverage: 0,
          spikiness: 0,
          redShare: 0,
          lineThickness: 1,
          darkness: 0,
          solidity: 0,
          elongation: 8,
        ),
        DrawingFeatures.fromMap(const {}),
      ];
      for (final f in extremes) {
        final w = statWeights(f);
        expect(w.reduce((a, b) => a + b), closeTo(1, 1e-9));
        for (final x in w) {
          expect(x, greaterThanOrEqualTo(kMinStatWeight - 1e-12));
        }
      }
    });

    test('stat total equals the rounded budget', () {
      for (final (e, s) in [
        (0.0, 0.0),
        (37.3, 12.0),
        (88.8, 66.6),
        (100.0, 99.0),
      ]) {
        final stats = computeBaseStats(_features(), e, s);
        expect(stats.total, statBudget(e, s).round());
      }
    });

    test('shape drives the distribution', () {
      final round = computeBaseStats(
        _features(roundness: 0.95, inkCoverage: 0.3, spikiness: 0),
        80,
        10,
      );
      final spiky = computeBaseStats(
        _features(roundness: 0.2, spikiness: 0.4, redShare: 0.8),
        80,
        10,
      );
      final long = computeBaseStats(
        _features(roundness: 0.2, elongation: 4, lineThickness: 2),
        80,
        10,
      );
      expect(round.hp, greaterThan(round.atk));
      expect(spiky.atk, greaterThan(spiky.hp));
      expect(long.spd, greaterThan(long.def));
    });

    test('map round-trip gives identical stats', () {
      final f = _features(roundness: 0.7, spikiness: 0.2);
      expect(
        computeBaseStatsFromMap(f.toMap(), 64.2, 41.5),
        computeBaseStats(f, 64.2, 41.5),
      );
    });
  });

  test('blendCloudSkill is 0.6 device + 0.4 cloud, clamped', () {
    expect(blendCloudSkill(20, 70), closeTo(40, 1e-9));
    expect(blendCloudSkill(100, 100), 100);
    expect(blendCloudSkill(0, -50), 0);
  });

  group('computeElement', () {
    test('hue bands', () {
      ElementType el(double hue) => computeElement(_features(dominantHue: hue));
      expect(el(0), ElementType.fire);
      expect(el(30), ElementType.fire); // orange
      expect(el(340), ElementType.fire); // pink
      expect(el(55), ElementType.thunder);
      expect(el(120), ElementType.leaf);
      expect(el(200), ElementType.water);
      expect(el(230), ElementType.water);
      expect(el(285), ElementType.shadow); // purple
    });

    test('achromatic drawings are shadow, balanced hues are rainbow', () {
      expect(
        computeElement(_features(chromaticShare: 0.1)),
        ElementType.shadow,
      );
      expect(
        computeElement(_features(balancedHueCount: 4, dominantHueShare: 0.3)),
        ElementType.rainbow,
      );
      expect(
        computeElement(_features(balancedHueCount: 4, dominantHueShare: 0.6)),
        ElementType.fire,
      );
    });
  });

  test('energy gate crushes near-empty drawings', () {
    final empty = DrawingFeatures.fromMap(const {
      'inkCoverage': 0.001,
      'bboxCoverage': 0.5,
      'colorCount': 6,
      'lineThickness': 20,
    });
    expect(computeEnergy(empty), 0);
    expect(rejectReasonFor(empty), DrawingRejectReason.nearlyEmpty);
  });
}
