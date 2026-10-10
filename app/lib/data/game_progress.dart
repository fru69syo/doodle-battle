/// Game progress that is not part of a character: CPU stages cleared,
/// online results already applied, today's play time, today's ad boosts and
/// the chosen online display name.
class GameProgress {
  const GameProgress({
    this.clearedStage = 0,
    this.appliedMatchIds = const [],
    this.playDate,
    this.playSecondsToday = 0,
    this.onlineLevels = const {},
    this.adBoostDate,
    this.adBoostsToday = 0,
    this.displayName,
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

  /// Local date (yyyy-mm-dd) [adBoostsToday] refers to.
  final String? adBoostDate;

  /// Post-battle XP ×2 bonuses used on [adBoostDate], by rewarded ad or
  /// with こうこくなしパス (one shared daily cap, `dailyAdBoostCap`).
  final int adBoostsToday;

  /// Online display name last confirmed by the server (`setDisplayName` or
  /// registration), or null.
  final ChosenDisplayName? displayName;

  static const int maxAppliedMatchIds = 100;

  /// Ad boosts already used on the local [date] (yyyy-mm-dd).
  int adBoostsOn(String date) => adBoostDate == date ? adBoostsToday : 0;

  /// Records one ad boost on [date].
  GameProgress withAdBoost(String date) =>
      copyWith(adBoostDate: date, adBoostsToday: adBoostsOn(date) + 1);

  GameProgress copyWith({
    int? clearedStage,
    List<String>? appliedMatchIds,
    String? playDate,
    int? playSecondsToday,
    Map<String, int>? onlineLevels,
    String? adBoostDate,
    int? adBoostsToday,
    ChosenDisplayName? displayName,
  }) => GameProgress(
    clearedStage: clearedStage ?? this.clearedStage,
    appliedMatchIds: appliedMatchIds ?? this.appliedMatchIds,
    playDate: playDate ?? this.playDate,
    playSecondsToday: playSecondsToday ?? this.playSecondsToday,
    onlineLevels: onlineLevels ?? this.onlineLevels,
    adBoostDate: adBoostDate ?? this.adBoostDate,
    adBoostsToday: adBoostsToday ?? this.adBoostsToday,
    displayName: displayName ?? this.displayName,
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
    'adBoostDate': adBoostDate,
    'adBoostsToday': adBoostsToday,
    'displayName': displayName?.toJson(),
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
    adBoostDate: j['adBoostDate'] as String?,
    adBoostsToday: j['adBoostsToday'] as int? ?? 0,
    displayName: j['displayName'] is Map
        ? ChosenDisplayName.fromJson(
            (j['displayName']! as Map).cast<String, Object?>(),
          )
        : null,
  );
}

/// An online display name made of preset word ids (docs/BACKEND.md §5).
class ChosenDisplayName {
  const ChosenDisplayName({
    required this.adjectiveId,
    required this.nounId,
    required this.text,
  });

  final String adjectiveId;
  final String nounId;

  /// As composed by the server, e.g. 「あおい ドラゴン」.
  final String text;

  Map<String, Object?> toJson() => {
    'adjectiveId': adjectiveId,
    'nounId': nounId,
    'text': text,
  };

  factory ChosenDisplayName.fromJson(Map<String, Object?> j) =>
      ChosenDisplayName(
        adjectiveId: j['adjectiveId'] as String? ?? '',
        nounId: j['nounId'] as String? ?? '',
        text: j['text'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is ChosenDisplayName &&
      other.adjectiveId == adjectiveId &&
      other.nounId == nounId &&
      other.text == text;

  @override
  int get hashCode => Object.hash(adjectiveId, nounId, text);
}
