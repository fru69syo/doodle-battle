/// Request/response models of the Cloud Functions contracts in
/// docs/BACKEND.md §5. Plain Dart, no Firebase imports.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../domain/battle/battle.dart';
import '../../domain/character.dart';
import '../../domain/element_type.dart';
import '../../domain/stats.dart';

/// Error codes (`HttpsError.details.code`, docs/BACKEND.md §6) plus two
/// client-side codes: [unavailable] (Firebase not configured / feature off)
/// and [network] (offline, timeout, unknown failure).
abstract final class BackendCodes {
  static const unavailable = 'CLIENT_UNAVAILABLE';
  static const network = 'CLIENT_NETWORK';
  static const unauthenticated = 'UNAUTHENTICATED';
  static const consentRequired = 'CONSENT_REQUIRED';
  static const invalidArgument = 'INVALID_ARGUMENT';
  static const imageInvalid = 'IMAGE_INVALID';
  static const imageTooLarge = 'IMAGE_TOO_LARGE';
  static const rateLimited = 'RATE_LIMITED';
  static const aiUnavailable = 'AI_UNAVAILABLE';
  static const notFound = 'NOT_FOUND';
  static const notOwner = 'NOT_OWNER';
  static const snapshotNotActive = 'SNAPSHOT_NOT_ACTIVE';
  static const notInMatch = 'NOT_IN_MATCH';
  static const matchNotActive = 'MATCH_NOT_ACTIVE';
  static const wrongTurn = 'WRONG_TURN';
  static const illegalAction = 'ILLEGAL_ACTION';
  static const cannotReportSelf = 'CANNOT_REPORT_SELF';
  static const notSeenInMatch = 'NOT_SEEN_IN_MATCH';
  static const confirmationRequired = 'CONFIRMATION_REQUIRED';
  static const noOpponent = 'NO_OPPONENT';
  static const internal = 'INTERNAL';
}

class BackendException implements Exception {
  const BackendException(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() =>
      'BackendException($code${message == null ? '' : ': $message'})';
}

/// `judgeDrawing` response (SPEC §3.3).
class CloudJudgement {
  const CloudJudgement({
    required this.subject,
    required this.suggestedNames,
    required this.elementMoveName,
    required this.specialMoveName,
    required this.skillEstimate,
    required this.appropriate,
    this.reasons = const [],
  });

  final String? subject;
  final List<String> suggestedNames;
  final String? elementMoveName;
  final String? specialMoveName;
  final int skillEstimate;
  final bool appropriate;
  final List<String> reasons;

  factory CloudJudgement.fromJson(Map<String, Object?> j) {
    final moves = (j['moveNames'] as Map?)?.cast<String, Object?>() ?? {};
    return CloudJudgement(
      subject: j['subject'] as String?,
      suggestedNames: [
        for (final n in (j['suggestedNames'] as List?) ?? const []) n as String,
      ],
      elementMoveName: moves['element'] as String?,
      specialMoveName: moves['special'] as String?,
      skillEstimate: ((j['skillEstimate'] as num?) ?? 50).round().clamp(0, 100),
      appropriate: j['appropriate'] as bool? ?? false,
      reasons: [
        for (final r in (j['reasons'] as List?) ?? const []) r as String,
      ],
    );
  }
}

/// `registerCharacter` request.
class RegisterCharacterRequest {
  const RegisterCharacterRequest({required this.character, required this.png});

  final Character character;

  /// Cut-out PNG (≤ 512 px).
  final Uint8List png;

  Map<String, Object?> toJson() {
    final c = character;
    return {
      'localCharacterId': c.id,
      'imageBase64': base64Encode(png),
      'name': c.name,
      'element': c.element.name,
      'baseStats': c.baseStats.toJson(),
      'energy': c.energy,
      'skill': c.skill,
      'level': c.level,
      'xp': c.xp,
      'seedAllocations': {
        for (final e in c.seedAllocations.entries)
          if (e.value > 0) e.key.name: e.value,
      },
      'features': c.features,
      'subject': ?c.subject,
      if (c.elementMoveName != null || c.specialMoveName != null)
        'moveNames': {
          'element': ?c.elementMoveName,
          'special': ?c.specialMoveName,
        },
    };
  }
}

sealed class RegisterOutcome {
  const RegisterOutcome();

