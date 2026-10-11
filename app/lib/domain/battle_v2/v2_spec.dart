/// PROTOTYPE (v2.0 game design spike) — reference constants for the v2 combat
/// model. Not wired into the app. The normative copy is
/// `shared/battle_spec_v3/battle_spec_v3.json`, generated from [V2Spec.toJson]
/// by `dart run tool/v2_sim.dart spec` (a test checks they match).
///
/// Every number here is an integer. All engine maths is integer maths with
/// floor division on non-negative operands, so a port to TS / C# / GDScript is
/// bit-exact (see docs/GAME_DESIGN_V2.md §9).
library;

/// The ten stats, in canonical order (index = position in every stat array).
enum Stat {
  hp('HP'),
  sp('SP'),
  str('STR'),
  vit('VIT'),
  def('DEF'),
  intl('INT'),
  res('RES'),
  dex('DEX'),
  agi('AGI'),
  luk('LUK');

  const Stat(this.code);

  /// Upper-case code used in JSON (`"STR"`).
  final String code;

  static Stat fromCode(String c) => Stat.values.firstWhere(
    (s) => s.code == c,
    orElse: () {
      throw FormatException('unknown stat $c');
    },
  );
}

/// Tunable parameters of the v2 model. Defaults are the tuned values
/// (docs/GAME_DESIGN_V2.md §10); the simulator builds variants with
/// [copyWith] to explore.
class V2Spec {
  const V2Spec({
    this.specVersion = 3,
    // --- character generation -------------------------------------------
    this.kidEnergyWeight = 6,
    this.kidSkillWeight = 4,
    this.budgetBase = 1400,
    this.budgetPerKid = 3,
    this.budgetDiv = 400,
    this.budgetJitterMinPct = 97,
    this.budgetJitterSpan = 7,
    this.bloomerSkillAbove10 = 750,
    this.bloomerPreBudgetPct = 50,
    this.bloomerPreGrowthPct = 100,
    this.rebirthLevel = 50,
    this.rebirthKid = 75,
    this.rebirthBudgetPct = 100,
    this.bloomerPostGrowthBoostPct = 12,
    this.minShareMille = 50,
    this.affinityJitterMinPct = 85,
    this.affinityJitterSpan = 31,
    this.affinityFloor = 50,
    this.growthTotalMillePerLevel = 400,
    this.growthRawBase = 700,
    this.growthRawAffinityDiv = 3,
    this.growthRawJitterSpan = 301,
    this.hpPerHp = 3,
    this.hpPerVit = 2,
    this.hpPerAvg = 5,
    // --- levels --------------------------------------------------------------
    this.maxLevel = 100,
    this.xpBase = 60,
    this.xpPerLevel = 20,
    this.xpQuadNum = 3,
    this.xpQuadDen = 4,
    // --- moves ---------------------------------------------------------------
    this.slotBudgets = const [100, 100, 120, 150],
    this.slotUnlockLevels = const [1, 1, 10, 50],
    this.moveFactorBasePct = 95,
    this.moveFactorKidDiv = 10,
    this.bloomerPreMoveFactorPct = 70,
    this.legendMoveBonusPct = 5,
    this.bloomerRebirthMoveBonusPct = 0,
    this.maxDiscountPct = 50,
    // --- ATB -----------------------------------------------------------------
    this.tickHz = 10,
    this.gaugeMax = 10000,
    this.gaugeFillPerTick = 280,
    this.agiWeightPct = 30,
    this.decisionTicks = 50,
    this.spMaxCenti = 10000,
    this.spStartCenti = 4000,
    this.spRegenCentiPerTick = 25,
    this.spWeightPct = 50,
    // --- damage --------------------------------------------------------------
    this.damageScalePct = 60,
    this.typeAdvantagePct = 150,
    this.typeDisadvantagePct = 75,
    this.typeStrengthPct = 100,
    this.varianceMinPct = 90,
    this.varianceSpan = 11,
    this.critBaseMille = 50,
    this.critLukMille = 60,
    this.critMultiplierPct = 150,
    this.hitSkewPct = 15,
    this.hitMinPct = 30,
    this.stageDen = 4,
    this.maxStage = 2,
    // --- statuses ------------------------------------------------------------
    this.poisonMillePerSecond = 15,
    this.poisonTicks = 80,
    this.paralyzeFillPct = 60,
    this.paralyzeTicks = 60,
    this.statusLukSkewPct = 50,
    this.healDecaySteps = const [100, 75, 50, 25],
    // --- termination -----------------------------------------------------------
    this.heatUpStartTick = 600,
    this.heatUpPctPerSecond = 3,
    this.hardCapTick = 1800,
  });

