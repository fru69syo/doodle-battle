import '../../domain/battle/battle.dart';
import '../../domain/character.dart';

/// One CPU battle (SPEC §4): the player is side a, the CPU side b. Battle
/// and AI use independent rng streams derived from [seed] (docs/BATTLE.md).
class CpuBattleSession {
  CpuBattleSession({
    required this.spec,
    required this.player,
    required this.cpu,
    required this.stage,
    required CpuRoster roster,
    required int seed,
  }) : state = initBattle(
         spec,
         fighterSetupFor(spec, player),
         cpuFighterSetup(spec, stage, roster),
       ),
       _rng = Mulberry32(deriveSeed(seed, 0)),
       _ai = Mulberry32(deriveSeed(seed, 2));

  final BattleSpec spec;
  final Character player;

  /// CPU doodle for display (see `cpuDisplayCharacter`).
  final Character cpu;
  final CpuStage stage;
  final Mulberry32 _rng;
  final Mulberry32 _ai;
  BattleState state;

  bool get isOver => state.isOver;
  bool get playerWon => state.winner == Side.a;
  bool get specialReady => state.a.gauge >= spec.gauge.max;

  /// Resolves one turn with the player's [action]; returns the events to
  /// animate.
  List<BattleEvent> playTurn(BattleAction action) {
    final cpuAction = chooseCpuAction(spec, state, Side.b, stage.aiTier, _ai);
    final r = resolveTurn(spec, state, action, cpuAction, _rng);
    state = r.state;
    return r.events;
  }
}
