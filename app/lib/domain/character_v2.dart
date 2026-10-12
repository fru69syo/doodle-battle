/// A child's drawing as a v2.0 character (spec v3): ten stats, グー/チョキ/パー,
/// levels up to 100, four move slots (2 at Lv1, 3rd at Lv10, 4th at Lv50)
/// and the optional 2.5D rig.
///
/// Only the *inputs* are persisted (quantised features, energy / skill, the
/// image hash, the trust verdict, level, XP, AI move proposals). Stats,
/// attribute, kid-likeness and the hidden late-bloomer state are derived
/// every time with the engine's [Genome] (docs/GAME_DESIGN_V2.md §11: the
/// hidden state is never stored as such, never shown, never sent).
///
/// [CharacterV2.fromJson] also loads v1 characters (`domain/character.dart`
/// JSON) and migrates them; see [CharacterV2.migrateV1].
library;

import 'battle_v3/battle_v3.dart';
import 'cosmetics.dart';
import 'element_type.dart';
import 'rig_blob.dart';

/// How the drawing reached the app (SPEC §3).
enum DrawingSource {
  /// A photo of a drawing on paper.
  photo,

  /// The in-app drawing canvas (never checked for "digital" finish).
  canvas,
}

/// Trust verdicts that do not reject a picture (docs/GAME_DESIGN_V2.md §1):
/// on-device `digital` / `printed` / `screen`, cloud `ai_generated`.
const Set<String> kTrustVerdicts = kBloomerOrigins;

final RegExp _kanaName = RegExp(r'^[ぁ-ゖァ-ヺー]{1,10}$');

/// One move slot as stored: an optional normalised AI proposal (template +
/// parameters + name / flavour / vfx / colour; numbers are re-fitted to the
/// slot budget by the validator every time) and an optional name override
/// (legacy v1 move names). Neither set = the deterministic offline move.
class CharacterMove {
  const CharacterMove({this.proposal, this.name});

  final Map<String, Object?>? proposal;
  final String? name;

  static const empty = CharacterMove();

  bool get isAi => proposal != null;

  Map<String, Object?> toJson() => {
    if (proposal != null) 'proposal': proposal,
    if (name != null) 'name': name,
  };

  factory CharacterMove.fromJson(Object? j) {
    if (j is! Map) return empty;
    final p = j['proposal'];
    final n = j['name'];
    return CharacterMove(
      proposal: p is Map ? p.cast<String, Object?>() : null,
      name: n is String && _kanaName.hasMatch(n) ? n : null,
    );
  }
}

class CharacterV2 {
  const CharacterV2({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.imageHash,
    required this.features,
    required this.energy10,
    required this.skill10,
    required this.createdAt,
    this.source = DrawingSource.photo,
    this.verdict,
    this.level = 1,
    this.xp = 0,
    this.moves = const [],
    this.moveSet = 0,
    this.rig,
    this.legacyElement,
    this.subject,
    this.onlineId,
    this.cardFrame,
    this.cosmetics = CharacterCosmetics.none,
  });

  /// JSON schema version written by [toJson] (v1 files have none).
  static const int schema = 2;

  final String id;
  final String name;

  /// Absolute path to the cut-out PNG on device.
  final String imagePath;

  /// SHA-256 (hex) of the normalised input image: the deterministic seed.
  final String imageHash;
  final FeatureVector features;

  /// のびのび度 / じょうずさ in tenths (0..1000), cloud-blended.
  final int energy10;
  final int skill10;
  final DateTime createdAt;
  final DrawingSource source;

  /// Trust verdict that did not reject the picture ([kTrustVerdicts]), or
  /// null for an ordinary drawing. Internal.
  final String? verdict;
  final int level;

  /// XP towards the next level.
  final int xp;

  /// Index = slot (0..3). Shorter lists mean "offline" for missing slots.
  final List<CharacterMove> moves;

  /// 0 = the birth move set, 1 = the set regenerated at the Lv50 evolution
  /// (internal; AI proposals of set 0 are not used once set 1 is due).
  final int moveSet;

  /// Validated 2.5D rig blob ([validateRigJson]), or null for the auto rig.
  final Map<String, Object?>? rig;