  final int specVersion;

  /// kid = (kidEnergyWeight·e10 + kidSkillWeight·(1000 − s10) + 50) / 100,
  /// e10 / s10 = energy / skill in tenths (0..1000).
  final int kidEnergyWeight;
  final int kidSkillWeight;

  /// budget = (budgetBase + budgetPerKid·kid) · jitterPct / budgetDiv.
  final int budgetBase;
  final int budgetPerKid;
  final int budgetDiv;

  /// jitterPct = budgetJitterMinPct + u32 % budgetJitterSpan (97..103).
  final int budgetJitterMinPct;
  final int budgetJitterSpan;

  /// Hidden late bloomer when s10 > this (or an origin flag, see docs).
  final int bloomerSkillAbove10;
  final int bloomerPreBudgetPct;
  final int bloomerPreGrowthPct;
  final int rebirthLevel;
  final int rebirthKid;
  final int rebirthBudgetPct;
  final int bloomerPostGrowthBoostPct;

  /// Every stat gets at least minShareMille ‰ of the budget; the remaining
  /// 1000 − 10·minShareMille ‰ is split by affinity.
  final int minShareMille;
  final int affinityJitterMinPct;
  final int affinityJitterSpan;
  final int affinityFloor;

  /// Σ per-stat growth (‰ of the Lv1 stat per level) = this (avg 40 ‰ = 4 %).
  final int growthTotalMillePerLevel;
  final int growthRawBase;
  final int growthRawAffinityDiv;
  final int growthRawJitterSpan;

  /// maxHp = hpPerHp·HP + hpPerVit·VIT + hpPerAvg·(Σ all 10 stats)/10.
  final int hpPerHp;
  final int hpPerVit;
  final int hpPerAvg;

  final int maxLevel;

  /// xpToNext(L) = xpBase + xpPerLevel·L + floor(xpQuadNum·L² / xpQuadDen).
  final int xpBase;
  final int xpPerLevel;
  final int xpQuadNum;
  final int xpQuadDen;

  final List<int> slotBudgets;
  final List<int> slotUnlockLevels;

  /// moveFactorPct = moveFactorBasePct + kid / moveFactorKidDiv (95..105).
  final int moveFactorBasePct;
  final int moveFactorKidDiv;
  final int bloomerPreMoveFactorPct;
  final int legendMoveBonusPct;
  final int bloomerRebirthMoveBonusPct;

  /// Discounts (SP, cast, cooldown) may not exceed this % of a move's value.
  final int maxDiscountPct;

  final int tickHz;
  final int gaugeMax;
  final int gaugeFillPerTick;
  final int agiWeightPct;
  final int decisionTicks;
  final int spMaxCenti;
  final int spStartCenti;
  final int spRegenCentiPerTick;
  final int spWeightPct;

  final int damageScalePct;
  final int typeAdvantagePct;
  final int typeDisadvantagePct;

  /// 100 = the owner's ×1.5 / ×0.75 applied in full to the damage.
  final int typeStrengthPct;
  final int varianceMinPct;
  final int varianceSpan;
  final int critBaseMille;
  final int critLukMille;
  final int critMultiplierPct;
  final int hitSkewPct;
  final int hitMinPct;

