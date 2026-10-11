/// PROTOTYPE — v2 character generation: kid-likeness, hidden late bloomer,
/// 10 stats from appearance features, per-stat growth, stats at a level.
/// docs/GAME_DESIGN_V2.md §2–§4. Integer maths only (portable).
library;

import '../battle/rng.dart';
import 'v2_spec.dart';

/// グー / チョキ / パー (+ none for support moves).
enum Attr {
  gu('グー'),
  choki('チョキ'),
  pa('パー'),
  none('むぞくせい');

  const Attr(this.label);
  final String label;

  /// The attribute this one beats.
  Attr? get beats => switch (this) {
    gu => choki,
    choki => pa,
    pa => gu,
    none => null,
  };

  /// The attribute that beats this one.
  Attr? get beatenBy => switch (this) {
    gu => pa,
    choki => gu,
    pa => choki,
    none => null,
  };
}

/// Floor division for possibly negative numerators (portable definition).
int floorDiv(int a, int b) {
  final q = a ~/ b;
  return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q;
}

/// Quantised feature vector: the integer contract between the analyser and
/// the engines (units in [kFeatureUnits]). Missing keys default to a
/// "neutral" value.
class FeatureVector {
  const FeatureVector(this.values);
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

/// uint32 seed from an image hash (first 8 hex digits; non-hex → FNV-1a).
int imageSeed(String imageHash) {
  if (imageHash.length >= 8) {
    final v = int.tryParse(imageHash.substring(0, 8), radix: 16);
    if (v != null) return v & mask32;
  }
  return fnv1a32(imageHash);
}

/// Kid-likeness 0..100 from energy / skill in tenths.
int kidLikeness(V2Spec s, int energy10, int skill10) {
  final e = energy10.clamp(0, 1000);
  final k = (1000 - skill10.clamp(0, 1000));
  return (s.kidEnergyWeight * e + s.kidSkillWeight * k + 50) ~/ 100;
}

/// Largest-remainder split of [total] by integer [shares] (ties → lower
/// index). Result sums exactly to [total].
List<int> largestRemainder(int total, List<int> shares) {
  final sum = shares.fold<int>(0, (a, b) => a + b);
  if (sum <= 0) {
    final each = total ~/ shares.length;
    final out = List<int>.filled(shares.length, each);
    for (var i = 0; i < total - each * shares.length; i++) {
      out[i]++;
    }
    return out;
  }
  final out = [for (final s in shares) total * s ~/ sum];
  final rem = [for (final s in shares) total * s % sum];
  var left = total - out.fold<int>(0, (a, b) => a + b);
  final order = List.generate(shares.length, (i) => i)
    ..sort((a, b) {
      final c = rem[b].compareTo(rem[a]);
      return c != 0 ? c : a.compareTo(b);
    });
  for (var k = 0; left > 0; k++, left--) {
    out[order[k % order.length]]++;
  }
  return out;
}

/// Origin verdicts that make a character a hidden late bloomer even when the
/// skill score is below the threshold (cloud `ai_generated`, on-device
/// `digital` / `printed` / `screen`).
const Set<String> kBloomerOrigins = {
  'ai_generated',
  'digital',
  'printed',
  'screen',
};

/// Everything derived once from a drawing. Immutable and deterministic.
class Genome {
  Genome._({
    required this.spec,
    required this.kid,
    required this.isBloomer,
    required this.attr,
    required this.jitterPct,
    required this.budget,
    required this.affinities,
    required this.base,
    required this.growthMille,
    required this.rebirthBase,
    required this.seed,
  });

  /// Builds the genome. [energy10]/[skill10] are the (cloud-blended) scores
  /// in tenths; [origin] is the strongest origin verdict, if any.
  factory Genome.derive(
    V2Spec s, {
    required FeatureVector features,
    required int energy10,
    required int skill10,
    required String imageHash,
    String? origin,
  }) {
    final seed = imageSeed(imageHash);
    final kid = kidLikeness(s, energy10, skill10);
    final bloomer =
        skill10 > s.bloomerSkillAbove10 || kBloomerOrigins.contains(origin);
    final rj = Mulberry32(deriveSeed(seed, 10));
    final jitterPct =
        s.budgetJitterMinPct + rj.nextUint32() % s.budgetJitterSpan;
    final luck = rj.nextUint32() % 1001;
    final aff = _affinities(s, features, luck, rj);
    final fullBudget =
        (s.budgetBase + s.budgetPerKid * kid) * jitterPct ~/ s.budgetDiv;
    final budget = bloomer
        ? fullBudget * s.bloomerPreBudgetPct ~/ 100
        : fullBudget;
    final base = _distribute(s, budget, aff);

    final rg = Mulberry32(deriveSeed(seed, 11));
    final raw = [
      for (var i = 0; i < 10; i++)
        s.growthRawBase +
            aff[i] ~/ s.growthRawAffinityDiv +
            rg.nextUint32() % s.growthRawJitterSpan,
    ];
    final growth = largestRemainder(s.growthTotalMillePerLevel, raw);

    List<int>? rebirth;
    if (bloomer) {
      final rr = Mulberry32(deriveSeed(seed, 13));
      final luck2 = rr.nextUint32() % 1001;
      final aff2 = _affinities(s, features, luck2, rr);
      final b2 =
          (s.budgetBase + s.budgetPerKid * s.rebirthKid) *
          jitterPct ~/
          s.budgetDiv *
          s.rebirthBudgetPct ~/
          100;
      rebirth = _distribute(s, b2, aff2);
    }
    return Genome._(
      spec: s,
      kid: kid,
      isBloomer: bloomer,
      attr: attributeOf(features),
      jitterPct: jitterPct,
      budget: budget,
      affinities: aff,
      base: base,
      growthMille: growth,
      rebirthBase: rebirth,
      seed: seed,
    );
  }

