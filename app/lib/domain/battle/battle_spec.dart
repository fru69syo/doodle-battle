/// Typed view of `shared/battle_spec/battle_spec.json` — the single source of
/// truth for every battle / growth constant (shared with the TS engine).
///
/// Pure Dart (no Flutter import) so it can be used from tools and tests. The
/// Flutter asset loader lives in `battle_spec_asset.dart`.
library;

import 'dart:convert';

import '../character.dart' show EvolutionStage;
import '../element_type.dart';
import 'battle_types.dart';

int _i(Map<String, Object?> j, String k) => (j[k]! as num).toInt();
Map<String, Object?> _m(Map<String, Object?> j, String k) =>
    (j[k]! as Map).cast<String, Object?>();

class DamageSpec {
  const DamageSpec({
    required this.scalePct,
    required this.basePower,
    required this.defenseWeight,
    required this.minDamage,
    required this.critChancePct,
    required this.critMultiplierPct,
    required this.varianceMinPct,
    required this.varianceMaxPct,
  });

  final int scalePct;

  /// Untyped power added to every attack after the type multiplier.
  final int basePower;

  /// k in `eff = floor(atk * (atk + k*def) / ((k+1) * def))`; larger k makes
  /// the atk/def ratio matter less.
  final int defenseWeight;
  final int minDamage;
  final int critChancePct;
  final int critMultiplierPct;
  final int varianceMinPct;
  final int varianceMaxPct;

  factory DamageSpec.fromJson(Map<String, Object?> j) => DamageSpec(
    scalePct: _i(j, 'scalePct'),
    basePower: _i(j, 'basePower'),
    defenseWeight: _i(j, 'defenseWeight'),
    minDamage: _i(j, 'minDamage'),
    critChancePct: _i(j, 'critChancePct'),
    critMultiplierPct: _i(j, 'critMultiplierPct'),
    varianceMinPct: _i(j, 'varianceMinPct'),
    varianceMaxPct: _i(j, 'varianceMaxPct'),
  );

  Map<String, Object?> toJson() => {
    'scalePct': scalePct,
    'basePower': basePower,
    'defenseWeight': defenseWeight,
    'minDamage': minDamage,
    'critChancePct': critChancePct,
    'critMultiplierPct': critMultiplierPct,
    'varianceMinPct': varianceMinPct,
    'varianceMaxPct': varianceMaxPct,
  };
}

class TypeChartSpec {
  const TypeChartSpec({
    required this.advantagePct,
    required this.disadvantagePct,
    required this.neutralPct,
    required this.matrix,
  });

  final int advantagePct;
  final int disadvantagePct;
  final int neutralPct;

  /// matrix[attacker][defender] = damage multiplier in percent.
  final Map<ElementType, Map<ElementType, int>> matrix;

  int multiplierPct(ElementType attacker, ElementType defender) =>
      matrix[attacker]![defender]!;

  factory TypeChartSpec.fromJson(Map<String, Object?> j) {
    final raw = _m(j, 'matrix');
    return TypeChartSpec(
      advantagePct: _i(j, 'advantagePct'),
      disadvantagePct: _i(j, 'disadvantagePct'),
      neutralPct: _i(j, 'neutralPct'),
      matrix: {
        for (final a in ElementType.values)
          a: {
            for (final d in ElementType.values)
              d: ((raw[a.name]! as Map)[d.name]! as num).toInt(),
          },
      },
    );
  }

  Map<String, Object?> toJson() => {
    'advantagePct': advantagePct,
    'disadvantagePct': disadvantagePct,
    'neutralPct': neutralPct,
    'matrix': {
      for (final a in matrix.entries)
        a.key.name: {for (final d in a.value.entries) d.key.name: d.value},
    },
  };
}

class AttackMoveSpec {
  const AttackMoveSpec({
    required this.label,
    required this.power,
    required this.accuracyPct,
    required this.typed,
  });

  final String label;
  final int power;
  final int accuracyPct;