  /// Stage multiplier: +n → (stageDen+n)/stageDen, −n → stageDen/(stageDen+n).
  final int stageDen;
  final int maxStage;

  final int poisonMillePerSecond;
  final int poisonTicks;
  final int paralyzeFillPct;
  final int paralyzeTicks;
  final int statusLukSkewPct;
  final List<int> healDecaySteps;

  final int heatUpStartTick;
  final int heatUpPctPerSecond;
  final int hardCapTick;

  V2Spec copyWith({
    int? gaugeFillPerTick,
    int? agiWeightPct,
    int? damageScalePct,
    int? typeStrengthPct,
    int? bloomerPreBudgetPct,
    int? bloomerPreGrowthPct,
    int? bloomerPostGrowthBoostPct,
    int? rebirthKid,
    int? rebirthBudgetPct,
    int? spRegenCentiPerTick,
    int? budgetPerKid,
    int? moveFactorBasePct,
    int? moveFactorKidDiv,
    int? bloomerRebirthMoveBonusPct,
    int? hitSkewPct,
    int? varianceMinPct,
    int? varianceSpan,
    int? critBaseMille,
  }) => V2Spec(
    gaugeFillPerTick: gaugeFillPerTick ?? this.gaugeFillPerTick,
    agiWeightPct: agiWeightPct ?? this.agiWeightPct,
    damageScalePct: damageScalePct ?? this.damageScalePct,
    typeStrengthPct: typeStrengthPct ?? this.typeStrengthPct,
    bloomerPreBudgetPct: bloomerPreBudgetPct ?? this.bloomerPreBudgetPct,
    bloomerPreGrowthPct: bloomerPreGrowthPct ?? this.bloomerPreGrowthPct,
    bloomerPostGrowthBoostPct:
        bloomerPostGrowthBoostPct ?? this.bloomerPostGrowthBoostPct,
    rebirthKid: rebirthKid ?? this.rebirthKid,
    rebirthBudgetPct: rebirthBudgetPct ?? this.rebirthBudgetPct,
    spRegenCentiPerTick: spRegenCentiPerTick ?? this.spRegenCentiPerTick,
    budgetPerKid: budgetPerKid ?? this.budgetPerKid,
    moveFactorBasePct: moveFactorBasePct ?? this.moveFactorBasePct,
    moveFactorKidDiv: moveFactorKidDiv ?? this.moveFactorKidDiv,
    bloomerRebirthMoveBonusPct:
        bloomerRebirthMoveBonusPct ?? this.bloomerRebirthMoveBonusPct,
    hitSkewPct: hitSkewPct ?? this.hitSkewPct,
    varianceMinPct: varianceMinPct ?? this.varianceMinPct,
    varianceSpan: varianceSpan ?? this.varianceSpan,
    critBaseMille: critBaseMille ?? this.critBaseMille,
  );

  /// Effective type multiplier (%) after [typeStrengthPct].
  int typePct(int rawPct) => 100 + (rawPct - 100) * typeStrengthPct ~/ 100;

