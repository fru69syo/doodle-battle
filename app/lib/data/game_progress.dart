/// Game progress that is not part of a character: CPU stages cleared,
/// online results already applied and today's play time.
class GameProgress {
  const GameProgress({
    this.clearedStage = 0,
    this.appliedMatchIds = const [],
    this.playDate,
    this.playSecondsToday = 0,
    this.onlineLevels = const {},
  });

  /// Highest CPU stage won (0 = none). Stage `clearedStage + 1` is playable.
  final int clearedStage;

  /// Online matches whose XP was already applied (dedupe, newest last).
  final List<String> appliedMatchIds;

  /// Local date (yyyy-mm-dd) [playSecondsToday] refers to.
  final String? playDate;
  final int playSecondsToday;

  /// Character id → level of its current online snapshot (re-register when
  /// the character has grown since).
  final Map<String, int> onlineLevels;

  static const int maxAppliedMatchIds = 100;

  GameProgress copyWith({
    int? clearedStage,
    List<String>? appliedMatchIds,
    String? playDate,
    int? playSecondsToday,
    Map<String, int>? onlineLevels,
  }) => GameProgress(
    clearedStage: clearedStage ?? this.clearedStage,
    appliedMatchIds: appliedMatchIds ?? this.appliedMatchIds,
    playDate: playDate ?? this.playDate,
    playSecondsToday: playSecondsToday ?? this.playSecondsToday,
    onlineLevels: onlineLevels ?? this.onlineLevels,
  );

  /// Records [matchId]; keeps only the newest [maxAppliedMatchIds].
  GameProgress withAppliedMatch(String matchId) {
    final ids = [...appliedMatchIds.where((m) => m != matchId), matchId];
    final start = ids.length > maxAppliedMatchIds
        ? ids.length - maxAppliedMatchIds
        : 0;
    return copyWith(appliedMatchIds: ids.sublist(start));
  }

  Map<String, Object?> toJson() => {
    'clearedStage': clearedStage,
    'appliedMatchIds': appliedMatchIds,
    'playDate': playDate,
    'playSecondsToday': playSecondsToday,
    'onlineLevels': onlineLevels,
  };

  factory GameProgress.fromJson(Map<String, Object?> j) => GameProgress(
    clearedStage: j['clearedStage'] as int? ?? 0,
    appliedMatchIds: [
      for (final m in (j['appliedMatchIds'] as List?) ?? const []) m as String,
    ],
    playDate: j['playDate'] as String?,
    playSecondsToday: j['playSecondsToday'] as int? ?? 0,
    onlineLevels: {
      for (final e in ((j['onlineLevels'] as Map?) ?? const {}).entries)
        e.key as String: e.value as int,
    },
  );
}
