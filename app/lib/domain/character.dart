import 'element_type.dart';
import 'stats.dart';

/// Evolution stage reached by levelling (SPEC §4.2).
enum EvolutionStage { normal, kagayaki, densetsu }

/// A child's drawing turned into a character, as persisted locally.
class Character {
  const Character({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.imageHash,
    required this.element,
    required this.baseStats,
    required this.energy,
    required this.skill,
    required this.features,
    required this.createdAt,
    this.level = 1,
    this.xp = 0,
    this.seedAllocations = const {},
    this.subject,
    this.elementMoveName,
    this.specialMoveName,
    this.onlineId,
  });

  final String id;
  final String name;

  /// Absolute path to the cut-out PNG on device.
  final String imagePath;
  final String imageHash;
  final ElementType element;

  /// Level-1 stats from analysis; current stats are derived by the growth
  /// rules in `domain/battle`.
  final Stats baseStats;
  final double energy;
  final double skill;
  final Map<String, num> features;
  final DateTime createdAt;

  final int level;

  /// XP accumulated towards the next level.
  final int xp;

  /// Number of パワーのたね spent per stat.
  final Map<StatKind, int> seedAllocations;

  /// What the drawing depicts, e.g. "ねこ" (cloud judge only).
  final String? subject;
  final String? elementMoveName;
  final String? specialMoveName;

  /// Server id once registered for online play (passed moderation).
  final String? onlineId;

  bool get isShobo => skill > 75;

  EvolutionStage get stage => level >= 20
      ? EvolutionStage.densetsu
      : level >= 10
      ? EvolutionStage.kagayaki
      : EvolutionStage.normal;

  bool get onlineUnlocked => level >= 5;

  Character copyWith({
    String? name,
    int? level,
    int? xp,
    Map<StatKind, int>? seedAllocations,
    String? subject,
    String? elementMoveName,
    String? specialMoveName,
    String? onlineId,
  }) => Character(
    id: id,
    name: name ?? this.name,
    imagePath: imagePath,
    imageHash: imageHash,
    element: element,
    baseStats: baseStats,
    energy: energy,
    skill: skill,
    features: features,
    createdAt: createdAt,
    level: level ?? this.level,
    xp: xp ?? this.xp,
    seedAllocations: seedAllocations ?? this.seedAllocations,
    subject: subject ?? this.subject,
    elementMoveName: elementMoveName ?? this.elementMoveName,
    specialMoveName: specialMoveName ?? this.specialMoveName,
    onlineId: onlineId ?? this.onlineId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'imagePath': imagePath,
    'imageHash': imageHash,
    'element': element.name,
    'baseStats': baseStats.toJson(),
    'energy': energy,
    'skill': skill,
    'features': features,
    'createdAt': createdAt.toIso8601String(),
    'level': level,
    'xp': xp,
    'seedAllocations': {
      for (final e in seedAllocations.entries) e.key.name: e.value,
    },
    'subject': subject,
    'elementMoveName': elementMoveName,
    'specialMoveName': specialMoveName,
    'onlineId': onlineId,
  };

  factory Character.fromJson(Map<String, Object?> json) => Character(
    id: json['id']! as String,
    name: json['name']! as String,
    imagePath: json['imagePath']! as String,
    imageHash: json['imageHash']! as String,
    element: ElementType.fromName(json['element']! as String),
    baseStats: Stats.fromJson(
      (json['baseStats']! as Map).cast<String, Object?>(),
    ),
    energy: (json['energy']! as num).toDouble(),
    skill: (json['skill']! as num).toDouble(),
    features: (json['features']! as Map).cast<String, num>(),
    createdAt: DateTime.parse(json['createdAt']! as String),
    level: json['level']! as int,
    xp: json['xp']! as int,
    seedAllocations: {
      for (final e in (json['seedAllocations']! as Map).entries)
        StatKind.values.byName(e.key as String): e.value as int,
    },
    subject: json['subject'] as String?,
    elementMoveName: json['elementMoveName'] as String?,
    specialMoveName: json['specialMoveName'] as String?,
    onlineId: json['onlineId'] as String?,
  );
}