  factory RegisterOutcome.fromJson(Map<String, Object?> j) {
    if (j['ok'] == true) {
      final moves = (j['moveNames'] as Map?)?.cast<String, Object?>() ?? {};
      return RegisterAccepted(
        snapshotId: j['snapshotId']! as String,
        name: j['name']! as String,
        elementMoveName: moves['element'] as String?,
        specialMoveName: moves['special'] as String?,
        displayName: j['displayName'] as String?,
      );
    }
    return RegisterRejected(
      reason: j['reason'] as String? ?? 'IMAGE_OTHER',
      presetNames: [
        for (final n in (j['presetNames'] as List?) ?? const []) n as String,
      ],
    );
  }
}

class RegisterAccepted extends RegisterOutcome {
  const RegisterAccepted({
    required this.snapshotId,
    required this.name,
    this.elementMoveName,
    this.specialMoveName,
    this.displayName,
  });
  final String snapshotId;
  final String name;
  final String? elementMoveName;
  final String? specialMoveName;
  final String? displayName;
}

class RegisterRejected extends RegisterOutcome {
  const RegisterRejected({required this.reason, this.presetNames = const []});

  /// One of the rejection reasons in docs/BACKEND.md §6.
  final String reason;

  /// Safe names to pick instead (only for NAME_* reasons).
  final List<String> presetNames;

  bool get isNameProblem => reason.startsWith('NAME_');
}

enum QueueState { waiting, matched, left }

class QueueStatus {
  const QueueStatus(this.state, {this.matchId, this.waitedMs = 0});
  final QueueState state;
  final String? matchId;
  final int waitedMs;

  factory QueueStatus.fromJson(Map<String, Object?> j) => QueueStatus(
    QueueState.values.byName(j['status']! as String),
    matchId: j['matchId'] as String?,
    waitedMs: (j['waitedMs'] as num?)?.toInt() ?? 0,
  );
}

/// What a player sees about one side of an online match (`SideInfo`).
class OnlineFighter {
  const OnlineFighter({
    required this.isGhost,
    required this.snapshotId,
    required this.characterName,
    required this.element,
    required this.level,
    required this.isShobo,
    required this.stats,
    this.uid,
    this.displayName,
    this.evolution = EvolutionStage.normal,
    this.imagePath,
    this.elementMoveName,
    this.specialMoveName,
  });

  final String? uid;
  final bool isGhost;
  final String snapshotId;
  final String? displayName;
  final String characterName;
  final ElementType element;
  final int level;
  final bool isShobo;
  final EvolutionStage evolution;
  final Stats stats;

  /// Storage path of the snapshot image.
  final String? imagePath;
  final String? elementMoveName;
  final String? specialMoveName;

  factory OnlineFighter.fromJson(Map<String, Object?> j) {
    final moves = (j['moveNames'] as Map?)?.cast<String, Object?>() ?? {};
    final dn = j['displayName'];
    return OnlineFighter(
      uid: j['uid'] as String?,
      isGhost: j['isGhost'] as bool? ?? false,
      snapshotId: j['snapshotId']! as String,
      displayName: dn is Map ? dn['text'] as String? : dn as String?,
      characterName: j['characterName'] as String? ?? '？',
      element: ElementType.fromName(j['element']! as String),
      level: (j['level']! as num).toInt(),
      isShobo: j['isShobo'] as bool? ?? false,
      evolution:
          EvolutionStage.values.asNameMap()[j['evolution']] ??
          EvolutionStage.normal,
      stats: Stats.fromJson((j['stats']! as Map).cast<String, Object?>()),
      imagePath: j['imagePath'] as String?,
      elementMoveName: moves['element'] as String?,
      specialMoveName: moves['special'] as String?,
    );
  }
}

/// Public per-side battle numbers (`view.a` / `view.b`).
class FighterView {
  const FighterView({
    required this.hp,
    required this.maxHp,
    required this.gauge,
  });
  final int hp;
  final int maxHp;
  final int gauge;

  factory FighterView.fromJson(Map<String, Object?> j) => FighterView(
    hp: (j['hp']! as num).toInt(),
    maxHp: (j['maxHp']! as num).toInt(),
    gauge: (j['gauge'] as num?)?.toInt() ?? 0,
  );
}

class MatchSideResult {
  const MatchSideResult({
    required this.xp,
    required this.outcome,
    this.ratingDelta = 0,
  });
  final int xp;

  /// win | lose | draw
  final String outcome;
  final int ratingDelta;