  /// Whether the type chart applies (uses the attacker's element).
  final bool typed;

  factory AttackMoveSpec.fromJson(Map<String, Object?> j) => AttackMoveSpec(
    label: j['label']! as String,
    power: _i(j, 'power'),
    accuracyPct: _i(j, 'accuracyPct'),
    typed: j['typed']! as bool,
  );

  Map<String, Object?> toJson() => {
    'label': label,
    'power': power,
    'accuracyPct': accuracyPct,
    'typed': typed,
  };
}

class GuardMoveSpec {
  const GuardMoveSpec({
    required this.label,
    required this.damageTakenPctByStreak,
  });

  final String label;

  /// Damage taken (percent) for the 1st, 2nd, 3rd+ consecutive guard.
  final List<int> damageTakenPctByStreak;

  /// [streak] >= 1 is the number of consecutive guards including this one.
  int damageTakenPct(int streak) {
    final i = streak - 1;
    return damageTakenPctByStreak[i < damageTakenPctByStreak.length
        ? i
        : damageTakenPctByStreak.length - 1];
  }

  factory GuardMoveSpec.fromJson(Map<String, Object?> j) => GuardMoveSpec(
    label: j['label']! as String,
    damageTakenPctByStreak: [
      for (final v in j['damageTakenPctByStreak']! as List) (v as num).toInt(),
    ],
  );

  Map<String, Object?> toJson() => {
    'label': label,
    'damageTakenPctByStreak': damageTakenPctByStreak,
  };
}

class MovesSpec {
  const MovesSpec({
    required this.tackle,
    required this.element,
    required this.guard,
    required this.special,
  });

  final AttackMoveSpec tackle;
  final AttackMoveSpec element;
  final GuardMoveSpec guard;
  final AttackMoveSpec special;

  AttackMoveSpec attack(BattleAction move) => switch (move) {
    BattleAction.tackle => tackle,
    BattleAction.element => element,
    BattleAction.special => special,
    _ => throw ArgumentError.value(move, 'move', 'not an attack'),
  };

  factory MovesSpec.fromJson(Map<String, Object?> j) => MovesSpec(
    tackle: AttackMoveSpec.fromJson(_m(j, 'tackle')),
    element: AttackMoveSpec.fromJson(_m(j, 'element')),
    guard: GuardMoveSpec.fromJson(_m(j, 'guard')),
    special: AttackMoveSpec.fromJson(_m(j, 'special')),
  );

  Map<String, Object?> toJson() => {
    'tackle': tackle.toJson(),
    'element': element.toJson(),
    'guard': guard.toJson(),
    'special': special.toJson(),
  };
}

class GaugeSpec {
  const GaugeSpec({
    required this.max,
    required this.onHit,
    required this.onMiss,
    required this.onGuard,
    required this.onDamagedFlat,
    required this.onDamagedPctOfMaxHp,
  });

  final int max;

  /// Gained by the attacker when tackle / element hits.
  final int onHit;

  /// Gained by the attacker when tackle / element misses.
  final int onMiss;

  /// Gained when using まもる.
  final int onGuard;

  /// Gained by the defender when it takes damage (and survives):
  /// `onDamagedFlat + floor(hpLost * onDamagedPctOfMaxHp / maxHp)`.
  final int onDamagedFlat;
  final int onDamagedPctOfMaxHp;

  factory GaugeSpec.fromJson(Map<String, Object?> j) => GaugeSpec(
    max: _i(j, 'max'),
    onHit: _i(j, 'onHit'),
    onMiss: _i(j, 'onMiss'),
    onGuard: _i(j, 'onGuard'),
    onDamagedFlat: _i(j, 'onDamagedFlat'),
    onDamagedPctOfMaxHp: _i(j, 'onDamagedPctOfMaxHp'),
  );

  Map<String, Object?> toJson() => {
    'max': max,
    'onHit': onHit,
    'onMiss': onMiss,
    'onGuard': onGuard,
    'onDamagedFlat': onDamagedFlat,
    'onDamagedPctOfMaxHp': onDamagedPctOfMaxHp,
  };
}

