/// Move templates, the numeric budget ("budget points"), the cost in gauge
/// bars and the shrink-to-fit rule. docs/GAME_DESIGN_V2.md §5. Integer maths
/// only.
///
/// The AI never decides numbers: a move is a template + parameters inside the
/// template ranges, its points must fit the slot's bar budget, and its cost
/// in bars is derived from its points ([moveBars]). Every number a battle
/// uses is computed here (or clamped / shrunk by `validator.dart`).
library;

import 'spec.dart';

enum MoveKind { physical, special, heal, buff, debuff, status, shield }

/// ATK mixes a damage move may use (all sum to 100 %).
enum AtkFormula {
  strAgi('STR80_AGI20', Stat.str, 80, Stat.agi, 20, true),
  strVit('STR70_VIT30', Stat.str, 70, Stat.vit, 30, true),
  strDex('STR60_DEX40', Stat.str, 60, Stat.dex, 40, true),
  intDex('INT80_DEX20', Stat.intl, 80, Stat.dex, 20, false),
  intRes('INT70_RES30', Stat.intl, 70, Stat.res, 30, false),
  intLuk('INT60_LUK40', Stat.intl, 60, Stat.luk, 40, false);

  const AtkFormula(this.code, this.a, this.pa, this.b, this.pb, this.physical);
  final String code;
  final Stat a;
  final int pa;
  final Stat b;
  final int pb;
  final bool physical;

  static AtkFormula? fromCode(String? c) {
    for (final f in values) {
      if (f.code == c) return f;
    }
    return null;
  }
}

enum StatusKind { poison, paralyze }

/// Secondary effect of a damage move.
enum SecondaryType { none, poison, paralyze, debuff, drain }

const List<String> kVfx = [
  'slash', 'punch', 'beam', 'orb', 'burst', 'wave', 'rain', 'spiral', //
  'stars', 'hearts', 'bubbles', 'leaves', 'sparks', 'shield', 'glow',
];
const List<String> kColours = [
  'red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'pink', //
  'black', 'white', 'rainbow',
];

/// Stats a buff / debuff may target.
const List<Stat> kStageStats = [
  Stat.str, Stat.def, Stat.intl, Stat.res, Stat.agi, Stat.dex, Stat.luk, //
];

/// Integer range `[min, max]`.
class R {
  const R(this.min, this.max);
  final int min;
  final int max;
  int clamp(int v) => v < min ? min : (v > max ? max : v);
  List<int> toJson() => [min, max];
}

/// A move template: which kind it is and the legal range of every knob.
class MoveTemplate {
  const MoveTemplate(this.id, this.kind, this.ranges);
  final String id;
  final MoveKind kind;
  final Map<String, R> ranges;

  bool get isDamage => kind == MoveKind.physical || kind == MoveKind.special;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'ranges': {for (final e in ranges.entries) e.key: e.value.toJson()},
  };
}

/// Largest power of a damage move (a 5-bar ひっさつ needs ~750).
const int kMaxPower = 1200;

const _common = {'castTicks': R(0, 20), 'cooldownTicks': R(0, 150)};

const Map<String, MoveTemplate> kTemplates = {
  'strike': MoveTemplate('strike', MoveKind.physical, {
    'power': R(40, kMaxPower),
    'hits': R(1, 1),
    'accuracy': R(60, 100),
    'critBonus': R(0, 20),
    ..._common,
  }),
  'combo': MoveTemplate('combo', MoveKind.physical, {
    'power': R(40, kMaxPower),
    'hits': R(2, 3),
    'accuracy': R(60, 100),
    'critBonus': R(0, 20),
    ..._common,
  }),
  'blast': MoveTemplate('blast', MoveKind.special, {
    'power': R(40, kMaxPower),
    'hits': R(1, 1),
    'accuracy': R(60, 100),
    'critBonus': R(0, 20),
    ..._common,
  }),
  'barrage': MoveTemplate('barrage', MoveKind.special, {
    'power': R(40, kMaxPower),
    'hits': R(2, 3),
    'accuracy': R(60, 100),
    'critBonus': R(0, 20),
    ..._common,
  }),
  'heal': MoveTemplate('heal', MoveKind.heal, {
    'healPct': R(10, 40),
    'castTicks': R(0, 20),
    'cooldownTicks': R(60, 150),
  }),
  'power_up': MoveTemplate('power_up', MoveKind.buff, {
    'stages': R(1, 2),
    'durationTicks': R(40, 120),
    ..._common,
  }),
  'weaken': MoveTemplate('weaken', MoveKind.debuff, {
    'stages': R(1, 2),
    'durationTicks': R(40, 120),
    'accuracy': R(60, 100),
    ..._common,
  }),
  'poison': MoveTemplate('poison', MoveKind.status, {
    'chance': R(30, 100),
    'accuracy': R(60, 100),
    ..._common,
  }),
  'paralyze': MoveTemplate('paralyze', MoveKind.status, {
    'chance': R(30, 100),
    'accuracy': R(60, 100),
    ..._common,
  }),
  'barrier': MoveTemplate('barrier', MoveKind.shield, {
    'shieldPct': R(20, 60),
    'durationTicks': R(20, 60),
    'castTicks': R(0, 5),
    'cooldownTicks': R(40, 150),
  }),
};

