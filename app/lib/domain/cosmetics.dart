/// Local-only cosmetics the child adds by drawing again (SPEC §11.2-3,
/// docs/LOOP.md): parts drawn on paper and placed on the character, drawn
/// move effects, and the badge of the daily theme (きょうの おだい).
///
/// None of this affects stats, and none of it is sent to the server: online
/// snapshots keep using only the base drawing.
library;

import 'dart:math' as math;

/// What kind of part the child drew (picked after capture).
enum PartType {
  hat,
  wings,
  horn,
  tail,
  weapon,
  accessory;

  static PartType fromName(String? name) => PartType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => PartType.accessory,
  );
}

/// Where a part sits on the base drawing.
///
/// Coordinates are relative to the base drawing so they survive any
/// resampling: ([cx], [cy]) is the part's centre as a fraction of the base
/// width / height (0..1 is inside the base; parts may stick out), [scale] is
/// the part's longest side as a fraction of the base's longest side,
/// [rotation] is clockwise in radians, and [behind] draws the part under the
/// base drawing (wings, tails).
class PartTransform {
  const PartTransform({
    required this.cx,
    required this.cy,
    required this.scale,
    this.rotation = 0,
    this.behind = false,
  });

  final double cx;
  final double cy;
  final double scale;
  final double rotation;
  final bool behind;

  static const double minScale = 0.12;
  static const double maxScale = 1.6;

  /// How far a part's centre may move outside the base (fraction).
  static const double maxOverhang = 0.6;

  /// Clamps to the editable range and normalises the angle to (-π, π].
  PartTransform clamped() {
    var r = rotation % (2 * math.pi);
    if (r > math.pi) r -= 2 * math.pi;
    return PartTransform(
      cx: cx.clamp(-maxOverhang, 1 + maxOverhang).toDouble(),
      cy: cy.clamp(-maxOverhang, 1 + maxOverhang).toDouble(),
      scale: scale.clamp(minScale, maxScale).toDouble(),
      rotation: r,
      behind: behind,
    );
  }

  PartTransform copyWith({
    double? cx,
    double? cy,
    double? scale,
    double? rotation,
    bool? behind,
  }) => PartTransform(
    cx: cx ?? this.cx,
    cy: cy ?? this.cy,
    scale: scale ?? this.scale,
    rotation: rotation ?? this.rotation,
    behind: behind ?? this.behind,
  );

  Map<String, Object?> toJson() => {
    'cx': cx,
    'cy': cy,
    'scale': scale,
    'rotation': rotation,
    'behind': behind,
  };

  factory PartTransform.fromJson(Map<String, Object?> j) => PartTransform(
    cx: (j['cx'] as num?)?.toDouble() ?? 0.5,
    cy: (j['cy'] as num?)?.toDouble() ?? 0.5,
    scale: (j['scale'] as num?)?.toDouble() ?? 0.4,
    rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
    behind: j['behind'] as bool? ?? false,
  ).clamped();

  @override
  bool operator ==(Object other) =>
      other is PartTransform &&
      other.cx == cx &&
      other.cy == cy &&
      other.scale == scale &&
      other.rotation == rotation &&
      other.behind == behind;

  @override
  int get hashCode => Object.hash(cx, cy, scale, rotation, behind);
}

/// One drawn part. Its cut-out PNG is stored next to the character as the
/// asset [assetName] (see `DrawingLoopStorage`).
class CharacterPart {
  const CharacterPart({
    required this.id,
    required this.type,
    required this.transform,
  });

  /// `[A-Za-z0-9_-]`, unique within the character.
  final String id;
  final PartType type;
  final PartTransform transform;

  String get assetName => 'part_$id';

  CharacterPart copyWith({PartType? type, PartTransform? transform}) =>
      CharacterPart(
        id: id,
        type: type ?? this.type,
        transform: transform ?? this.transform,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'transform': transform.toJson(),
  };

  factory CharacterPart.fromJson(Map<String, Object?> j) => CharacterPart(
    id: j['id']! as String,
    type: PartType.fromName(j['type'] as String?),
    transform: PartTransform.fromJson(
      (j['transform'] as Map?)?.cast<String, Object?>() ?? const {},
    ),
  );
}