class EvolutionSpec {
  const EvolutionSpec({
    required this.level,
    required this.stage,
    required this.specialPowerBonus,
  });

  final int level;
  final EvolutionStage stage;
  final int specialPowerBonus;

  factory EvolutionSpec.fromJson(Map<String, Object?> j) => EvolutionSpec(
    level: _i(j, 'level'),
    stage: EvolutionStage.values.byName(j['stage']! as String),
    specialPowerBonus: _i(j, 'specialPowerBonus'),
  );

  Map<String, Object?> toJson() => {
    'level': level,
    'stage': stage.name,
    'specialPowerBonus': specialPowerBonus,
  };
}

class GrowthSpec {
  const GrowthSpec({
    required this.maxLevel,
    required this.levelUpStatPct,
    required this.shoboLevelUpStatPct,
    required this.shoboSkillAbove,
    required this.seedStatPct,
    required this.seedsPerLevel,
    required this.xpToNextBase,
    required this.xpToNextPerLevel,
    required this.evolutions,
  });

  final int maxLevel;

  /// Stat growth per level (percent of Lv1 stats) for normal characters.
  final int levelUpStatPct;

  /// Stat growth per level for しょぼキャラ (「育てれば戦える」, SPEC §4.2).
  final int shoboLevelUpStatPct;

  /// A character is しょぼ when skill > shoboSkillAbove (SPEC §1).
  final int shoboSkillAbove;
  final int seedStatPct;
  final int seedsPerLevel;
  final int xpToNextBase;
  final int xpToNextPerLevel;

  /// Sorted by level ascending.
  final List<EvolutionSpec> evolutions;

  int levelUpPct({required bool isShobo}) =>
      isShobo ? shoboLevelUpStatPct : levelUpStatPct;

  factory GrowthSpec.fromJson(Map<String, Object?> j) => GrowthSpec(
    maxLevel: _i(j, 'maxLevel'),
    levelUpStatPct: _i(j, 'levelUpStatPct'),
    shoboLevelUpStatPct: _i(j, 'shoboLevelUpStatPct'),
    shoboSkillAbove: _i(j, 'shoboSkillAbove'),
    seedStatPct: _i(j, 'seedStatPct'),
    seedsPerLevel: _i(j, 'seedsPerLevel'),
    xpToNextBase: _i(j, 'xpToNextBase'),
    xpToNextPerLevel: _i(j, 'xpToNextPerLevel'),
    evolutions: [
      for (final e in j['evolutions']! as List)
        EvolutionSpec.fromJson((e as Map).cast<String, Object?>()),
    ],
  );

  Map<String, Object?> toJson() => {
    'maxLevel': maxLevel,
    'levelUpStatPct': levelUpStatPct,
    'shoboLevelUpStatPct': shoboLevelUpStatPct,
    'shoboSkillAbove': shoboSkillAbove,
    'seedStatPct': seedStatPct,
    'seedsPerLevel': seedsPerLevel,
    'xpToNextBase': xpToNextBase,
    'xpToNextPerLevel': xpToNextPerLevel,
    'evolutions': [for (final e in evolutions) e.toJson()],
  };
}

class XpSpec {
  const XpSpec({
    required this.win,
    required this.lose,
    required this.shoboBonusPct,
    required this.adBoostMultiplier,
  });

  final int win;
  final int lose;
  final int shoboBonusPct;
  final int adBoostMultiplier;

  factory XpSpec.fromJson(Map<String, Object?> j) => XpSpec(
    win: _i(j, 'win'),
    lose: _i(j, 'lose'),
    shoboBonusPct: _i(j, 'shoboBonusPct'),
    adBoostMultiplier: _i(j, 'adBoostMultiplier'),
  );

  Map<String, Object?> toJson() => {
    'win': win,
    'lose': lose,
    'shoboBonusPct': shoboBonusPct,
    'adBoostMultiplier': adBoostMultiplier,
  };
}