  /// v1 colour element, kept only as a cosmetic hint (effect colours).
  final ElementType? legacyElement;
  final String? subject;

  /// Server snapshot id once registered for online play (v2 snapshot).
  final String? onlineId;
  final String? cardFrame;
  final CharacterCosmetics cosmetics;

  // --- derived ----------------------------------------------------------------

  /// Everything derived from the drawing (INTERNAL fields: see [Genome]).
  Genome genome([V3Spec s = const V3Spec()]) => Genome.derive(
    s,
    features: features,
    energy10: energy10,
    skill10: skill10,
    imageHash: imageHash,
    origin: verdict,
  );

  Attr attribute([V3Spec s = const V3Spec()]) => genome(s).attr;

  /// Stats at the current level (Stat order).
  List<int> stats([V3Spec s = const V3Spec()]) => genome(s).statsAt(level);

  int maxHp([V3Spec s = const V3Spec()]) => maxHpOf(s, stats(s));

  /// Number of unlocked move slots (2 / 3 / 4).
  int unlockedSlotCount([V3Spec s = const V3Spec()]) => unlockedSlots(s, level);

  bool get onlineUnlocked => level >= kRatedUnlockLevel;

  /// Highest evolution reached (`kagayaki` … `oukan`), or null.
  String? get evolution {
    String? e;
    for (final x in kEvolutions.entries) {
      if (level >= x.key) e = x.value;
    }
    return e;
  }

  List<Map<String, Object?>?> _proposals(Genome g) {
    // A pre-rebirth AI set is not used by the regenerated (rebirth) set.
    final stale = g.rebornAt(level) && moveSet == 0;
    return [for (final m in moves) stale ? null : m.proposal];
  }

  List<String?> _names(Genome g) {
    final stale = g.rebornAt(level) && moveSet == 0;
    return [for (final m in moves) stale ? null : m.name];
  }

  /// All four slot moves at the current level (locked ones included; the
  /// first [unlockedSlotCount] are usable). [ngCheck] re-checks AI names.
  List<Move> allMoves({
    V3Spec s = const V3Spec(),
    bool Function(String)? ngCheck,
  }) {
    final g = genome(s);
    return movesAt(
      s,
      g,
      level,
      aiProposals: _proposals(g),
      nameOverrides: _names(g),
      ngCheck: ngCheck,
    );
  }

  /// The battle setup at the current level (single-player, CPU mirror).
  FighterSetup battleSetup({V3Spec s = const V3Spec(), int? atLevel}) {
    final g = genome(s);
    return setupAt(
      s,
      g,
      atLevel ?? level,
      aiProposals: _proposals(g),
      nameOverrides: _names(g),
      label: name,
    );
  }

  /// Rated-play setup (synced to Lv50, see [ratedSetup]).
  FighterSetup ratedBattleSetup({V3Spec s = const V3Spec()}) {
    final g = genome(s);
    return ratedSetup(
      s,
      g,
      actualLevel: level,
      aiProposals: _proposals(g),
      nameOverrides: _names(g),
      label: name,
    );
  }

  /// Family battle at [battleLevel] (handicap).
  FighterSetup familyBattleSetup(int battleLevel, {V3Spec s = const V3Spec()}) {
    final g = genome(s);
    return familySetup(
      s,
      g,
      actualLevel: level,
      battleLevel: battleLevel,
      aiProposals: _proposals(g),
      nameOverrides: _names(g),
      label: name,
    );
  }

  // --- growth -------------------------------------------------------------------

  /// Adds [gained] XP. At the Lv50 evolution a hidden bloomer's move set is
  /// regenerated (its AI proposals and name overrides are dropped; the
  /// offline rebirth set is used until new AI names are requested). The
  /// returned [LevelProgress] reports unlocks and evolutions for the UI;
  /// its `rebirth` flag is internal.
  (CharacterV2, LevelProgress) gainXp(int gained, {V3Spec s = const V3Spec()}) {
    final g = genome(s);
    final p = applyXp(
      s,
      level: level,
      xp: xp,
      gained: gained,
      isBloomer: g.isBloomer,
    );
    var c = copyWith(level: p.level, xp: p.xp);
    if (p.rebirth) c = c.copyWith(moves: const [], moveSet: 1);
    return (c, p);
  }

