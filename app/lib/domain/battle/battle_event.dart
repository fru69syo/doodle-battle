import '../element_type.dart';
import 'battle_types.dart';

/// Something that happened during a turn, in the order the UI should animate
/// it. `toJson()` is the wire format shared with the TS engine (see
/// docs/BATTLE.md §5); `type` is the discriminator.
sealed class BattleEvent {
  const BattleEvent();

  String get type;

  Map<String, Object?> toJson();

  static BattleEvent fromJson(Map<String, Object?> j) {
    Side side(String k) => Side.values.byName(j[k]! as String);
    int n(String k) => j[k]! as int;
    return switch (j['type']) {
      'turnStart' => TurnStartEvent(n('turn')),
      'timeout' => TimeoutEvent(side('side')),
      'specialNotReady' => SpecialNotReadyEvent(side('side')),
      'guard' => GuardEvent(
        side('side'),
        damageTakenPct: n('damageTakenPct'),
        weakened: j['weakened']! as bool,
      ),
      'move' => MoveEvent(
        side('side'),
        BattleAction.values.byName(j['move']! as String),
        element: j['element'] == null
            ? null
            : ElementType.fromName(j['element']! as String),
      ),
      'miss' => MissEvent(side('side')),
      'crit' => CritEvent(side('side')),
      'effectiveness' => EffectivenessEvent(
        side('side'),
        multiplierPct: n('multiplierPct'),
        text: j['text']! as String,
      ),
      'damage' => DamageEvent(
        side('target'),
        amount: n('amount'),
        hp: n('hp'),
        guarded: j['guarded']! as bool,
      ),
      'gauge' => GaugeEvent(side('side'), delta: n('delta'), value: n('value')),
      'faint' => FaintEvent(side('side')),
      'battleEnd' => BattleEndEvent(
        side('winner'),
        EndReason.values.byName(j['reason']! as String),
      ),
      _ => throw FormatException('unknown event type ${j['type']}'),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is BattleEvent && _mapEq(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);

  @override
  String toString() => toJson().toString();
}

bool _mapEq(Map<String, Object?> x, Map<String, Object?> y) {
  if (x.length != y.length) return false;
  for (final e in x.entries) {
    if (!y.containsKey(e.key) || y[e.key] != e.value) return false;
  }
  return true;
}

/// A new turn begins (1-based).
class TurnStartEvent extends BattleEvent {
  const TurnStartEvent(this.turn);
  final int turn;
  @override
  String get type => 'turnStart';
  @override
  Map<String, Object?> toJson() => {'type': type, 'turn': turn};
}

/// [side] ran out of time; it will use たいあたり. 「じかんぎれ！」
class TimeoutEvent extends BattleEvent {
  const TimeoutEvent(this.side);
  final Side side;
  @override
  String get type => 'timeout';
  @override
  Map<String, Object?> toJson() => {'type': type, 'side': side.name};
}

/// [side] chose ひっさつ without a full gauge; it will use たいあたり.
class SpecialNotReadyEvent extends BattleEvent {
  const SpecialNotReadyEvent(this.side);
  final Side side;
  @override
  String get type => 'specialNotReady';
  @override
  Map<String, Object?> toJson() => {'type': type, 'side': side.name};
}

/// [side] uses まもる; it takes [damageTakenPct]% damage this turn.
/// [weakened] when used consecutively (「まもりが よわく なっている…」).
class GuardEvent extends BattleEvent {
  const GuardEvent(
    this.side, {
    required this.damageTakenPct,
    required this.weakened,
  });
  final Side side;
  final int damageTakenPct;
  final bool weakened;
  @override
  String get type => 'guard';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'side': side.name,
    'damageTakenPct': damageTakenPct,
    'weakened': weakened,
  };
}

/// [side] uses attack [move]; [element] is the element of a typed move
/// (null for たいあたり).
class MoveEvent extends BattleEvent {
  const MoveEvent(this.side, this.move, {this.element});
  final Side side;
  final BattleAction move;
  final ElementType? element;
  @override
  String get type => 'move';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'side': side.name,
    'move': move.name,
    'element': element?.name,
  };
}

/// [side]'s attack missed. 「でも はずれた！」
class MissEvent extends BattleEvent {
  const MissEvent(this.side);
  final Side side;
  @override
  String get type => 'miss';
  @override
  Map<String, Object?> toJson() => {'type': type, 'side': side.name};
}

/// [side]'s attack was a critical hit. 「きゅうしょに あたった！」
class CritEvent extends BattleEvent {
  const CritEvent(this.side);
  final Side side;
  @override
  String get type => 'crit';
  @override
  Map<String, Object?> toJson() => {'type': type, 'side': side.name};
}

/// Type effectiveness of [side]'s attack (only emitted when not neutral).
class EffectivenessEvent extends BattleEvent {
  const EffectivenessEvent(
    this.side, {
    required this.multiplierPct,
    required this.text,
  });
  final Side side;
  final int multiplierPct;

  /// e.g. 「こうかは ばつぐんだ！」 (from spec.texts).
  final String text;
  bool get isSuper => multiplierPct > 100;
  @override
  String get type => 'effectiveness';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'side': side.name,
    'multiplierPct': multiplierPct,
    'text': text,
  };
}

/// [target] lost [amount] HP (already clamped to remaining HP) and now has
/// [hp]. [guarded] when the target used まもる this turn.
class DamageEvent extends BattleEvent {
  const DamageEvent(
    this.target, {
    required this.amount,
    required this.hp,
    required this.guarded,
  });
  final Side target;
  final int amount;
  final int hp;
  final bool guarded;
  @override
  String get type => 'damage';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'target': target.name,
    'amount': amount,
    'hp': hp,
    'guarded': guarded,
  };
}

/// [side]'s gauge changed by [delta] (negative when ひっさつ is used) to
/// [value].
class GaugeEvent extends BattleEvent {
  const GaugeEvent(this.side, {required this.delta, required this.value});
  final Side side;
  final int delta;
  final int value;
  @override
  String get type => 'gauge';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'side': side.name,
    'delta': delta,
    'value': value,
  };
}

/// [side] fainted. 「たおれた！」
class FaintEvent extends BattleEvent {
  const FaintEvent(this.side);
  final Side side;
  @override
  String get type => 'faint';
  @override
  Map<String, Object?> toJson() => {'type': type, 'side': side.name};
}

/// The battle is over.
class BattleEndEvent extends BattleEvent {
  const BattleEndEvent(this.winner, this.reason);
  final Side winner;
  final EndReason reason;
  @override
  String get type => 'battleEnd';
  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'winner': winner.name,
    'reason': reason.name,
  };
}