  Map<String, Object?> toJson() => {
    'specVersion': specVersion,
    'draft': 'DRAFT — prototype numbers from the v2 design spike',
    'integerMath':
        'All values are integers. Every division is floor division of '
        'non-negative integers; every intermediate stays below 2^53.',
    'rng': {
      'algorithm': 'mulberry32 (same as battle spec v2, docs/BATTLE.md §2)',
      'imageSeed': 'uint32 from the first 8 hex digits of imageHash',
      'streams': {
        'statJitter': 10,
        'growth': 11,
        'moves': 12,
        'rebirthStats': 13,
        'rebirthMoves': 14,
        'battle': 0,
        'aiA': 1,
        'aiB': 2,
      },
    },
    'character': {
      'kid': {
        'energyWeight': kidEnergyWeight,
        'skillWeight': kidSkillWeight,
        'formula': 'kid = (ew*e10 + sw*(1000 - s10) + 50) / 100',
      },
      'budget': {
        'base': budgetBase,
        'perKid': budgetPerKid,
        'div': budgetDiv,
        'jitterMinPct': budgetJitterMinPct,
        'jitterSpan': budgetJitterSpan,
        'formula':
            'budget = (base + perKid*kid) * jitterPct / div; '
            'jitterPct = jitterMinPct + rng(statJitter).next() % jitterSpan',
      },
      'bloomer': {
        'skillAbove10': bloomerSkillAbove10,
        'originFlags': ['ai_generated', 'digital', 'printed', 'screen'],
        'preBudgetPct': bloomerPreBudgetPct,
        'preGrowthPct': bloomerPreGrowthPct,
        'rebirthLevel': rebirthLevel,
        'rebirthKid': rebirthKid,
        'rebirthBudgetPct': rebirthBudgetPct,
        'postGrowthBoostPct': bloomerPostGrowthBoostPct,
        'visibility': 'never shown in any UI text, store copy or API response',
      },
      'distribution': {
        'minShareMille': minShareMille,
        'affinityJitterMinPct': affinityJitterMinPct,
        'affinityJitterSpan': affinityJitterSpan,
        'affinityFloor': affinityFloor,
        'affinities': kAffinityTable,
        'ramps': kRampTable,
      },
      'growth': {
        'totalMillePerLevel': growthTotalMillePerLevel,
        'rawBase': growthRawBase,
        'rawAffinityDiv': growthRawAffinityDiv,
        'rawJitterSpan': growthRawJitterSpan,
      },
      'maxHp': {
        'perHp': hpPerHp,
        'perVit': hpPerVit,
        'perAvg': hpPerAvg,
        'formula':
            'maxHp = perHp*HP + perVit*VIT + perAvg*(sum of 10 stats)/10',
      },
      'attribute': kAttributeRule,
    },
    'levels': {
      'max': maxLevel,
      'xpToNext': {
        'base': xpBase,
        'perLevel': xpPerLevel,
        'quadNum': xpQuadNum,
        'quadDen': xpQuadDen,
      },
    },
    'moves': {
      'slotBudgets': slotBudgets,
      'slotUnlockLevels': slotUnlockLevels,
      'moveFactorBasePct': moveFactorBasePct,
      'moveFactorKidDiv': moveFactorKidDiv,
      'bloomerPreMoveFactorPct': bloomerPreMoveFactorPct,
      'legendMoveBonusPct': legendMoveBonusPct,
      'bloomerRebirthMoveBonusPct': bloomerRebirthMoveBonusPct,
      'maxDiscountPct': maxDiscountPct,
    },
    'atb': {
      'tickHz': tickHz,
      'gaugeMax': gaugeMax,
      'gaugeFillPerTick': gaugeFillPerTick,
      'agiWeightPct': agiWeightPct,
      'decisionTicks': decisionTicks,
      'spMaxCenti': spMaxCenti,
      'spStartCenti': spStartCenti,
      'spRegenCentiPerTick': spRegenCentiPerTick,
      'spWeightPct': spWeightPct,
    },
    'damage': {
      'scalePct': damageScalePct,
      'typeAdvantagePct': typeAdvantagePct,
      'typeDisadvantagePct': typeDisadvantagePct,
      'typeStrengthPct': typeStrengthPct,
      'triangle': {'gu': 'choki', 'choki': 'pa', 'pa': 'gu'},
      'varianceMinPct': varianceMinPct,
      'varianceSpan': varianceSpan,
      'critBaseMille': critBaseMille,
      'critLukMille': critLukMille,
      'critMultiplierPct': critMultiplierPct,
      'hitSkewPct': hitSkewPct,
      'hitMinPct': hitMinPct,
      'stageDen': stageDen,
      'maxStage': maxStage,
    },
    'status': {
      'poisonMillePerSecond': poisonMillePerSecond,
      'poisonTicks': poisonTicks,
      'paralyzeFillPct': paralyzeFillPct,
      'paralyzeTicks': paralyzeTicks,
      'lukSkewPct': statusLukSkewPct,
      'healDecaySteps': healDecaySteps,
    },
    'termination': {
      'heatUpStartTick': heatUpStartTick,
      'heatUpPctPerSecond': heatUpPctPerSecond,
      'hardCapTick': hardCapTick,
    },
  };
}

