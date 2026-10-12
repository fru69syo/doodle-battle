/// Request/response models of the Cloud Functions contracts in
/// docs/BACKEND.md §5. Plain Dart, no Firebase imports.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../domain/character_v2.dart';

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
    this.rejectCode,
    this.moves,
  });

  /// `IMAGE_AI_GENERATED` / `IMAGE_NOT_DRAWING` when the judge is confident
  /// the picture is not a hand drawing on paper (SPEC §11.1); the app then
  /// asks for a new photo with 「かみに かいた えを とってね」.
  static const aiGenerated = 'IMAGE_AI_GENERATED';
  static const notDrawing = 'IMAGE_NOT_DRAWING';

  final String? subject;
  final List<String> suggestedNames;
  final String? elementMoveName;
  final String? specialMoveName;
  final int skillEstimate;
  final bool appropriate;
  final List<String> reasons;
  final String? rejectCode;

  /// v2 only: the server-validated AI move proposal per slot (null = the
  /// offline move). The app re-validates them at every level.
  final List<Map<String, Object?>?>? moves;

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
      rejectCode: switch (j['rejectCode']) {
        aiGenerated => aiGenerated,
        notDrawing => notDrawing,
        _ => null,
      },
      moves: j['moves'] is List
          ? [
              for (final m in (j['moves']! as List).take(4))
                m is Map ? m.cast<String, Object?>() : null,
            ]
          : null,
    );
  }
}

/// The analyser's quantised output sent with `judgeDrawing` (`v2`) so the
/// server can size the AI move proposals (docs/BATTLE_V3.md §7).
class V2DrawingInput {
  const V2DrawingInput({
    required this.features,
    required this.energy10,
    required this.skill10,
    required this.imageHash,
  });

  final Map<String, int> features;
  final int energy10;
  final int skill10;
  final String imageHash;

  Map<String, Object?> toJson() => {
    'features': features,
    'energy10': energy10,
    'skill10': skill10,
    'imageHash': imageHash,
  };
}

/// `registerCharacter` request, `schema: 2` (engine v3 characters). The
/// server recomputes stats from the inputs; the response never depends on
/// the hidden state.
class RegisterCharacterRequest {
  const RegisterCharacterRequest({
    required this.character,
    required this.png,
    this.canvas,
  });

  final CharacterV2 character;

  /// Stroke summary of a drawing-tool character (`StrokeDrawing
  /// .canvasSummary`, docs/TRUST.md §8.2); null for photos.
  final Map<String, Object?>? canvas;

  /// Cut-out PNG (≤ 512 px).
  final Uint8List png;

  Map<String, Object?> toJson() {
    final c = character;
    return {
      'schema': 2,
      'localCharacterId': c.id,
      'imageBase64': base64Encode(png),
      'name': c.name,
      'level': c.level,
      'xp': c.xp,
      'features': c.features.toJson(),
      'energy10': c.energy10,
      'skill10': c.skill10,
      'imageHash': c.imageHash,
      'verdict': ?c.verdict,
      'moves': [for (final m in c.moves.take(4)) m.proposal],
      'rig': ?c.rig,
      'subject': ?c.subject,
      'source': c.source == DrawingSource.canvas ? 'canvas' : 'photo',
      if (c.source == DrawingSource.canvas) 'canvas': ?canvas,
    };
  }
}

/// `generateMove` request: one AI-designed move for the slot unlocked at
/// Lv10 (slot 2) or Lv50 (slot 3). Needs the cloudJudge consent.
class GenerateMoveRequest {
  const GenerateMoveRequest({
    required this.character,
    required this.png,
    required this.slot,
    required this.otherNames,
  });

  final CharacterV2 character;
  final Uint8List png;
  final int slot;
  final List<String> otherNames;

  Map<String, Object?> toJson() {
    final c = character;
    return {
      'imageBase64': base64Encode(png),
      'features': c.features.toJson(),
      'energy10': c.energy10,
      'skill10': c.skill10,
      'verdict': ?c.verdict,
      'level': c.level,
      'slot': slot,
      'otherNames': otherNames.take(3).toList(),
    };
  }
}

sealed class RegisterOutcome {
  const RegisterOutcome();

  factory RegisterOutcome.fromJson(Map<String, Object?> j) {
    if (j['ok'] == true) {
      return RegisterAccepted(
        snapshotId: j['snapshotId']! as String,
        name: j['name']! as String,
        displayName: j['displayName'] as String?,
        imageHash: j['imageHash'] as String?,
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
    this.displayName,
    this.imageHash,
  });
  final String snapshotId;
  final String name;
  final String? displayName;

  /// The seed hash the server used (SHA-256 of the uploaded PNG): the
  /// authority for the stored character (docs/TRUST.md §8.1).
  final String? imageHash;
}

class RegisterRejected extends RegisterOutcome {
  const RegisterRejected({required this.reason, this.presetNames = const []});

  /// One of the rejection reasons in docs/BACKEND.md §6.
  final String reason;

  /// Safe names to pick instead (only for NAME_* reasons).
  final List<String> presetNames;

  bool get isNameProblem => reason.startsWith('NAME_');
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

/// Which AI-suggested text is reported (`reportAiSuggestion`).
enum AiSuggestionKind {
  name('name'),
  elementMove('element_move'),
  specialMove('special_move');

  const AiSuggestionKind(this.code);
  final String code;
}

/// Preset reasons for reporting an AI suggestion (no free text; Google
/// Play AI-generated content policy).
enum AiReportReason {
  mean('mean', 'いやな ことば'),
  scary('scary', 'こわい ことば'),
  strange('strange', 'へんな ことば'),
  other('other', 'そのほか');

  const AiReportReason(this.code, this.label);
  final String code;

  /// Hiragana label shown to children.
  final String label;
}

/// Tokens for the realtime server's `hello` (docs/REALTIME_PROTOCOL.md §3).
class RealtimeAuth {
  const RealtimeAuth({required this.idToken, this.appCheckToken});
  final String idToken;
  final String? appCheckToken;
}