/// Secondary ranges for damage moves.
const Map<String, R> kSecondaryRanges = {
  'chance': R(10, 50),
  'drainPct': R(10, 50),
};

/// Budget-point values of effects (100 points ≈ a 100-power neutral hit ≈
/// 10 % of max HP at equal stats).
const int kPoisonValue = 120;
const int kParalyzeValue = 80;
const int kDebuffSecondaryValue = 40;
const int kHealValuePerPct = 6;
const List<int> kHitsAdjPct = [100, 100, 103, 106];

/// Duration of the 1-stage debuff a damage move's secondary applies.
const int kDebuffSecondaryTicks = 60;

/// A concrete move (one slot of a character).
class Move {
  const Move({
    required this.template,
    required this.attr,
    this.name = '',
    this.flavor = '',
    this.vfx = 'punch',
    this.colour = 'red',
    this.atkFormula = AtkFormula.strAgi,
    this.power = 0,
    this.hits = 1,
    this.accuracy = 100,
    this.critBonus = 0,
    this.bars = 1,
    this.castTicks = 0,
    this.cooldownTicks = 0,
    this.secondary = SecondaryType.none,
    this.secondaryChance = 0,
    this.secondaryStat = Stat.def,
    this.drainPct = 0,
    this.healPct = 0,
    this.stat = Stat.str,
    this.stages = 0,
    this.durationTicks = 0,
    this.chance = 0,
    this.shieldPct = 0,
  });

  final String template;
  final Attr attr;
  final String name;
  final String flavor;
  final String vfx;
  final String colour;
  final AtkFormula atkFormula;
  final int power;
  final int hits;
  final int accuracy;
  final int critBonus;

  /// Cost in gauge bars (1..5), derived from the points by [moveBars] when
  /// the move is generated or validated (never set by the AI).
  final int bars;
  final int castTicks;
  final int cooldownTicks;
  final SecondaryType secondary;
  final int secondaryChance;
  final Stat secondaryStat;
  final int drainPct;
  final int healPct;
  final Stat stat;
  final int stages;
  final int durationTicks;
  final int chance;
  final int shieldPct;

  MoveTemplate get tpl => kTemplates[template]!;
  MoveKind get kind => tpl.kind;
  bool get isDamage => tpl.isDamage;
  StatusKind? get status => template == 'poison'
      ? StatusKind.poison
      : template == 'paralyze'
      ? StatusKind.paralyze
      : null;

  Move copyWith({
    Attr? attr,
    String? name,
    String? flavor,
    String? vfx,
    String? colour,
    int? power,
    int? accuracy,
    int? bars,
    int? castTicks,
    int? cooldownTicks,
    SecondaryType? secondary,
    int? secondaryChance,
    int? drainPct,
    int? healPct,
    int? stages,
    int? durationTicks,
    int? chance,
    int? shieldPct,
  }) => Move(
    template: template,
    attr: attr ?? this.attr,
    name: name ?? this.name,
    flavor: flavor ?? this.flavor,
    vfx: vfx ?? this.vfx,
    colour: colour ?? this.colour,
    atkFormula: atkFormula,
    power: power ?? this.power,
    hits: hits,
    accuracy: accuracy ?? this.accuracy,
    critBonus: critBonus,
    bars: bars ?? this.bars,
    castTicks: castTicks ?? this.castTicks,
    cooldownTicks: cooldownTicks ?? this.cooldownTicks,
    secondary: secondary ?? this.secondary,
    secondaryChance: secondaryChance ?? this.secondaryChance,
    secondaryStat: secondaryStat,
    drainPct: drainPct ?? this.drainPct,
    healPct: healPct ?? this.healPct,
    stat: stat,
    stages: stages ?? this.stages,
    durationTicks: durationTicks ?? this.durationTicks,
    chance: chance ?? this.chance,
    shieldPct: shieldPct ?? this.shieldPct,
  );

