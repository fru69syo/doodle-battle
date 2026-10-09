/// Small enums shared by the battle engine (names are the JSON wire format).
library;

/// The two fighters. In CPU battles the player is [a]; online, [a] is the
/// first player of the match document.
enum Side {
  a,
  b;

  Side get other => this == Side.a ? Side.b : Side.a;
}

/// What a player chose for a turn.
///
/// [timeout] is input-only: the engine resolves it as `spec.timeoutAction`
/// (たいあたり) and emits a [TimeoutEvent]. A [special] chosen without a full
/// gauge is resolved as [tackle] (a `SpecialNotReadyEvent` is emitted).
enum BattleAction {
  /// たいあたり
  tackle,

  /// ぞくせいわざ
  element,

  /// まもる
  guard,

  /// ひっさつ
  special,

  /// The turn timer ran out (input only).
  timeout;

  bool get isAttack => this == tackle || this == element || this == special;
}

/// CPU strength: よわい / ふつう / つよい.
enum AiTier { weak, normal, strong }

/// Why a battle ended.
enum EndReason { ko, turnCap }
