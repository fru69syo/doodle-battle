/// PROTOTYPE — v2 move templates, numeric budget, validator for AI (Claude)
/// output and the deterministic offline generator.
/// docs/GAME_DESIGN_V2.md §5. Integer maths only.
library;

import '../battle/rng.dart';
import 'stats_v2.dart';
import 'v2_spec.dart';

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

const _common = {
  'spCost': R(0, 50),
  'castTicks': R(0, 20),
  'cooldownTicks': R(0, 150),
};

const Map<String, MoveTemplate> kTemplates = {
  'strike': MoveTemplate('strike', MoveKind.physical, {
    'power': R(40, 200),
    'hits': R(1, 1),
    'accuracy': R(60, 100),
    'critBonus': R(0, 20),
    ..._common,
  }),
  'combo': MoveTemplate('combo', MoveKind.physical, {
    'power': R(40, 200),
    'hits': R(2, 3),
    'accuracy': R(60, 100),
    'critBonus': R(0, 20),
    ..._common,
  }),
  'blast': MoveTemplate('blast', MoveKind.special, {
    'power': R(40, 200),
    'hits': R(1, 1),
    'accuracy': R(60, 100),
    'critBonus': R(0, 20),
    ..._common,
  }),
  'barrage': MoveTemplate('barrage', MoveKind.special, {
    'power': R(40, 200),
    'hits': R(2, 3),
    'accuracy': R(60, 100),
    'critBonus': R(0, 20),
    ..._common,
  }),
  'heal': MoveTemplate('heal', MoveKind.heal, {
    'healPct': R(10, 40),
    'spCost': R(0, 50),
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
    'spCost': R(0, 50),
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

/// A concrete move (one slot of a character).
class MoveV2 {
  const MoveV2({
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
    this.spCost = 0,
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
  final int spCost;
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

  MoveV2 copyWith({
    Attr? attr,
    String? name,
    String? flavor,
    String? vfx,
    String? colour,
    int? power,
    int? accuracy,
    int? spCost,
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
  }) => MoveV2(
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
    spCost: spCost ?? this.spCost,
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
    'spCost': spCost,
    'castTicks': castTicks,
    'cooldownTicks': cooldownTicks,
  };

  /// Inverse of [toJson] for already-validated moves (golden vectors,
  /// persisted characters). Not a validator: use [validateAiMove] for AI
  /// output.
  factory MoveV2.fromJson(Map<String, Object?> j) {
    int i(String k, [int d = 0]) => (j[k] as int?) ?? d;
    final sec = (j['secondary'] as Map?)?.cast<String, Object?>();
    final stat = j['stat'] as String?;
    return MoveV2(
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
      spCost: i('spCost'),
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
int freeCooldown(MoveV2 m) => switch (m.kind) {
  MoveKind.heal => 60,
  MoveKind.buff ||
  MoveKind.debuff => m.durationTicks > 20 ? m.durationTicks : 20,
  MoveKind.shield => 40,
  _ => 20,
};

/// Gross value of a move in budget points (before discounts).
int moveValue(MoveV2 m) {
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

/// Discount for SP cost, cast time and extra cooldown (capped).
int moveDiscount(V2Spec s, MoveV2 m) {
  final free = freeCooldown(m);
  final d =
      m.spCost * 5 ~/ 4 +
      m.castTicks * 2 +
      (m.cooldownTicks > free ? (m.cooldownTicks - free) ~/ 2 : 0);
  final cap = moveValue(m) * s.maxDiscountPct ~/ 100;
  return d < cap ? d : cap;
}

/// Net cost in budget points; must be <= [slotBudget].
int moveCost(V2Spec s, MoveV2 m) => moveValue(m) - moveDiscount(s, m);

/// Budget of [slot] (0..3) for a character with [moveFactorPct].
int slotBudget(V2Spec s, int slot, int moveFactorPct) =>
    s.slotBudgets[slot] * moveFactorPct ~/ 100;

// ---------------------------------------------------------------------------
// Validator for AI output
// ---------------------------------------------------------------------------

/// Outcome of validating one AI-proposed move.
class MoveValidation {
  MoveValidation(
    this.move,
    this.warnings, {
    this.rejected = false,
    this.reason,
  });
  final MoveV2? move;
  final List<String> warnings;
  final bool rejected;
  final String? reason;
}

final RegExp _kanaName = RegExp(r'^[ぁ-ゖァ-ヺー]{1,10}$');
final RegExp _kanaFlavor = RegExp(r'^[ぁ-ゖァ-ヺー、。！？ 　]{0,30}$');

/// Validates and normalises one move proposed by the AI for [slot] of a
/// character with attribute [own]. Deterministic; see docs §5.6.
/// [ngCheck] returns true when a string contains an NG word.
MoveValidation validateAiMove(
  V2Spec s,
  Map<String, Object?> json, {
  required int slot,
  required Attr own,
  required int moveFactorPct,
  bool Function(String)? ngCheck,
}) {
  final w = <String>[];
  MoveValidation reject(String r) =>
      MoveValidation(null, w, rejected: true, reason: r);

  final tplId = json['template'];
  if (tplId is! String || !kTemplates.containsKey(tplId)) {
    return reject('unknown template');
  }
  final tpl = kTemplates[tplId]!;
  int numParam(String k, int def) {
    final v = json[k];
    final r = tpl.ranges[k];
    var i = v is int ? v : (v is double && v.isFinite ? v.floor() : def);
    if (v != null && v is! int && v is! double) w.add('$k not a number');
    if (r != null && (i < r.min || i > r.max)) {
      w.add('$k clamped');
      i = r.clamp(i);
    }
    return i;
  }

  // Slot rules.
  if (slot == 0 && !tpl.isDamage) return reject('slot 1 must be a damage move');
  if (slot == 3 && !tpl.isDamage) return reject('slot 4 must be a damage move');

  var attr = Attr.values.firstWhere(
    (a) => a.name == json['attribute'],
    orElse: () => Attr.none,
  );
  final supportKind =
      tpl.kind == MoveKind.heal ||
      tpl.kind == MoveKind.buff ||
      tpl.kind == MoveKind.shield;
  if (supportKind && attr != Attr.none) {
    w.add('support moves have no attribute');
    attr = Attr.none;
  }
  if (slot == 0 && attr != own) {
    w.add('slot 1 attribute forced to own');
    attr = own;
  }
  if (slot == 3 && attr != Attr.none) {
    w.add('slot 4 (ひっさつ) is always neutral');
    attr = Attr.none;
  }
  if (slot == 1 && attr == own) {
    w.add('slot 2 attribute must differ from slot 1');
    attr = Attr.none;
  }

  // Strings.
  var name = json['name'] is String ? json['name']! as String : '';
  var flavor = json['flavor'] is String ? json['flavor']! as String : '';
  if (!_kanaName.hasMatch(name) || (ngCheck?.call(name) ?? false)) {
    return reject('name');
  }
  if (!_kanaFlavor.hasMatch(flavor) || (ngCheck?.call(flavor) ?? false)) {
    w.add('flavor dropped');
    flavor = '';
  }
  var vfx = json['vfx'] is String ? json['vfx']! as String : '';
  if (!kVfx.contains(vfx)) {
    w.add('vfx defaulted');
    vfx = tpl.isDamage ? 'punch' : 'glow';
  }
  var colour = json['colour'] is String ? json['colour']! as String : '';
  if (!kColours.contains(colour)) {
    w.add('colour defaulted');
    colour = 'white';
  }

  var formula = AtkFormula.fromCode(json['atkFormula'] as String?);
  final physical = tpl.kind == MoveKind.physical;
  if (tpl.isDamage && (formula == null || formula.physical != physical)) {
    w.add('atkFormula defaulted');
    formula = physical ? AtkFormula.strAgi : AtkFormula.intDex;
  }
  var statKind = Stat.str;
  if (tpl.kind == MoveKind.buff || tpl.kind == MoveKind.debuff) {
    final c = json['stat'];
    final found = kStageStats.where((st) => st.code == c);
    if (found.isEmpty) return reject('stat');
    statKind = found.first;
  }

  var secondary = SecondaryType.none;
  var secChance = 0;
  var secStat = Stat.def;
  var drain = 0;
  if (tpl.isDamage && json['secondary'] is Map) {
    final sec = (json['secondary']! as Map).cast<String, Object?>();
    secondary = SecondaryType.values.firstWhere(
      (t) => t.name == sec['type'],
      orElse: () => SecondaryType.none,
    );
    int sn(String k) {
      final v = sec[k];
      final i = v is int
          ? v
          : (v is double && v.isFinite ? v.floor() : kSecondaryRanges[k]!.min);
      final c = kSecondaryRanges[k]!.clamp(i);
      if (c != i) w.add('secondary.$k clamped');
      return c;
    }

    if (secondary == SecondaryType.poison ||
        secondary == SecondaryType.paralyze ||
        secondary == SecondaryType.debuff) {
      secChance = sn('chance');
    }
    if (secondary == SecondaryType.debuff) {
      final found = kStageStats.where((st) => st.code == sec['stat']);
      if (found.isEmpty) {
        w.add('secondary dropped');
        secondary = SecondaryType.none;
      } else {
        secStat = found.first;
      }
    }
    if (secondary == SecondaryType.drain) drain = sn('drainPct');
  }

  var m = MoveV2(
    template: tplId,
    attr: attr,
    name: name,
    flavor: flavor,
    vfx: vfx,
    colour: colour,
    atkFormula: formula ?? AtkFormula.strAgi,
    power: tpl.isDamage ? numParam('power', 100) : 0,
    hits: tpl.isDamage ? numParam('hits', tpl.ranges['hits']!.min) : 1,
    accuracy: tpl.ranges.containsKey('accuracy')
        ? numParam('accuracy', 100)
        : 100,
    critBonus: tpl.isDamage ? numParam('critBonus', 0) : 0,
    spCost: numParam('spCost', 0),
    castTicks: numParam('castTicks', 0),
    cooldownTicks: numParam('cooldownTicks', tpl.ranges['cooldownTicks']!.min),
    secondary: secondary,
    secondaryChance: secChance,
    secondaryStat: secStat,
    drainPct: drain,
    healPct: tpl.kind == MoveKind.heal ? numParam('healPct', 10) : 0,
    stat: statKind,
    stages: tpl.ranges.containsKey('stages') ? numParam('stages', 1) : 0,
    durationTicks: tpl.ranges.containsKey('durationTicks')
        ? numParam('durationTicks', tpl.ranges['durationTicks']!.min)
        : 0,
    chance: tpl.ranges.containsKey('chance') ? numParam('chance', 30) : 0,
    shieldPct: tpl.ranges.containsKey('shieldPct')
        ? numParam('shieldPct', 20)
        : 0,
  );

  // Slot-1 "いつもの わざ" must be always usable.
  if (slot == 0 && (m.spCost != 0 || m.cooldownTicks != 0 || m.castTicks > 5)) {
    w.add('slot 1 made free (sp 0, cooldown 0, cast <= 5)');
    m = m.copyWith(
      spCost: 0,
      cooldownTicks: 0,
      castTicks: m.castTicks > 5 ? 5 : m.castTicks,
    );
  }
  // Buffs/debuffs can not be re-applied while active.
  if ((m.kind == MoveKind.buff || m.kind == MoveKind.debuff) &&
      m.cooldownTicks < m.durationTicks) {
    m = m.copyWith(cooldownTicks: m.durationTicks);
  }

  final fitted = fitToBudget(s, m, slotBudget(s, slot, moveFactorPct));
  if (fitted == null) return reject('over budget');
  if (!identical(fitted, m)) w.add('scaled to budget');
  return MoveValidation(fitted, w);
}

/// Shrinks the primary magnitude until the move fits [budget]; null when
/// impossible. Returns the same instance when it already fits.
MoveV2? fitToBudget(V2Spec s, MoveV2 m0, int budget) {
  var m = m0;
  for (var guard = 0; guard < 400; guard++) {
    if (moveCost(s, m) <= budget) return m;
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

// ---------------------------------------------------------------------------
// Offline generator (no cloud consent): deterministic from the image hash.
// ---------------------------------------------------------------------------

const Map<Attr, List<String>> _prefix = {
  Attr.gu: ['ごつごつ', 'どすん', 'ぐるぐる', 'がっちり', 'ドカン'],
  Attr.choki: ['シャキーン', 'ちょきちょき', 'ビュン', 'とげとげ', 'スパッと'],
  Attr.pa: ['ふわふわ', 'ぱあっと', 'きらきら', 'ひらひら', 'もくもく'],
  Attr.none: ['にこにこ', 'ぽかぽか', 'わくわく', 'のびのび', 'ぴかぴか'],
};
const Map<MoveKind, List<String>> _noun = {
  MoveKind.physical: ['パンチ', 'キック', 'タックル', 'ずつき'],
  MoveKind.special: ['ビーム', 'ボール', 'ウェーブ', 'スター'],
  MoveKind.heal: ['ヒール', 'おひるね', 'げんき'],
  MoveKind.buff: ['パワー', 'がんばる', 'きあい'],
  MoveKind.debuff: ['こちょこちょ', 'にらめっこ'],
  MoveKind.status: ['ねばねば', 'ビリビリ'],
  MoveKind.shield: ['バリア', 'まもり'],
};
const Map<Attr, List<String>> _attrColours = {
  Attr.gu: ['red', 'orange', 'black'],
  Attr.choki: ['yellow', 'cyan', 'purple'],
  Attr.pa: ['green', 'pink', 'blue', 'rainbow'],
  Attr.none: ['white', 'pink', 'yellow'],
};

T _pick<T>(Mulberry32 r, List<T> xs) => xs[r.nextInt(xs.length)];

String _name(Mulberry32 r, Attr a, MoveKind k) {
  final n = _pick(r, _noun[k]!);
  final p = _pick(r, _prefix[a]!);
  final s = '$p$n';
  return s.length <= 10 ? s : n;
}

/// Largest power (multiple of 5) that fits; null if even the minimum does not.
MoveV2? _maxPower(V2Spec s, MoveV2 m, int budget) {
  for (var p = 200; p >= 40; p -= 5) {
    final c = m.copyWith(power: p);
    if (moveCost(s, c) <= budget) return c;
  }
  return null;
}

/// Generates the four slot moves (locked slots are generated too — they are
/// revealed at Lv10 / Lv50). [stream] 12 normally, 14 for the bloomer's
/// rebirth set.
List<MoveV2> generateOfflineMoves(
  V2Spec s,
  Genome g, {
  required int moveFactorPct,
  int stream = 12,
  Attr? attr,
}) {
  final r = Mulberry32(deriveSeed(g.seed, stream));
  final st = g.base;
  final physical = st[Stat.str.index] >= st[Stat.intl.index];
  final own = attr ?? g.attr;
  final formula = _bestFormula(st, physical);
  final kindD = physical ? MoveKind.physical : MoveKind.special;
  String dmgTpl(bool multi) =>
      physical ? (multi ? 'combo' : 'strike') : (multi ? 'barrage' : 'blast');
  String vfxFor(MoveKind k) => switch (k) {
    MoveKind.physical => _pick(r, ['punch', 'slash', 'spiral', 'burst']),
    MoveKind.special => _pick(r, ['beam', 'orb', 'wave', 'stars', 'sparks']),
    MoveKind.heal => _pick(r, ['hearts', 'glow', 'bubbles']),
    MoveKind.shield => 'shield',
    _ => _pick(r, ['glow', 'stars', 'bubbles', 'leaves', 'rain']),
  };

  MoveV2 damage(
    int slot,
    Attr a, {
    bool multi = false,
    int sp = 0,
    int cast = 0,
    int cd = 0,
    int acc = 100,
    SecondaryType sec = SecondaryType.none,
    int secChance = 0,
  }) {
    final base = MoveV2(
      template: dmgTpl(multi),
      attr: a,
      name: _name(r, a, kindD),
      vfx: vfxFor(kindD),
      colour: _pick(r, _attrColours[a]!),
      atkFormula: formula,
      power: 40,
      hits: multi ? 2 + r.nextInt(2) : 1,
      accuracy: acc,
      spCost: sp,
      castTicks: cast,
      cooldownTicks: cd,
      secondary: sec,
      secondaryChance: secChance,
      secondaryStat: physical ? Stat.def : Stat.res,
    );
    return _maxPower(s, base, slotBudget(s, slot, moveFactorPct)) ??
        base.copyWith(secondary: SecondaryType.none);
  }

  // Slot 1: いつもの わざ.
  final roll1 = r.nextInt(100);
  final m0 = roll1 < 30
      ? damage(0, own, acc: 90)
      : roll1 < 50
      ? damage(0, own, sec: SecondaryType.debuff, secChance: 20)
      : damage(0, own);

  // Slot 2: coverage or support.
  final cover = own.beatenBy!.beatenBy!; // beats what beats me
  final roll2 = r.nextInt(100);
  final MoveV2 m1;
  if (roll2 < 35) {
    m1 = damage(1, cover, cd: 30, sp: 10);
  } else if (roll2 < 65) {
    m1 = damage(
      1,
      Attr.none,
      sec: r.nextInt(2) == 0 ? SecondaryType.poison : SecondaryType.paralyze,
      secChance: 30,
      sp: 10,
    );
  } else {
    m1 = _support(s, r, g, own, slotBudget(s, 1, moveFactorPct), vfxFor);
  }

  // Slot 3 (Lv10): strong move.
  final roll3 = r.nextInt(100);
  final m2 = roll3 < 50
      ? damage(2, roll3 < 25 ? own : cover, sp: 20, cast: 6, cd: 40)
      : damage(
          2,
          own.beats == m1.attr ? own : Attr.none,
          multi: true,
          sp: 15,
          cd: 30,
        );

  // Slot 4 (Lv50): ひっさつ.
  final m3 = damage(3, Attr.none, sp: 40, cast: 12, cd: 80); // ひっさつ: neutral
  return [m0, m1, m2, m3];
}

MoveV2 _support(
  V2Spec s,
  Mulberry32 r,
  Genome g,
  Attr own,
  int budget,
  String Function(MoveKind) vfxFor,
) {
  final st = g.base;
  final w = [
    st[Stat.intl.index], // heal
    st[Stat.def.index] + st[Stat.vit.index], // barrier
    st[Stat.luk.index] * 2, // status
    st[Stat.str.index] + st[Stat.intl.index], // buff
  ];
  final total = w.fold<int>(0, (a, b) => a + b);
  var x = r.nextInt(total);
  var k = 0;
  while (x >= w[k]) {
    x -= w[k];
    k++;
  }
  final physical = st[Stat.str.index] >= st[Stat.intl.index];
  final MoveV2 m = switch (k) {
    0 => MoveV2(
      template: 'heal',
      attr: Attr.none,
      healPct: 40,
      spCost: 25,
      cooldownTicks: 100,
    ),
    1 => const MoveV2(
      template: 'barrier',
      attr: Attr.none,
      shieldPct: 60,
      durationTicks: 40,
      spCost: 10,
      cooldownTicks: 60,
    ),
    2 => MoveV2(
      template: r.nextInt(2) == 0 ? 'poison' : 'paralyze',
      attr: own.beats!,
      chance: 100,
      accuracy: 90,
      spCost: 10,
      cooldownTicks: 60,
    ),
    _ => MoveV2(
      template: 'power_up',
      attr: Attr.none,
      stat: physical ? Stat.str : Stat.intl,
      stages: 2,
      durationTicks: 120,
      spCost: 15,
      cooldownTicks: 120,
    ),
  };
  final fitted = fitToBudget(s, m, budget) ?? m;
  return fitted.copyWith(
    name: _name(r, fitted.attr, fitted.kind),
    vfx: vfxFor(fitted.kind),
    colour: _pick(r, _attrColours[fitted.attr]!),
  );
}

AtkFormula _bestFormula(List<int> st, bool physical) {
  AtkFormula? best;
  var bestV = -1;
  for (final f in AtkFormula.values) {
    if (f.physical != physical) continue;
    final v = st[f.a.index] * f.pa + st[f.b.index] * f.pb;
    if (v > bestV) {
      bestV = v;
      best = f;
    }
  }
  return best!;
}
