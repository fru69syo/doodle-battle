/// Parent settings and consents (SPEC §7), stored on device.
library;

/// Bump when the privacy policy changes; the app then asks the parent to
/// consent again (sent to the server as `consent.policyVersion`).
const int currentPolicyVersion = 1;

/// What the parent allowed behind the parental gate. Everything defaults to
/// off (privacy by default).
class ParentConsents {
  const ParentConsents({
    this.cloudJudge = false,
    this.online = false,
    this.ads = false,
    this.purchases = false,
  });

  /// Send the cut-out drawing to the AI judge (SPEC §3.3).
  final bool cloudJudge;

  /// Online battles (SPEC §5).
  final bool online;

  /// Rewarded ads (「どうがを みて けいけんち 2ばい」).
  final bool ads;

  /// In-app purchases (shop in おうちのひと).
  final bool purchases;

  ParentConsents copyWith({
    bool? cloudJudge,
    bool? online,
    bool? ads,
    bool? purchases,
  }) => ParentConsents(
    cloudJudge: cloudJudge ?? this.cloudJudge,
    online: online ?? this.online,
    ads: ads ?? this.ads,
    purchases: purchases ?? this.purchases,
  );

  Map<String, Object?> toJson() => {
    'cloudJudge': cloudJudge,
    'online': online,
    'ads': ads,
    'purchases': purchases,
  };

  factory ParentConsents.fromJson(Map<String, Object?> j) => ParentConsents(
    cloudJudge: j['cloudJudge'] as bool? ?? false,
    online: j['online'] as bool? ?? false,
    ads: j['ads'] as bool? ?? false,
    purchases: j['purchases'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is ParentConsents &&
      other.cloudJudge == cloudJudge &&
      other.online == online &&
      other.ads == ads &&
      other.purchases == purchases;

  @override
  int get hashCode => Object.hash(cloudJudge, online, ads, purchases);
}

class AppSettings {
  const AppSettings({
    this.setupCompleted = false,
    this.policyVersion = 0,
    this.consents = const ParentConsents(),
    this.playTimeMinutes,
    this.entitlements = const {},
  });

  /// First-run parent setup finished.
  final bool setupCompleted;

  /// Privacy-policy version the parent consented to (0 = never).
  final int policyVersion;
  final ParentConsents consents;

  /// Daily play-time guideline in minutes (null = no guideline).
  final int? playTimeMinutes;

  /// Cached purchase entitlements (product ids) so limits work offline.
  final Set<String> entitlements;

  /// Whether the parent must (re-)run the setup.
  bool get needsSetup =>
      !setupCompleted || policyVersion < currentPolicyVersion;

  AppSettings copyWith({
    bool? setupCompleted,
    int? policyVersion,
    ParentConsents? consents,
    int? Function()? playTimeMinutes,
    Set<String>? entitlements,
  }) => AppSettings(
    setupCompleted: setupCompleted ?? this.setupCompleted,
    policyVersion: policyVersion ?? this.policyVersion,
    consents: consents ?? this.consents,
    playTimeMinutes: playTimeMinutes != null
        ? playTimeMinutes()
        : this.playTimeMinutes,
    entitlements: entitlements ?? this.entitlements,
  );

  Map<String, Object?> toJson() => {
    'setupCompleted': setupCompleted,
    'policyVersion': policyVersion,
    'consents': consents.toJson(),
    'playTimeMinutes': playTimeMinutes,
    'entitlements': entitlements.toList()..sort(),
  };

  factory AppSettings.fromJson(Map<String, Object?> j) => AppSettings(
    setupCompleted: j['setupCompleted'] as bool? ?? false,
    policyVersion: j['policyVersion'] as int? ?? 0,
    consents: ParentConsents.fromJson(
      (j['consents'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
    playTimeMinutes: j['playTimeMinutes'] as int?,
    entitlements: {
      for (final e in (j['entitlements'] as List?) ?? const []) e as String,
    },
  );
}