/// Feature ramps (quantised integer features → 0..1000). Each entry:
/// `[featureKey, lo, hi]` in the feature's integer unit (see
/// [kFeatureUnits]). `ramp = 0 if v<=lo, 1000 if v>=hi, else
/// (v-lo)*1000/(hi-lo)`; `inv:` prefix = 1000 − ramp.
const Map<String, List<Object>> kRampTable = {
  'round': ['roundness', 200, 800],
  'size': ['silhouetteCoverage', 30, 350],
  'ink': ['inkCoverage', 0, 300],
  'solid': ['solidity', 500, 950],
  'spiky': ['spikiness', 0, 300],
  'red': ['redShare', 0, 1000],
  'thick': ['lineThickness', 10, 120],
  'dark': ['darkness', 200, 800],
  'colour': ['colorUnits', 1, 10],
  'hues': ['balancedHueCount', 1, 4],
  'detail': ['detailDensity', 0, 600],
  'parts': ['convexityDefects', 0, 8],
  'elong': ['elongation', 100, 300],
  'sym': ['symmetry', 400, 900],
};

/// Integer units of the quantised feature vector (the contract between the
/// analyser and every engine port).
const Map<String, String> kFeatureUnits = {
  'roundness': 'per-mille (round(1000*x))',
  'silhouetteCoverage': 'per-mille',
  'inkCoverage': 'per-mille',
  'solidity': 'per-mille',
  'spikiness': 'per-mille',
  'redShare': 'per-mille',
  'lineThickness': 'tenths of a px (round(10*x)), 0..600',
  'darkness': 'per-mille',
  'colorUnits': 'colorCount*2 + achromaticCount (half-colour units)',
  'balancedHueCount': 'count',
  'detailDensity': 'per-mille',
  'convexityDefects': 'count',
  'elongation': 'hundredths (round(100*x)), 100..1000',
  'symmetry': 'per-mille',
  'energy10': 'energy in tenths, 0..1000',
  'skill10': 'skill in tenths, 0..1000',
};

/// Affinity per stat = Σ weight·term / 100 (weights per stat sum to 100).
/// Terms are ramps from [kRampTable]; `inv:x` = 1000 − ramp x; `luck` =
/// rng(statJitter) % 1001 (drawn in stat order, see stats_v2.dart).
const Map<String, Map<String, int>> kAffinityTable = {
  'HP': {'round': 40, 'size': 35, 'ink': 25},
  'SP': {'hues': 40, 'ink': 30, 'parts': 30},
  'STR': {'spiky': 40, 'red': 30, 'thick': 30},
  'VIT': {'dark': 40, 'solid': 30, 'size': 30},
  'DEF': {'thick': 45, 'solid': 35, 'inv:elong': 20},
  'INT': {'colour': 50, 'detail': 30, 'inv:sym': 20},
  'RES': {'dark': 40, 'thick': 35, 'colour': 25},
  'DEX': {'inv:thick': 40, 'parts': 30, 'detail': 30},
  'AGI': {'elong': 45, 'inv:thick': 35, 'inv:size': 20},
  'LUK': {'luck': 50, 'hues': 25, 'inv:sym': 25},
};

/// Character attribute (グー/チョキ/パー) from shape. Scores (0..3000),
/// highest wins, ties in order gu > choki > pa.
const Map<String, Object> kAttributeRule = {
  'gu': ['solid', 'round', 'thick'],
  'choki': ['spiky', 'elong', 'inv:thick'],
  'pa': ['colour', 'hues', 'size'],
  'tieOrder': ['gu', 'choki', 'pa'],
};