  Map<String, Object?> toJson() => {
    'template': template,
    'attribute': attr.name,
    'name': name,
    'flavor': flavor,
    'vfx': vfx,
    'colour': colour,
    if (isDamage) ...{
      'atkFormula': atkFormula.code,
      'power': power,
      'hits': hits,
      'accuracy': accuracy,
      'critBonus': critBonus,
      'secondary': {
        'type': secondary.name,
        if (secondary == SecondaryType.poison ||
            secondary == SecondaryType.paralyze ||
            secondary == SecondaryType.debuff)
          'chance': secondaryChance,
        if (secondary == SecondaryType.debuff) 'stat': secondaryStat.code,
        if (secondary == SecondaryType.drain) 'drainPct': drainPct,
      },
    },
    if (kind == MoveKind.heal) 'healPct': healPct,
    if (kind == MoveKind.buff || kind == MoveKind.debuff) ...{
      'stat': stat.code,
      'stages': stages,
      'durationTicks': durationTicks,
    },
    if (kind == MoveKind.debuff || kind == MoveKind.status)
      'accuracy': accuracy,
    if (kind == MoveKind.status) 'chance': chance,
    if (kind == MoveKind.shield) ...{
      'shieldPct': shieldPct,
      'durationTicks': durationTicks,
    },
    'bars': bars,
    'castTicks': castTicks,
    'cooldownTicks': cooldownTicks,
  };

  /// Inverse of [toJson] for already-validated moves (golden vectors).
  /// Not a validator: use [validateAiMove] for AI output and stored
  /// proposals (a legacy `spCost` is ignored everywhere).
  factory Move.fromJson(Map<String, Object?> j) {
    int i(String k, [int d = 0]) => (j[k] as int?) ?? d;
    final sec = (j['secondary'] as Map?)?.cast<String, Object?>();
    final stat = j['stat'] as String?;
    return Move(
      template: j['template']! as String,
      attr: Attr.values.byName(j['attribute']! as String),
      name: j['name'] as String? ?? '',
      flavor: j['flavor'] as String? ?? '',
      vfx: j['vfx'] as String? ?? 'punch',
      colour: j['colour'] as String? ?? 'white',
      atkFormula:
          AtkFormula.fromCode(j['atkFormula'] as String?) ?? AtkFormula.strAgi,
      power: i('power'),
      hits: i('hits', 1),
      accuracy: i('accuracy', 100),
      critBonus: i('critBonus'),
      bars: i('bars', 1),
      castTicks: i('castTicks'),
      cooldownTicks: i('cooldownTicks'),
      secondary: sec == null
          ? SecondaryType.none
          : SecondaryType.values.byName(sec['type']! as String),
      secondaryChance: (sec?['chance'] as int?) ?? 0,
      secondaryStat: sec?['stat'] == null
          ? Stat.def
          : Stat.fromCode(sec!['stat']! as String),
      drainPct: (sec?['drainPct'] as int?) ?? 0,
      healPct: i('healPct'),
      stat: stat == null ? Stat.str : Stat.fromCode(stat),
      stages: i('stages'),
      durationTicks: i('durationTicks'),
      chance: i('chance'),
      shieldPct: i('shieldPct'),
    );
  }

  @override
  String toString() => toJson().toString();
}

/// Minimum cooldown that is "free" (not discounted) for a move.
int freeCooldown(Move m) => switch (m.kind) {
  MoveKind.heal => 60,
  MoveKind.buff ||
  MoveKind.debuff => m.durationTicks > 20 ? m.durationTicks : 20,
  MoveKind.shield => 40,
  _ => 20,
};

/// Gross value of a move in budget points (before discounts).
int moveValue(Move m) {
  switch (m.kind) {
    case MoveKind.physical:
    case MoveKind.special:
      var v =
          m.power *
          m.accuracy *
          (200 + m.critBonus) *
          kHitsAdjPct[m.hits] ~/
          (100 * 200 * 100);
      v += switch (m.secondary) {
        SecondaryType.none => 0,
        SecondaryType.poison => m.secondaryChance * kPoisonValue ~/ 100,
        SecondaryType.paralyze => m.secondaryChance * kParalyzeValue ~/ 100,
        SecondaryType.debuff =>
          m.secondaryChance * kDebuffSecondaryValue ~/ 100,
        SecondaryType.drain => m.drainPct * m.power ~/ 100,
      };
      return v;
    case MoveKind.heal:
      return m.healPct * kHealValuePerPct;
    case MoveKind.buff:
      return m.stages *
          m.durationTicks *
          5 *
          (m.stat == Stat.agi ? 120 : 100) ~/
          800;
    case MoveKind.debuff:
      return m.stages *
          m.durationTicks *
          5 *
          (m.stat == Stat.agi ? 120 : 100) *
          m.accuracy ~/
          80000;
    case MoveKind.status:
      final sv = m.status == StatusKind.poison ? kPoisonValue : kParalyzeValue;
      return sv * m.chance * m.accuracy ~/ 10000;
    case MoveKind.shield:
      return m.shieldPct * m.durationTicks ~/ 30;
  }
}