  factory MatchSideResult.fromJson(Map<String, Object?> j) => MatchSideResult(
    xp: (j['xp'] as num?)?.toInt() ?? 0,
    outcome: j['outcome'] as String? ?? 'draw',
    ratingDelta: (j['ratingDelta'] as num?)?.toInt() ?? 0,
  );
}

enum MatchStatus { active, finished, aborted }

/// `matches/{id}` as seen by one player.
class MatchSnapshot {
  const MatchSnapshot({
    required this.id,
    required this.status,
    required this.turn,
    required this.mySide,
    required this.sides,
    required this.view,
    this.submitted = const {},
    this.turnDeadlineMs,
    this.winner,
    this.endReason,
    this.result = const {},
  });

  final String id;
  final MatchStatus status;

  /// Turn waiting for actions (1-based). The log of turn n is in turns/{n}.
  final int turn;
  final Side mySide;
  final Map<Side, OnlineFighter> sides;
  final Map<Side, FighterView> view;
  final Map<Side, bool> submitted;
  final int? turnDeadlineMs;

  /// 'a' | 'b' | 'draw' | null.
  final String? winner;
  final String? endReason;
  final Map<Side, MatchSideResult> result;

  OnlineFighter get me => sides[mySide]!;
  OnlineFighter get opponent => sides[mySide.other]!;
  bool get isOver => status != MatchStatus.active;

  /// Parses a match document; [myUid] decides which side is ours.
  factory MatchSnapshot.fromJson(
    String id,
    Map<String, Object?> j, {
    required String? myUid,
  }) {
    Map<String, Object?> m(Object? v) =>
        (v as Map?)?.cast<String, Object?>() ?? {};
    final sidesJson = m(j['sides']);
    final sides = {
      for (final s in Side.values)
        if (sidesJson[s.name] != null)
          s: OnlineFighter.fromJson(m(sidesJson[s.name])),
    };
    final mySide = sides[Side.b]?.uid == myUid && myUid != null
        ? Side.b
        : Side.a;
    final viewJson = m(j['view']);
    final submittedJson = m(j['submitted']);
    final resultJson = m(j['result']);
    return MatchSnapshot(
      id: id,
      status: MatchStatus.values.asNameMap()[j['status']] ?? MatchStatus.active,
      turn: (j['turn'] as num?)?.toInt() ?? 1,
      mySide: mySide,
      sides: sides,
      view: {
        for (final s in Side.values)
          if (viewJson[s.name] != null)
            s: FighterView.fromJson(m(viewJson[s.name])),
      },
      submitted: {
        for (final s in Side.values) s: submittedJson[s.name] == true,
      },
      turnDeadlineMs: (j['turnDeadlineMs'] as num?)?.toInt(),
      winner: j['winner'] as String?,
      endReason: j['endReason'] as String?,
      result: {
        for (final s in Side.values)
          if (resultJson[s.name] != null)
            s: MatchSideResult.fromJson(m(resultJson[s.name])),
      },
    );
  }
}

class PollResult {
  const PollResult({
    required this.status,
    required this.turn,
    this.turnDeadlineMs,
  });
  final MatchStatus status;
  final int turn;
  final int? turnDeadlineMs;

  factory PollResult.fromJson(Map<String, Object?> j) => PollResult(
    status: MatchStatus.values.asNameMap()[j['status']] ?? MatchStatus.active,
    turn: (j['turn'] as num?)?.toInt() ?? 1,
    turnDeadlineMs: (j['turnDeadlineMs'] as num?)?.toInt(),
  );
}

/// Preset report reasons (`reportCharacter.reasonCode`).
enum ReportReason {
  badPicture('bad_picture', 'こわい え・いやな え'),
  badName('bad_name', 'いやな なまえ'),
  realPerson('real_person', 'ほんものの ひとの しゃしん'),
  personalInfo('personal_info', 'なまえや じゅうしょが かいてある'),
  copiedCharacter('copied_character', 'ほかの キャラの まるうつし'),
  other('other', 'そのほか');

  const ReportReason(this.code, this.label);
  final String code;

  /// Hiragana label shown to children.
  final String label;
}

/// Parses one turn log's events; events this client does not understand are
/// skipped (e.g. from a newer server engine).
List<BattleEvent> parseTurnEvents(Object? raw) {
  final out = <BattleEvent>[];
  for (final e in (raw as List?) ?? const []) {
    try {
      out.add(BattleEvent.fromJson((e as Map).cast<String, Object?>()));
    } on Object {
      // ignore unknown event shapes
    }
  }
  return out;
}