  /// Replaces the AI proposals of the current move set (e.g. new names for
  /// the regenerated set) with the normalised proposals of
  /// [validateAiMoveSet]; rejected slots keep the offline move.
  CharacterV2 withAiMoves(List<SlotValidation> validated) => copyWith(
    moves: [
      for (var i = 0; i < 4; i++)
        CharacterMove(
          proposal: i < validated.length ? validated[i].proposal : null,
        ),
    ],
  );

  CharacterV2 copyWith({
    String? name,
    String? imageHash,
    int? level,
    int? xp,
    List<CharacterMove>? moves,
    int? moveSet,
    Map<String, Object?>? Function()? rig,
    String? subject,
    String? Function()? onlineId,
    String? Function()? cardFrame,
    CharacterCosmetics? cosmetics,
  }) => CharacterV2(
    id: id,
    name: name ?? this.name,
    imagePath: imagePath,
    imageHash: imageHash ?? this.imageHash,
    features: features,
    energy10: energy10,
    skill10: skill10,
    createdAt: createdAt,
    source: source,
    verdict: verdict,
    level: level ?? this.level,
    xp: xp ?? this.xp,
    moves: moves ?? this.moves,
    moveSet: moveSet ?? this.moveSet,
    rig: rig != null ? validateRigJson(rig()) : this.rig,
    legacyElement: legacyElement,
    subject: subject ?? this.subject,
    onlineId: onlineId != null ? onlineId() : this.onlineId,
    cardFrame: cardFrame != null ? cardFrame() : this.cardFrame,
    cosmetics: cosmetics ?? this.cosmetics,
  );

  // --- creation -----------------------------------------------------------------

  /// A new character from the analyser's output. [rawFeatures] is
  /// `DrawingFeatures.toMap()` (quantised here, once); [energy] / [skill]
  /// are the cloud-blended 0..100 scores (one decimal); [aiMoves] the
  /// validated cloud proposals, if the parent allowed cloud features.
  factory CharacterV2.create({
    required String id,
    required String name,
    required String imagePath,
    required String imageHash,
    required Map<String, num> rawFeatures,
    required double energy,
    required double skill,
    required DateTime createdAt,
    DrawingSource source = DrawingSource.photo,
    String? verdict,
    List<SlotValidation>? aiMoves,
    Map<String, Object?>? rig,
    String? subject,
    ElementType? legacyElement,
  }) {
    final c = CharacterV2(
      id: id,
      name: name,
      imagePath: imagePath,
      imageHash: imageHash,
      features: FeatureVector.quantize(rawFeatures),
      energy10: tenths(energy),
      skill10: tenths(skill),
      createdAt: createdAt,
      source: source,
      // The in-app canvas is never judged "digital" (GAME_DESIGN_V2 §1).
      verdict: source == DrawingSource.canvas
          ? null
          : (kTrustVerdicts.contains(verdict) ? verdict : null),
      rig: validateRigJson(rig),
      subject: subject,
      legacyElement: legacyElement,
    );
    return aiMoves == null ? c : c.withAiMoves(aiMoves);
  }

  /// 0..100 score with one decimal → integer tenths (0..1000).
  static int tenths(num v) => (v * 10).round().clamp(0, 1000);

  // --- JSON --------------------------------------------------------------------

  Map<String, Object?> toJson() => {
    'schema': schema,
    'id': id,
    'name': name,
    'imagePath': imagePath,
    'imageHash': imageHash,
    'source': source.name,
    'features': features.toJson(),
    'energy10': energy10,
    'skill10': skill10,
    if (verdict != null) 'verdict': verdict,
    'createdAt': createdAt.toIso8601String(),
    'level': level,
    'xp': xp,
    'moves': [for (final m in moves) m.toJson()],
    'moveSet': moveSet,
    if (rig != null) 'rig': rig,
    if (legacyElement != null) 'legacyElement': legacyElement!.name,
    'subject': subject,
    'onlineId': onlineId,
    'cardFrame': cardFrame,
    if (!cosmetics.isEmpty) 'cosmetics': cosmetics.toJson(),
  };