/// Moves whose effect can be drawn (ぞくせいわざ and ひっさつ).
enum DrawnMove { element, special }

/// The daily theme a character was drawn for (cosmetic badge).
class OdaiBadge {
  const OdaiBadge({
    required this.themeId,
    required this.date,
    required this.text,
  });

  final String themeId;

  /// Local date, yyyy-mm-dd.
  final String date;

  /// The prompt as shown that day (kept so the badge never changes later).
  final String text;

  Map<String, Object?> toJson() => {
    'themeId': themeId,
    'date': date,
    'text': text,
  };

  factory OdaiBadge.fromJson(Map<String, Object?> j) => OdaiBadge(
    themeId: j['themeId']! as String,
    date: j['date']! as String,
    text: j['text'] as String? ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is OdaiBadge &&
      other.themeId == themeId &&
      other.date == date &&
      other.text == text;

  @override
  int get hashCode => Object.hash(themeId, date, text);
}

/// All drawing-loop cosmetics of one character.
class CharacterCosmetics {
  const CharacterCosmetics({
    this.parts = const [],
    this.effects = const {},
    this.odai,
  });

  static const none = CharacterCosmetics();

  /// Maximum number of parts (slots unlock by level, see [partSlotsFor]).
  static const int maxParts = 3;

  /// Drawn parts, in drawing order (later parts are on top of earlier ones
  /// within the same layer).
  final List<CharacterPart> parts;

  /// Drawn move effect → asset name of its cut-out PNG.
  final Map<DrawnMove, String> effects;

  final OdaiBadge? odai;

  bool get isEmpty => parts.isEmpty && effects.isEmpty && odai == null;

  CharacterCosmetics copyWith({
    List<CharacterPart>? parts,
    Map<DrawnMove, String>? effects,
    OdaiBadge? Function()? odai,
  }) => CharacterCosmetics(
    parts: parts ?? this.parts,
    effects: effects ?? this.effects,
    odai: odai != null ? odai() : this.odai,
  );

  Map<String, Object?> toJson() => {
    if (parts.isNotEmpty) 'parts': [for (final p in parts) p.toJson()],
    if (effects.isNotEmpty)
      'effects': {for (final e in effects.entries) e.key.name: e.value},
    if (odai != null) 'odai': odai!.toJson(),
  };

  /// Lenient: anything unreadable is dropped rather than failing the whole
  /// character (a broken cosmetic must never lose the child's character).
  factory CharacterCosmetics.fromJson(Object? json) {
    if (json is! Map) return none;
    final parts = <CharacterPart>[];
    final rawParts = json['parts'];
    if (rawParts is List) {
      for (final p in rawParts) {
        try {
          if (p is Map) parts.add(CharacterPart.fromJson(p.cast()));
        } on Object {
          // skip
        }
      }
    }
    final effects = <DrawnMove, String>{};
    final rawEffects = json['effects'];
    if (rawEffects is Map) {
      for (final e in rawEffects.entries) {
        final move = DrawnMove.values.where((m) => m.name == e.key).firstOrNull;
        if (move != null && e.value is String) effects[move] = e.value;
      }
    }
    OdaiBadge? odai;
    try {
      final o = json['odai'];
      if (o is Map) odai = OdaiBadge.fromJson(o.cast());
    } on Object {
      odai = null;
    }
    return CharacterCosmetics(
      parts: parts.take(maxParts).toList(),
      effects: effects,
      odai: odai,
    );
  }
}

/// Part slots unlocked at [level]: Lv5 → 1, Lv10 → 2, Lv20 → 3.
int partSlotsFor(int level) => level >= 20
    ? 3
    : level >= 10
    ? 2
    : level >= 5
    ? 1
    : 0;

/// Level at which slot number [slot] (1-based) unlocks.
int partSlotUnlockLevel(int slot) => switch (slot) {
  1 => 5,
  2 => 10,
  _ => 20,
};