/// Discount for cast time and extra cooldown (capped at
/// [V3Spec.maxDiscountPct] % of the value). Casting pauses the gauge, so a
/// cast is a real cost; a cooldown mostly is not (the bars take time to
/// refill anyway), so it counts a quarter.
int moveDiscount(V3Spec s, Move m) {
  final free = freeCooldown(m);
  final d =
      m.castTicks * s.castDiscountPerTick +
      (m.cooldownTicks > free
          ? (m.cooldownTicks - free) ~/ s.cooldownDiscountDiv
          : 0);
  final cap = moveValue(m) * s.maxDiscountPct ~/ 100;
  return d < cap ? d : cap;
}

/// Net strength in budget points (value − discount).
int movePoints(V3Spec s, Move m) => moveValue(m) - moveDiscount(s, m);

/// Budget points a move may be worth for a cost of [bars] (1..5) at
/// [moveFactorPct].
int barBudget(V3Spec s, int bars, int moveFactorPct) =>
    s.barBudgets[bars - 1] * moveFactorPct ~/ 100;

/// Cost in bars of a move worth [points]: the smallest n (1..5) whose
/// [barBudget] holds it, or 0 when even 5 bars do not.
int barsForPoints(V3Spec s, int points, int moveFactorPct) {
  for (var n = 1; n <= s.barBudgets.length; n++) {
    if (points <= barBudget(s, n, moveFactorPct)) return n;
  }
  return 0;
}

/// Cost in bars of [m] for a character with [moveFactorPct] (0 = too big).
int moveBars(V3Spec s, Move m, int moveFactorPct) =>
    barsForPoints(s, movePoints(s, m), moveFactorPct);

/// The most bars the move of [slot] (0..3) may cost for a character with
/// [maxBars].
int slotMaxBarsFor(V3Spec s, int slot, int maxBars) {
  final b = s.slotMaxBars[slot];
  return b < maxBars ? b : maxBars;
}

/// Budget (points) of [slot] for a character with [moveFactorPct] and
/// [maxBars]: the budget of the most bars the slot may cost.
int slotBudget(V3Spec s, int slot, int moveFactorPct, int maxBars) =>
    barBudget(s, slotMaxBarsFor(s, slot, maxBars), moveFactorPct);

/// [m] with its [Move.bars] derived from its points.
Move withBars(V3Spec s, Move m, int moveFactorPct) {
  final b = moveBars(s, m, moveFactorPct);
  return m.copyWith(bars: b < 1 ? 1 : b);
}

/// Shrinks the primary magnitude until the move fits [budget]; null when
/// impossible. Returns the same instance when it already fits.
Move? fitToBudget(V3Spec s, Move m0, int budget) {
  var m = m0;
  for (var guard = 0; guard < 400; guard++) {
    if (movePoints(s, m) <= budget) return m;
    final r = m.tpl.ranges;
    switch (m.kind) {
      case MoveKind.physical:
      case MoveKind.special:
        if (m.power - 5 >= r['power']!.min) {
          m = m.copyWith(power: m.power - 5);
        } else if (m.secondary != SecondaryType.none) {
          m = m.copyWith(secondary: SecondaryType.none);
        } else {
          return null;
        }
      case MoveKind.heal:
        if (m.healPct - 1 < r['healPct']!.min) return null;
        m = m.copyWith(healPct: m.healPct - 1);
      case MoveKind.buff:
      case MoveKind.debuff:
        if (m.durationTicks - 10 >= r['durationTicks']!.min) {
          m = m.copyWith(durationTicks: m.durationTicks - 10);
        } else if (m.stages > 1) {
          m = m.copyWith(stages: m.stages - 1);
        } else {
          return null;
        }
      case MoveKind.status:
        if (m.chance - 5 < r['chance']!.min) return null;
        m = m.copyWith(chance: m.chance - 5);
      case MoveKind.shield:
        if (m.shieldPct - 5 >= r['shieldPct']!.min) {
          m = m.copyWith(shieldPct: m.shieldPct - 5);
        } else if (m.durationTicks - 5 >= r['durationTicks']!.min) {
          m = m.copyWith(durationTicks: m.durationTicks - 5);
        } else {
          return null;
        }
    }
  }
  return null;
}
