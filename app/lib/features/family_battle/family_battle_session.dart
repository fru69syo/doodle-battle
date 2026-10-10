import '../../domain/battle/battle.dart';
import 'family_setup.dart';

/// One hot-seat battle: both sides are people on the same device. Side a
/// picks first, then side b, then the turn resolves with the shared engine.
/// No AI, no timer, no server. Battle rng = `deriveSeed(seed, 0)` like every
/// other battle (docs/BATTLE.md §2).
class FamilyBattleSession {
  FamilyBattleSession({
    required this.spec,
    required this.config,
    required int seed,
  }) : state = initBattle(
         spec,
         config.setup(spec, Side.a),
         config.setup(spec, Side.b),
       ),
       _rng = Mulberry32(deriveSeed(seed, 0));

  final BattleSpec spec;
  final FamilyBattleConfig config;
  final Mulberry32 _rng;
  BattleState state;

  /// Side a's secret choice for the current turn (null until it picked).
  BattleAction? _pendingA;

  bool get isOver => state.isOver;
  Side? get winner => state.winner;

  /// Whose pick is next.
  Side get picker => _pendingA == null ? Side.a : Side.b;

  bool specialReady(Side side) => state.fighter(side).gauge >= spec.gauge.max;

  /// Records a pick. Returns the turn's events once both sides have picked
  /// (the turn is resolved), otherwise null.
  List<BattleEvent>? pick(BattleAction action) {
    if (isOver) throw StateError('battle is over');
    final a = _pendingA;
    if (a == null) {
      _pendingA = action;
      return null;
    }
    _pendingA = null;
    final r = resolveTurn(spec, state, a, action, _rng);
    state = r.state;
    return r.events;
  }
}
