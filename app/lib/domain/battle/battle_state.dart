import '../element_type.dart';
import 'battle_types.dart';

/// How often a fighter used each move this battle (used by the つよい AI to
/// read the opponent's tendencies).
class MoveUsage {
  const MoveUsage({
    this.tackle = 0,
    this.element = 0,
    this.guard = 0,
    this.special = 0,
  });

  final int tackle;
  final int element;
  final int guard;
  final int special;

  int get total => tackle + element + guard + special;

  MoveUsage increment(BattleAction move) => MoveUsage(
    tackle: tackle + (move == BattleAction.tackle ? 1 : 0),
    element: element + (move == BattleAction.element ? 1 : 0),
    guard: guard + (move == BattleAction.guard ? 1 : 0),
    special: special + (move == BattleAction.special ? 1 : 0),
  );

  Map<String, Object?> toJson() => {
    'tackle': tackle,
    'element': element,
    'guard': guard,
    'special': special,
  };

  factory MoveUsage.fromJson(Map<String, Object?> j) => MoveUsage(
    tackle: j['tackle']! as int,
    element: j['element']! as int,
    guard: j['guard']! as int,
    special: j['special']! as int,
  );

  @override
  bool operator ==(Object other) =>
      other is MoveUsage &&
      other.tackle == tackle &&
      other.element == element &&
      other.guard == guard &&
      other.special == special;

  @override
  int get hashCode => Object.hash(tackle, element, guard, special);
}

/// One fighter's in-battle state. All numbers are integers.
class FighterState {
  const FighterState({
    required this.element,
    required this.level,
    required this.maxHp,
    required this.hp,
    required this.atk,
    required this.def,
    required this.spd,
    required this.specialPower,
    this.gauge = 0,
    this.guardStreak = 0,
    this.usage = const MoveUsage(),
    this.lastAction,
  });

  final ElementType element;
  final int level;

  /// Battle HP (= stats.hp * spec.hpMultiplier).
  final int maxHp;
  final int hp;
  final int atk;
  final int def;
  final int spd;

  /// ひっさつ power incl. evolution bonus (でんせつ +20).
  final int specialPower;

  /// ひっさつ gauge, 0..spec.gauge.max.
  final int gauge;

  /// Consecutive まもる count up to and including the last turn.
  final int guardStreak;
  final MoveUsage usage;

  /// Move actually performed last turn (after timeout / fallback).
  final BattleAction? lastAction;

  bool get fainted => hp <= 0;

  FighterState copyWith({
    int? hp,
    int? gauge,
    int? guardStreak,
    MoveUsage? usage,
    BattleAction? lastAction,
  }) => FighterState(
    element: element,
    level: level,
    maxHp: maxHp,
    hp: hp ?? this.hp,
    atk: atk,
    def: def,
    spd: spd,
    specialPower: specialPower,
    gauge: gauge ?? this.gauge,
    guardStreak: guardStreak ?? this.guardStreak,
    usage: usage ?? this.usage,
    lastAction: lastAction ?? this.lastAction,
  );

  Map<String, Object?> toJson() => {
    'element': element.name,
    'level': level,
    'maxHp': maxHp,
    'hp': hp,
    'atk': atk,
    'def': def,
    'spd': spd,
    'specialPower': specialPower,
    'gauge': gauge,
    'guardStreak': guardStreak,
    'usage': usage.toJson(),
    'lastAction': lastAction?.name,
  };

  factory FighterState.fromJson(Map<String, Object?> j) => FighterState(
    element: ElementType.fromName(j['element']! as String),
    level: j['level']! as int,
    maxHp: j['maxHp']! as int,
    hp: j['hp']! as int,
    atk: j['atk']! as int,
    def: j['def']! as int,
    spd: j['spd']! as int,
    specialPower: j['specialPower']! as int,
    gauge: j['gauge']! as int,
    guardStreak: j['guardStreak']! as int,
    usage: MoveUsage.fromJson((j['usage']! as Map).cast<String, Object?>()),
    lastAction: j['lastAction'] == null
        ? null
        : BattleAction.values.byName(j['lastAction']! as String),
  );

  @override
  bool operator ==(Object other) =>
      other is FighterState &&
      other.element == element &&
      other.level == level &&
      other.maxHp == maxHp &&
      other.hp == hp &&
      other.atk == atk &&
      other.def == def &&
      other.spd == spd &&
      other.specialPower == specialPower &&
      other.gauge == gauge &&
      other.guardStreak == guardStreak &&
      other.usage == usage &&
      other.lastAction == lastAction;

  @override
  int get hashCode => Object.hash(
    element,
    level,
    maxHp,
    hp,
    atk,
    def,
    spd,
    specialPower,
    gauge,
    guardStreak,
    usage,
    lastAction,
  );
}

/// Immutable battle snapshot. `turn` counts resolved turns (0 before the
/// first turn).
class BattleState {
  const BattleState({
    required this.a,
    required this.b,
    this.turn = 0,
    this.winner,
    this.endReason,
  });

  final FighterState a;
  final FighterState b;
  final int turn;
  final Side? winner;
  final EndReason? endReason;

  bool get isOver => winner != null;

  FighterState fighter(Side side) => side == Side.a ? a : b;

  BattleState withFighter(Side side, FighterState f) => BattleState(
    a: side == Side.a ? f : a,
    b: side == Side.b ? f : b,
    turn: turn,
    winner: winner,
    endReason: endReason,
  );

  Map<String, Object?> toJson() => {
    'turn': turn,
    'a': a.toJson(),
    'b': b.toJson(),
    'winner': winner?.name,
    'endReason': endReason?.name,
  };

  factory BattleState.fromJson(Map<String, Object?> j) => BattleState(
    turn: j['turn']! as int,
    a: FighterState.fromJson((j['a']! as Map).cast<String, Object?>()),
    b: FighterState.fromJson((j['b']! as Map).cast<String, Object?>()),
    winner: j['winner'] == null
        ? null
        : Side.values.byName(j['winner']! as String),
    endReason: j['endReason'] == null
        ? null
        : EndReason.values.byName(j['endReason']! as String),
  );

  @override
  bool operator ==(Object other) =>
      other is BattleState &&
      other.turn == turn &&
      other.a == a &&
      other.b == b &&
      other.winner == winner &&
      other.endReason == endReason;

  @override
  int get hashCode => Object.hash(turn, a, b, winner, endReason);
}
