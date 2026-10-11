import '../../../domain/battle_v3/battle_v3.dart';
import '../stage_events.dart';

/// [StageFeed] over the battle engine v3 (`domain/battle_v3`): steps it at
/// 10 Hz in real time and translates its renderer events (ready, select,
/// moveStart, effective, hit, miss, dot, heal, stage, status, shield,
/// expire, heatUp, faint, end — docs/BATTLE_V3.md) into stage events.
///
/// Online, the same translation runs over the server's event stream:
/// buffer its events 150–250 ms and hand them to [translate] instead of
/// stepping a local engine.
///
/// Also owns the player's input for local battles: [tap] (さきどり is the
/// engine's own queued input), [alwaysAuto] (おまかせ), [choiceLeft] (the
/// 5 s ring).
class BattleV3Feed implements StageFeed {
  BattleV3Feed(this.engine, {this.alwaysAuto = false, Controller? cpu})
    : _cpu = cpu ?? aiController();

  final Battle engine;

  /// おまかせ for the player.
  bool alwaysAuto;

  double _acc = 0;
  int _seen = 0;
  final Controller _cpu;
  final _auto = aiController();

  /// Move tapped by the player and not used yet (さきどり / chosen).
  int? get pending => engine.fighters[0].queued;

  /// Seconds left to choose (only while the player's gauge is full).
  double? get choiceLeft {
    final f = engine.fighters[0];
    if (f.phase != Phase.ready || alwaysAuto || engine.finished) return null;
    return f.decisionTicksLeft(engine.spec) / engine.spec.tickHz;
  }

  double get decisionSeconds => engine.spec.decisionTicks / engine.spec.tickHz;

  /// The player taps move [slot]; false when it can not be queued now.
  bool tap(int slot) {
    final f = engine.fighters[0];
    if (engine.finished || slot < 0 || slot >= f.moves.length) return false;
    if (f.phase == Phase.casting || alwaysAuto) return false;
    engine.queueInput(0, slot);
    return true;
  }

  void cancelTap() => engine.clearInput(0);

  bool usable(int slot) => engine.fighters[0].usable(slot);

  @override
  List<StageEvent> advance(double dt) {
    _acc += dt;
    while (_acc >= 0.1 && !engine.finished) {
      _acc -= 0.1;
      engine.step(a: alwaysAuto ? _auto : null, b: _cpu);
    }
    final ev = engine.events;
    final out = translate(ev.sublist(_seen), moves: _movesOf);
    _seen = ev.length;
    return out;
  }

  Move _movesOf(int side, int slot) => engine.fighters[side].moves[slot];

  @override
  StageFighterState fighter(int side) => fighterState(engine, side);
}

/// The stage state of fighter [side] of a v3 battle.
StageFighterState fighterState(Battle b, int side) {
  final f = b.fighters[side];
  var up = false, down = false;
  for (final s in f.stages) {
    if (s > 0) up = true;
    if (s < 0) down = true;
  }
  return StageFighterState(
    maxHp: f.maxHp,
    gauge: f.gauge / b.spec.gaugeMax,
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

/// Translates v3 renderer events (in order) into stage events. A
/// `moveStart` is grouped with the results logged after it on the same
/// tick. [moves] looks up the move of a side's slot (display data only).
List<StageEvent> translate(
  List<BattleEvent> ev, {
  required Move Function(int side, int slot) moves,
  int tickHz = 10,
}) {
  final out = <StageEvent>[];
  for (var k = 0; k < ev.length; k++) {
    final e = ev[k];
    switch (e.type) {
      case 'ready':
        out.add(StageReady(e.i('side')!));
      case 'select':
        out.add(
          StageChoose(
            e.i('side')!,
            castSeconds: (e.i('cast') ?? 0) / tickHz,
            auto: e.i('auto') == 1,
          ),
        );
      case 'moveStart':
        final side = e.i('side')!, slot = e.i('slot')!;
        final hits = <StageHit>[];
        final outcomes = <StageOutcome>[];
        var j = k + 1;
        for (; j < ev.length; j++) {
          final r = ev[j];
          if (r.tick != e.tick || r.type == 'moveStart') break;
          switch (r.type) {
            case 'hit':
              final pct = r.i('pct') ?? 100;
              hits.add(
                StageHit(
                  target: r.i('target')!,
                  amount: r.i('amount'),
                  hpAfter: r.i('hp'),
                  crit: r.i('crit') == 1,
                  effectiveness: pct > 100
                      ? StageEffectiveness.strong
                      : (pct < 100
                            ? StageEffectiveness.weak
                            : StageEffectiveness.normal),
                ),
              );
            case 'miss':
              hits.add(StageHit(target: r.i('target') ?? 1 - side));
            case 'heal':
              outcomes.add(
                StageHealed(r.i('side')!, r.i('amount')!, r.i('hp')!),
              );
            case 'status':
              outcomes.add(
                StageStatus(
                  r.i('target')!,
                  r.s('status') == 'poison'
                      ? StageStatusKind.poison
                      : StageStatusKind.paralyze,
                ),
              );
            case 'stage':
              outcomes.add(
                StageStatChange(r.i('side')!, up: r.i('stage')! > 0),
              );
            case 'shield':
              outcomes.add(StageShieldUp(r.i('side')!));
          }
        }
        out.add(
          StageAction(
            side: side,
            slot: slot,
            move: stageMoveOf(moves(side, slot), special: slot == 3),
            hits: hits,
            outcomes: outcomes,
          ),
        );
      case 'dot':
        out.add(StagePoisonTick(e.i('target')!, e.i('amount')!, e.i('hp')!));
      case 'heatUp':
        out.add(const StageHeatUp());
      case 'end':
        out.add(StageEnd(e.i('winner')!));
      // effective / hit / miss / heal / stage / status / shield are read
      // with their moveStart; expire is mirrored by the fighter state;
      // faint is shown with the K.O. at the end.
    }
  }
  return out;
}

/// Display data of an engine move.
StageMove stageMoveOf(Move m, {bool special = false, bool drawn = false}) =>
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