class WeakAiSpec {
  const WeakAiSpec({
    required this.tackleWeight,
    required this.elementWeight,
    required this.guardWeight,
    required this.specialWeight,
  });

  final int tackleWeight;
  final int elementWeight;
  final int guardWeight;

  /// Only counted when the special gauge is full.
  final int specialWeight;

  factory WeakAiSpec.fromJson(Map<String, Object?> j) => WeakAiSpec(
    tackleWeight: _i(j, 'tackleWeight'),
    elementWeight: _i(j, 'elementWeight'),
    guardWeight: _i(j, 'guardWeight'),
    specialWeight: _i(j, 'specialWeight'),
  );

  Map<String, Object?> toJson() => {
    'tackleWeight': tackleWeight,
    'elementWeight': elementWeight,
    'guardWeight': guardWeight,
    'specialWeight': specialWeight,
  };
}

class NormalAiSpec {
  const NormalAiSpec({required this.guardChancePct});

  final int guardChancePct;

  factory NormalAiSpec.fromJson(Map<String, Object?> j) =>
      NormalAiSpec(guardChancePct: _i(j, 'guardChancePct'));

  Map<String, Object?> toJson() => {'guardChancePct': guardChancePct};
}

class StrongAiSpec {
  const StrongAiSpec({
    required this.guardVsSpecialPct,
    required this.opponentGuardRatePct,
    required this.opponentGuardMinSamples,
  });

  /// Chance to まもる when the opponent's ready ひっさつ could KO us and
  /// guarding would let us survive.
  final int guardVsSpecialPct;

  /// The opponent counts as a habitual guarder when it used まもる in at
  /// least this percentage of its (>= opponentGuardMinSamples) turns.
  final int opponentGuardRatePct;
  final int opponentGuardMinSamples;

  factory StrongAiSpec.fromJson(Map<String, Object?> j) => StrongAiSpec(
    guardVsSpecialPct: _i(j, 'guardVsSpecialPct'),
    opponentGuardRatePct: _i(j, 'opponentGuardRatePct'),
    opponentGuardMinSamples: _i(j, 'opponentGuardMinSamples'),
  );

  Map<String, Object?> toJson() => {
    'guardVsSpecialPct': guardVsSpecialPct,
    'opponentGuardRatePct': opponentGuardRatePct,
    'opponentGuardMinSamples': opponentGuardMinSamples,
  };
}

class AiSpec {
  const AiSpec({
    required this.weak,
    required this.normal,
    required this.strong,
  });

  final WeakAiSpec weak;
  final NormalAiSpec normal;
  final StrongAiSpec strong;

  factory AiSpec.fromJson(Map<String, Object?> j) => AiSpec(
    weak: WeakAiSpec.fromJson(_m(j, 'weak')),
    normal: NormalAiSpec.fromJson(_m(j, 'normal')),
    strong: StrongAiSpec.fromJson(_m(j, 'strong')),
  );

  Map<String, Object?> toJson() => {
    'weak': weak.toJson(),
    'normal': normal.toJson(),
    'strong': strong.toJson(),
  };
}

/// One row of the CPU stage table.
class CpuStage {
  const CpuStage({
    required this.stage,
    required this.cpuId,
    required this.level,
    required this.recommendedLevel,
    required this.aiTier,
    required this.xpMultiplierPct,
  });

  final int stage;

  /// Id of a bundled CPU doodle (`app/assets/cpu/manifest.json`).
  final String cpuId;

  /// CPU level (tuned per doodle so the stages form a smooth difficulty
  /// curve; see docs/BATTLE.md §7).
  final int level;

  /// Player level the stage is designed for (「おすすめ Lv」).
  final int recommendedLevel;
  final AiTier aiTier;
  final int xpMultiplierPct;

  factory CpuStage.fromJson(Map<String, Object?> j) => CpuStage(
    stage: _i(j, 'stage'),
    cpuId: j['cpuId']! as String,
    level: _i(j, 'level'),
    recommendedLevel: _i(j, 'recommendedLevel'),
    aiTier: AiTier.values.byName(j['aiTier']! as String),
    xpMultiplierPct: _i(j, 'xpMultiplierPct'),
  );

