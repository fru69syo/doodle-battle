/// Server cost mode (`config/costMode`, shared/cost_mode/cost_mode.json,
/// SPEC §12.7). The kill switch lowers it when the monthly budget runs out;
/// the app silently adapts. Children never see anything about it.
library;

enum CostMode {
  normal(cloudJudge: true, cloudMoveGen: true, pvp: true, ghostAfterSec: 20),
  saving(cloudJudge: false, cloudMoveGen: false, pvp: true, ghostAfterSec: 8),
  minimal(cloudJudge: false, cloudMoveGen: false, pvp: false, ghostAfterSec: 3);

  const CostMode({
    required this.cloudJudge,
    required this.cloudMoveGen,
    required this.pvp,
    required this.ghostAfterSec,
  });

  /// Cloud drawing judgement (judgeDrawing) may be called.
  final bool cloudJudge;

  /// AI move proposals may be requested (judgeDrawing `v2`).
  final bool cloudMoveGen;

  /// Player-vs-player matchmaking (otherwise ghosts only; server-side).
  final bool pvp;

  /// Seconds in the queue before a ghost opponent (server-side).
  final int ghostAfterSec;

  /// The document's `mode` field; unknown values fall back to [normal]
  /// (the `default` of cost_mode.json).
  static CostMode parse(Object? mode) =>
      values.asNameMap()[mode] ?? CostMode.normal;
}
