import '../../../domain/battle_v2/battle_v2.dart';
import '../stage_events.dart';

/// [StageFeed] over the prototype v3 ATB engine (`domain/battle_v2`): steps
/// it at 10 Hz in real time and translates its event log. The Engine v3
/// team's production engine emits the same event types; the integration
/// keeps an adapter of this shape (it is ~150 lines on purpose).
///
/// Also owns the player's input for one-player battles: [tap] (さきどり when
/// the gauge is not full yet), [alwaysAuto] (おまかせ), [choiceLeft] (the
/// 5 s ring).
class BattleV2Feed implements StageFeed {
  BattleV2Feed(this.engine, {this.alwaysAuto = false});

  final AtbBattle engine;

  /// おまかせ for the player.
  bool alwaysAuto;

  /// Move tapped by the player, used on the tick the gauge is full
  /// (さきどり when tapped early, GAME_DESIGN_V2 §6.3).
  int? pending;

  double _acc = 0;
  int _seen = 0;
  final _cpu = aiController();
  final _auto = aiController();

  int? _player(AtbBattle b, int side) => alwaysAuto ? _auto(b, side) : pending;

  /// Seconds left to choose (only while the player's gauge is full).
  double? get choiceLeft {
    final f = engine.fighters[0];
    if (f.phase != Phase.ready || alwaysAuto || engine.finished) return null;
    return (engine.spec.decisionTicks - f.readyTicks) / engine.spec.tickHz;
  }

  double get decisionSeconds => engine.spec.decisionTicks / engine.spec.tickHz;

  /// The player taps move [slot]; false when it can not be queued now.
  bool tap(int slot) {
    final f = engine.fighters[0];
    if (engine.finished || slot >= f.moves.length) return false;
    if (f.phase == Phase.casting || alwaysAuto) return false;
    pending = slot;
    return true;
  }

  bool usable(int slot) => engine.fighters[0].usable(slot);

  @override
  List<StageEvent> advance(double dt) {
    _acc += dt;
    while (_acc >= 0.1 && !engine.finished) {
      _acc -= 0.1;
      engine.step(_player, _cpu);
    }
    final out = <StageEvent>[];
    final ev = engine.events;
    while (_seen < ev.length) {
      final e = ev[_seen++];
      final d = e.data;
      switch (e.type) {
        case 'ready':
          out.add(StageReady(d['side']! as int));
        case 'choose':
          final side = d['side']! as int;
          if (side == 0) pending = null;
          final auto = _seen >= 2 && ev[_seen - 2].type == 'autoPick';
          out.add(
            StageChoose(
              side,
              castSeconds: (d['cast']! as int) / engine.spec.tickHz,
              auto: auto,
            ),
          );
        case 'move':
          out.add(_action(e));
        case 'damage' when d['cause'] == 'poison':
          out.add(
            StagePoisonTick(
              d['target']! as int,
              d['amount']! as int,
              d['hp']! as int,
            ),
          );
        case 'end':
          out.add(StageEnd(d['winner']! as int));
      }
    }
    return out;
  }

  /// Groups a `move` with the results logged on the same tick after it.
  StageAction _action(BattleEventV2 e) {
    final side = e.data['side']! as int;
    final slot = e.data['slot']! as int;
    final m = engine.fighters[side].moves[slot];
    final defender = engine.fighters[1 - side];
    final ev = engine.events;
    final hits = <StageHit>[];
    final outcomes = <StageOutcome>[];
    var crit = false;
    for (var i = _seen; i < ev.length; i++) {
      final r = ev[i];
      if (r.tick != e.tick || r.type == 'move' || r.type == 'end') break;
      final d = r.data;
      switch (r.type) {
        case 'crit':
          crit = true;
        case 'damage' when d['cause'] != 'poison':
          final eff = switch (typeChart(m.attr, defender.attr, engine.spec)) {
            > 100 => StageEffectiveness.strong,
            < 100 => StageEffectiveness.weak,
            _ => StageEffectiveness.normal,
          };
          hits.add(
            StageHit(
              target: d['target']! as int,
              amount: d['amount']! as int,
              hpAfter: d['hp']! as int,
              crit: crit,
              effectiveness: eff,
            ),
          );
          crit = false;
        case 'miss':
          hits.add(StageHit(target: 1 - side));
        case 'heal':
          outcomes.add(
            StageHealed(
              d['side']! as int,
              d['amount']! as int,
              d['hp']! as int,
            ),
          );
        case 'status':
          outcomes.add(
            StageStatus(
              d['target']! as int,
              d['status'] == 'poison'
                  ? StageStatusKind.poison
                  : StageStatusKind.paralyze,
            ),
          );
        case 'stage':
          outcomes.add(
            StageStatChange(d['side']! as int, up: (d['stage']! as int) > 0),
          );
        case 'shield':
          outcomes.add(StageShieldUp(d['side']! as int));
      }
    }
    return StageAction(
      side: side,
      slot: slot,
      move: stageMoveOf(m, special: slot == 3),
      hits: hits,
      outcomes: outcomes,
    );
  }

  @override
  StageFighterState fighter(int side) {
    final f = engine.fighters[side];
    var up = false, down = false;
    for (final s in f.stages) {
      if (s > 0) up = true;
      if (s < 0) down = true;
    }
    return StageFighterState(
      maxHp: f.maxHp,
      gauge: f.gauge / engine.spec.gaugeMax,
      ready: f.phase == Phase.ready,
      casting: f.phase == Phase.casting,
      poisoned: f.poisonTicks > 0,
      paralyzed: f.paralyzeTicks > 0,
      shield: f.shieldTicks > 0 ? f.shieldPct / 100 : 0,
      statUp: up,
      statDown: down,
      sp: f.sp ~/ 100,
    );
  }
}

/// Display data of an engine move.
StageMove stageMoveOf(MoveV2 m, {bool special = false, bool drawn = false}) =>
    StageMove(
      name: m.name.isEmpty ? m.template : m.name,
      kind: switch (m.kind) {
        MoveKind.physical => StageMoveKind.physical,
        MoveKind.special ||
        MoveKind.debuff ||
        MoveKind.status => StageMoveKind.ranged,
        MoveKind.heal || MoveKind.buff || MoveKind.shield => StageMoveKind.self,
      },
      vfx: m.vfx,
      colour: m.colour,
      hits: m.hits,
      special: special,
      drawnEffect: drawn,
    );