  Map<String, Object?> toJson() => {
    'stage': stage,
    'cpuId': cpuId,
    'level': level,
    'recommendedLevel': recommendedLevel,
    'aiTier': aiTier.name,
    'xpMultiplierPct': xpMultiplierPct,
  };
}

class CpuSpec {
  const CpuSpec({required this.characterIds, required this.stages});

  /// Ids of the bundled CPU doodles (`app/assets/cpu/manifest.json`).
  final List<String> characterIds;
  final List<CpuStage> stages;

  /// Stage row for 1-based [stage].
  CpuStage stage(int stage) => stages.firstWhere((s) => s.stage == stage);

  factory CpuSpec.fromJson(Map<String, Object?> j) => CpuSpec(
    characterIds: [for (final v in j['characterIds']! as List) v as String],
    stages: [
      for (final s in j['stages']! as List)
        CpuStage.fromJson((s as Map).cast<String, Object?>()),
    ],
  );

  Map<String, Object?> toJson() => {
    'characterIds': characterIds,
    'stages': [for (final s in stages) s.toJson()],
  };
}

/// Root of battle_spec.json.
class BattleSpec {
  const BattleSpec({
    required this.specVersion,
    required this.hpMultiplier,
    required this.turnCap,
    required this.timeoutAction,
    required this.damage,
    required this.typeChart,
    required this.moves,
    required this.gauge,
    required this.growth,
    required this.xp,
    required this.ai,
    required this.texts,
    required this.cpu,
  });

  final int specVersion;

  /// Displayed / battle HP = stats.hp * hpMultiplier.
  final int hpMultiplier;

  /// After this many turns the battle ends; higher HP% wins.
  final int turnCap;

  /// Action used when a player runs out of time.
  final BattleAction timeoutAction;
  final DamageSpec damage;
  final TypeChartSpec typeChart;
  final MovesSpec moves;
  final GaugeSpec gauge;
  final GrowthSpec growth;
  final XpSpec xp;
  final AiSpec ai;

  /// UI strings for battle messages (hiragana).
  final Map<String, String> texts;
  final CpuSpec cpu;

  factory BattleSpec.fromJson(Map<String, Object?> j) => BattleSpec(
    specVersion: _i(j, 'specVersion'),
    hpMultiplier: _i(j, 'hpMultiplier'),
    turnCap: _i(j, 'turnCap'),
    timeoutAction: BattleAction.values.byName(j['timeoutAction']! as String),
    damage: DamageSpec.fromJson(_m(j, 'damage')),
    typeChart: TypeChartSpec.fromJson(_m(j, 'typeChart')),
    moves: MovesSpec.fromJson(_m(j, 'moves')),
    gauge: GaugeSpec.fromJson(_m(j, 'gauge')),
    growth: GrowthSpec.fromJson(_m(j, 'growth')),
    xp: XpSpec.fromJson(_m(j, 'xp')),
    ai: AiSpec.fromJson(_m(j, 'ai')),
    texts: _m(j, 'texts').cast<String, String>(),
    cpu: CpuSpec.fromJson(_m(j, 'cpu')),
  );

  factory BattleSpec.fromJsonString(String source) =>
      BattleSpec.fromJson((jsonDecode(source) as Map).cast<String, Object?>());

  Map<String, Object?> toJson() => {
    'specVersion': specVersion,
    'hpMultiplier': hpMultiplier,
    'turnCap': turnCap,
    'timeoutAction': timeoutAction.name,
    'damage': damage.toJson(),
    'typeChart': typeChart.toJson(),
    'moves': moves.toJson(),
    'gauge': gauge.toJson(),
    'growth': growth.toJson(),
    'xp': xp.toJson(),
    'ai': ai.toJson(),
    'texts': Map<String, String>.of(texts),
    'cpu': cpu.toJson(),
  };
}