  /// Loads a v2 character, or migrates a v1 one ([migrateV1]).
  factory CharacterV2.fromJson(Map<String, Object?> json, {V3Spec? spec}) {
    final s = spec ?? const V3Spec();
    if (json['schema'] != schema) return migrateV1(json, spec: s);
    final verdict = json['verdict'];
    final level = (json['level'] as int? ?? 1).clamp(1, s.maxLevel);
    return CharacterV2(
      id: json['id']! as String,
      name: json['name']! as String,
      imagePath: json['imagePath']! as String,
      imageHash: json['imageHash']! as String,
      source:
          DrawingSource.values.asNameMap()[json['source']] ??
          DrawingSource.photo,
      features:
          FeatureVector.tryParse(json['features']) ?? const FeatureVector({}),
      energy10: (json['energy10'] as int? ?? 0).clamp(0, 1000),
      skill10: (json['skill10'] as int? ?? 0).clamp(0, 1000),
      verdict: kTrustVerdicts.contains(verdict) ? verdict as String : null,
      createdAt: DateTime.parse(json['createdAt']! as String),
      level: level,
      xp: _clampXp(s, level, json['xp'] as int? ?? 0),
      moves: [
        for (final m in (json['moves'] as List? ?? const []).take(4))
          CharacterMove.fromJson(m),
      ],
      moveSet: json['moveSet'] == 1 ? 1 : 0,
      rig: validateRigJson(json['rig']),
      legacyElement: ElementType.values.asNameMap()[json['legacyElement']],
      subject: json['subject'] as String?,
      onlineId: json['onlineId'] as String?,
      cardFrame: json['cardFrame'] as String?,
      cosmetics: CharacterCosmetics.fromJson(json['cosmetics']),
    );
  }

  static int _clampXp(V3Spec s, int level, int xp) {
    if (level >= s.maxLevel || xp < 0) return 0;
    final need = xpToNext(s, level);
    return xp >= need ? need - 1 : xp;
  }

  /// Migrates a v1 character JSON (`Character.toJson()`, no `schema`):
  /// stats and moves are re-derived from the stored analyser features,
  /// energy and skill (v1 Lv1 stats and パワーのたね are dropped — the v2
  /// design abolishes seeds, GAME_DESIGN_V2 §4.3); level and XP are kept
  /// (XP clamped below the next level); the v1 AI move names become name
  /// overrides of slot 1 (element move) and slot 4 (special) when they are
  /// valid kana; the colour element is kept as a cosmetic hint; the v1
  /// online snapshot id is dropped (the character must be registered again
  /// for v2 online play). v1 only accepted paper drawings, so there is no
  /// trust verdict.
  static CharacterV2 migrateV1(Map<String, Object?> json, {V3Spec? spec}) {
    final s = spec ?? const V3Spec();
    final raw = <String, num>{};
    final f = json['features'];
    if (f is Map) {
      for (final e in f.entries) {
        if (e.key is String && e.value is num) raw[e.key as String] = e.value;
      }
    }
    String? kana(Object? v) => v is String && _kanaName.hasMatch(v) ? v : null;
    final elementMove = kana(json['elementMoveName']);
    final specialMove = kana(json['specialMoveName']);
    final level = (json['level'] as int? ?? 1).clamp(1, s.maxLevel);
    final energy = json['energy'];
    final skill = json['skill'];
    return CharacterV2(
      id: json['id']! as String,
      name: json['name']! as String,
      imagePath: json['imagePath']! as String,
      imageHash: json['imageHash']! as String,
      features: raw.isEmpty
          ? const FeatureVector({})
          : FeatureVector.quantize(raw),
      energy10: energy is num ? tenths(energy) : 500,
      skill10: skill is num ? tenths(skill) : 200,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      level: level,
      xp: _clampXp(s, level, json['xp'] as int? ?? 0),
      moves: [
        CharacterMove(name: elementMove),
        CharacterMove.empty,
        CharacterMove.empty,
        CharacterMove(name: specialMove),
      ],
      legacyElement: ElementType.values.asNameMap()[json['element']],
      subject: json['subject'] as String?,
      cardFrame: json['cardFrame'] as String?,
      cosmetics: CharacterCosmetics.fromJson(json['cosmetics']),
    );
  }
}
