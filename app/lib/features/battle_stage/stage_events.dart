/// The small, engine-agnostic vocabulary the 2.5D stage understands. An
/// adapter turns an engine's event stream (the v3 ATB engine on the phone,
/// or the server's events online) into these; the stage never reads engine
/// state directly, so engine changes only touch the adapter.
library;

/// How a move is staged.
enum StageMoveKind {
  /// Dash to the target and hit it (punch, kick, tackle...).
  physical,

  /// Shoot something at the target (beam, orb, bubbles...).
  ranged,

  /// On oneself (heal, power-up, shield).
  self,
}

/// Attribute matchup of a hit, shown as a short text.
enum StageEffectiveness { normal, strong, weak }

/// Display data of a move (no numbers).
class StageMove {
  const StageMove({
    required this.name,
    required this.kind,
    this.vfx = 'punch',
    this.colour = 'yellow',
    this.hits = 1,
    this.special = false,
    this.drawnEffect = false,
  });

  final String name;
  final StageMoveKind kind;

  /// One of the 15 `vfx` names (GAME_DESIGN_V2 §5.5): slash, punch, beam,
  /// orb, burst, wave, rain, spiral, stars, hearts, bubbles, leaves,
  /// sparks, shield, glow. Unknown names fall back to a generic burst.
  final String vfx;

  /// One of the 11 colours: red, orange, yellow, green, cyan, blue, purple,
  /// pink, black, white, rainbow.
  final String colour;
  final int hits;

  /// ひっさつ (the 4th move): bigger effects.
  final bool special;

  /// The child drew this move's effect (ぞくせいわざ / ひっさつ, docs/LOOP.md):
  /// the stage flies their drawing instead of the generic effect.
  final bool drawnEffect;
}

/// What happened, in order.
sealed class StageEvent {
  const StageEvent();
}

/// [side]'s gauge is full (the player may choose).
class StageReady extends StageEvent {
  const StageReady(this.side);
  final int side;
}

/// [side] picked a move; [castSeconds] > 0 means it charges first.
class StageChoose extends StageEvent {
  const StageChoose(this.side, {this.castSeconds = 0, this.auto = false});
  final int side;
  final double castSeconds;

  /// Picked by おまかせ / the 5 s timeout.
  final bool auto;
}

/// One hit of an action (or a miss when [amount] is null).
class StageHit {
  const StageHit({
    required this.target,
    this.amount,
    this.hpAfter,
    this.crit = false,
    this.effectiveness = StageEffectiveness.normal,
  });
  final int target;
  final int? amount;
  final int? hpAfter;
  final bool crit;
  final StageEffectiveness effectiveness;
  bool get missed => amount == null;
}

/// A side effect of an action.
sealed class StageOutcome {
  const StageOutcome();
}

class StageHealed extends StageOutcome {
  const StageHealed(this.side, this.amount, this.hpAfter);
  final int side, amount, hpAfter;
}

class StageStatus extends StageOutcome {
  const StageStatus(this.target, this.status);
  final int target;
  final StageStatusKind status;
}

class StageStatChange extends StageOutcome {
  const StageStatChange(this.side, {required this.up});
  final int side;
  final bool up;
}

class StageShieldUp extends StageOutcome {
  const StageShieldUp(this.side);
  final int side;
}

/// [side] uses [move]: the stage plays the whole choreography and shows
/// [hits] and [outcomes] at the moment of impact.
class StageAction extends StageEvent {
  const StageAction({
    required this.side,
    required this.slot,
    required this.move,
    this.hits = const [],
    this.outcomes = const [],
  });
  final int side, slot;
  final StageMove move;
  final List<StageHit> hits;
  final List<StageOutcome> outcomes;
}

/// Damage over time (ねばねば), shown at once.
class StagePoisonTick extends StageEvent {
  const StagePoisonTick(this.target, this.amount, this.hpAfter);
  final int target, amount, hpAfter;
}

/// The damage ramp starts (ヒートアップ): a short banner.
class StageHeatUp extends StageEvent {
  const StageHeatUp();
}

/// The battle is decided (shown after the last action has played).
class StageEnd extends StageEvent {
  const StageEnd(this.winner);
  final int winner;
}

enum StageStatusKind { poison, paralyze }

/// Per-frame state of a fighter for the overlay and status visuals.
class StageFighterState {
  const StageFighterState({
    required this.maxHp,
    this.gauge = 0,
    this.ready = false,
    this.casting = false,
    this.poisoned = false,
    this.paralyzed = false,
    this.shield = 0,
    this.statUp = false,
    this.statDown = false,
    this.sp = 0,
  });

  final int maxHp;

  /// 0..1.
  final double gauge;
  final bool ready, casting;
  final bool poisoned, paralyzed;

  /// 0..1 damage reduction while a shield is up.
  final double shield;
  final bool statUp, statDown;

  /// 0..100.
  final int sp;
}

/// The adapter interface between an engine and the stage.
abstract interface class StageFeed {
  /// Advances the source by [dt] seconds (a local engine steps its ticks;
  /// an online feed releases buffered server events) and returns what
  /// happened since the last call, in order.
  List<StageEvent> advance(double dt);

  /// Current state of fighter [side] (0 = player, 1 = opponent).
  StageFighterState fighter(int side);
}