  final V2Spec spec;
  final int kid;

  /// Hidden. Never surfaced in UI text.
  final bool isBloomer;
  final Attr attr;
  final int jitterPct;
  final int budget;
  final List<int> affinities;

  /// Lv1 stats (pre-rebirth form for bloomers).
  final List<int> base;

  /// Per-stat growth per level in ‰ of the Lv1 stat (Σ = 400).
  final List<int> growthMille;

  /// Bloomers only: the re-generated "virtual Lv1" stats used from Lv50.
  final List<int>? rebirthBase;
  final int seed;

  bool rebornAt(int level) => isBloomer && level >= spec.rebirthLevel;

  /// Rated play (§8): stats re-computed at the sync level (Lv50). A bloomer
  /// whose real level is below the rebirth level keeps its pre-rebirth form
  /// (its growth formula is extended to the sync level).
  List<int> ratedStats(int actualLevel, {int syncLevel = 50}) =>
      statsAt(syncLevel, preForm: isBloomer && actualLevel < spec.rebirthLevel);

  /// Stats at [level] (1..maxLevel). [preForm] forces a bloomer's
  /// pre-rebirth formula (rated sync only).
  List<int> statsAt(int level, {bool preForm = false}) {
    final s = spec;
    final l = level.clamp(1, s.maxLevel);
    if (!isBloomer) {
      return [
        for (var i = 0; i < 10; i++)
          base[i] + base[i] * growthMille[i] * (l - 1) ~/ 1000,
      ];
    }
    if (l < s.rebirthLevel || preForm) {
      return [
        for (var i = 0; i < 10; i++)
          base[i] +
              base[i] *
                  growthMille[i] *
                  s.bloomerPreGrowthPct *
                  (l - 1) ~/
                  100000,
      ];
    }
    final rb = rebirthBase!;
    final pre = s.rebirthLevel - 1;
    final post = l - s.rebirthLevel;
    return [
      for (var i = 0; i < 10; i++)
        rb[i] +
            rb[i] *
                growthMille[i] *
                (100 * pre + (100 + s.bloomerPostGrowthBoostPct) * post) ~/
                100000,
    ];
  }

  /// Move budget factor (%) at [level].
  int moveFactorPct(int level) {
    final s = spec;
    final legend = level >= s.rebirthLevel ? s.legendMoveBonusPct : 0;
    if (isBloomer) {
      if (level < s.rebirthLevel) return s.bloomerPreMoveFactorPct;
      return s.moveFactorBasePct +
          s.rebirthKid ~/ s.moveFactorKidDiv +
          legend +
          s.bloomerRebirthMoveBonusPct;
    }
    return s.moveFactorBasePct + kid ~/ s.moveFactorKidDiv + legend;
  }

  static List<int> _affinities(
    V2Spec s,
    FeatureVector f,
    int luck,
    Mulberry32 rj,
  ) {
    final out = <int>[];
    for (final st in Stat.values) {
      final w = kAffinityTable[st.code]!;
      var sum = 0;
      w.forEach((term, weight) {
        sum += weight * (term == 'luck' ? luck : f.term(term));
      });
      var a = sum ~/ 100;
      a =
          a *
          (s.affinityJitterMinPct + rj.nextUint32() % s.affinityJitterSpan) ~/
          100;
      out.add(a < s.affinityFloor ? s.affinityFloor : a);
    }
    return out;
  }

  static List<int> _distribute(V2Spec s, int budget, List<int> aff) {
    final sumA = aff.fold<int>(0, (a, b) => a + b);
    final free = 1000 - 10 * s.minShareMille;
    return largestRemainder(budget, [
      for (final a in aff) s.minShareMille * sumA + free * a,
    ]);
  }
}

/// Shape → グー / チョキ / パー.
Attr attributeOf(FeatureVector f) {
  int score(String a) => (kAttributeRule[a]! as List).fold<int>(
    0,
    (acc, t) => acc + f.term(t as String),
  );
  final gu = score('gu');
  final choki = score('choki');
  final pa = score('pa');
  if (gu >= choki && gu >= pa) return Attr.gu;
  if (choki >= pa) return Attr.choki;
  return Attr.pa;
}

/// maxHp from stats.
int maxHpOf(V2Spec s, List<int> st) =>
    s.hpPerHp * st[Stat.hp.index] +
    s.hpPerVit * st[Stat.vit.index] +
    s.hpPerAvg * st.fold<int>(0, (a, b) => a + b) ~/ 10;
