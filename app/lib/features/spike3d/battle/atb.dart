import 'dart:math' as math;

/// A move in the prototype (numbers are placeholders; the real ones come
/// from the game-design team's templates, SPEC §12.3).
class SpikeMove {
  const SpikeMove(this.name, {required this.power, this.ranged = false});
  final String name;
  final int power;

  /// Ranged moves are thrown from where the attacker stands (no dash).
  final bool ranged;
}

class SpikeFighter {
  SpikeFighter({
    required this.name,
    required this.maxHp,
    required this.agi,
    required this.str,
    required this.def,
    required this.moves,
  }) : hp = maxHp;

  final String name;
  final int maxHp;
  final int agi, str, def;
  final List<SpikeMove> moves;
  int hp;

  /// 0..1; the fighter may act at 1.
  double gauge = 0;
  bool get alive => hp > 0;
}

/// Events from the battle simulation, consumed by the director/UI.
sealed class AtbEvent {
  const AtbEvent();
}

/// [side]'s gauge filled. For the player this opens the move menu.
class GaugeFull extends AtbEvent {
  const GaugeFull(this.side);
  final int side;
}

/// [side] uses [move] on the other side; [damage] is already decided (the
/// renderer shows it at the impact frame).
class ActionStarted extends AtbEvent {
  const ActionStarted(this.side, this.move, this.damage, {this.auto = false});
  final int side;
  final SpikeMove move;
  final int damage;

  /// Chosen by おまかせ (time-out or always-auto).
  final bool auto;
}

class BattleOver extends AtbEvent {
  const BattleOver(this.winner);
  final int winner;
}

/// Real-time ATB prototype (SPEC §12.4):
/// - gauges fill in proportion to AGI and never pause for the other side's
///   menu;
/// - a full gauge waits for a move; the player has [choiceSeconds] before
///   おまかせ picks one; the CPU decides after a short think;
/// - actions resolve one at a time ([actionLockSeconds], the time the 3D
///   scene needs to play an attack), queued in order.
///
/// Damage resolution happens here (client-side prototype). Online, the
/// server runs this and the client only renders (SPEC §12.4).
class AtbBattle {
  AtbBattle(
    this.fighters, {
    int seed = 1,
    this.baseFillSeconds = 3.0,
    this.choiceSeconds = 5.0,
    this.cpuThinkSeconds = 0.6,
    this.actionLockSeconds = 1.3,
    this.alwaysAuto = false,
  }) : _rng = math.Random(seed);

  /// [0] = player, [1] = CPU.
  final List<SpikeFighter> fighters;
  final double baseFillSeconds;
  final double choiceSeconds;
  final double cpuThinkSeconds;
  final double actionLockSeconds;

  /// おまかせ for the player too (small children, SPEC §12.4).
  bool alwaysAuto;

  final math.Random _rng;
  final _waiting = <int, double>{}; // side → seconds waited while full
  final _queue = <ActionStarted>[];
  double _lock = 0;
  int? winner;
  double time = 0;

  bool get over => winner != null;

  /// Seconds left for the player's choice, or null when not choosing.
  double? get playerChoiceLeft {
    final w = _waiting[0];
    if (w == null || alwaysAuto) return null;
    return math.max(0, choiceSeconds - w);
  }

  bool get playerCanChoose => playerChoiceLeft != null;

  /// Advances the simulation; returns the events of this step.
  List<AtbEvent> tick(double dt) {
    if (over) return const [];
    time += dt;
    final events = <AtbEvent>[];
    final agiSum = fighters.fold<int>(0, (s, f) => s + f.agi);
    for (var side = 0; side < fighters.length; side++) {
      final f = fighters[side];
      if (!f.alive) continue;
      if (_waiting.containsKey(side) || _queued(side)) {
        if (_waiting.containsKey(side)) _waiting[side] = _waiting[side]! + dt;
        continue;
      }
      // Equal AGI → both fill in baseFillSeconds.
      final rate = f.agi / (agiSum / fighters.length) / baseFillSeconds;
      f.gauge = math.min(1, f.gauge + rate * dt);
      if (f.gauge >= 1) {
        _waiting[side] = 0;
        events.add(GaugeFull(side));
      }
    }
    // Decisions that are due.
    for (final side in _waiting.keys.toList()) {
      final waited = _waiting[side]!;
      final auto = side != 0 || alwaysAuto;
      if (auto && waited >= (side == 0 ? 0.3 : cpuThinkSeconds)) {
        _commit(side, _aiPick(side), auto: true);
      } else if (!auto && waited >= choiceSeconds) {
        _commit(side, _aiPick(side), auto: true);
      }
    }
    // One action at a time.
    _lock = math.max(0, _lock - dt);
    if (_lock == 0 && _queue.isNotEmpty) {
      final a = _queue.removeAt(0);
      final attacker = fighters[a.side];
      final target = fighters[1 - a.side];
      if (attacker.alive && target.alive) {
        target.hp = math.max(0, target.hp - a.damage);
        attacker.gauge = 0;
        _lock = actionLockSeconds;
        events.add(a);
        if (!target.alive) {
          winner = a.side;
          events.add(BattleOver(a.side));
        }
      }
    }
    return events;
  }

  /// Player picks move [index] (ignored unless the menu is open).
  bool choose(int index) {
    if (!playerCanChoose) return false;
    _commit(0, index);
    return true;
  }

  bool _queued(int side) => _queue.any((a) => a.side == side);

  void _commit(int side, int moveIndex, {bool auto = false}) {
    _waiting.remove(side);
    final f = fighters[side];
    final move = f.moves[moveIndex.clamp(0, f.moves.length - 1)];
    final def = fighters[1 - side].def;
    final roll = 0.9 + _rng.nextDouble() * 0.2;
    final dmg = math.max(1, (move.power * f.str / math.max(1, def) * 0.5 * roll).round());
    _queue.add(ActionStarted(side, move, dmg, auto: auto));
  }

  int _aiPick(int side) {
    final moves = fighters[side].moves;
    var best = 0;
    for (var i = 1; i < moves.length; i++) {
      if (moves[i].power > moves[best].power) best = i;
    }
    // Mostly the strongest, sometimes a random one.
    return _rng.nextDouble() < 0.7 ? best : _rng.nextInt(moves.length);
  }
}
