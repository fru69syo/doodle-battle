import 'dart:typed_data';

import '../../domain/cost_mode.dart';
import '../app_settings.dart';
import '../game_progress.dart';
import 'backend_models.dart';

export '../game_progress.dart' show ChosenDisplayName;
export 'backend_models.dart';

/// All server calls (docs/BACKEND.md §5). Every method throws
/// [BackendException] on failure. Implementations: [FirebaseBackendApi]
/// (real), [UnavailableBackendApi] (Firebase not configured) and a fake in
/// tests.
abstract interface class BackendApi {
  /// False when Firebase is not configured: online and cloud features show
  /// 「じゅんびちゅう」.
  bool get isAvailable;

  /// Anonymous user id once signed in (shown to parents as support ID).
  String? get supportId;

  /// Writes the parent's consent to `users/{uid}` (signs in if needed).
  Future<void> syncConsent(ParentConsents consents, int policyVersion);

  /// Cloud judgement; with [v2] the same call also proposes AI moves
  /// ([CloudJudgement.moves]).
  Future<CloudJudgement> judgeDrawing(
    Uint8List cutoutPng, {
    V2DrawingInput? v2,
  });

  Future<RegisterOutcome> registerCharacter(RegisterCharacterRequest request);

  /// One AI move for a newly unlocked slot; null = keep the template move
  /// (offline, cost mode, refusal…, never shown to the child).
  Future<Map<String, Object?>?> generateMove(GenerateMoveRequest request);

  /// Fresh Firebase ID token (+ App Check token) for the realtime battle
  /// server's `hello` (signs in if needed).
  Future<RealtimeAuth> realtimeAuth();

  /// `config/costMode` (normal / saving / minimal). Read failures count as
  /// [CostMode.normal] (the server enforces the real mode anyway).
  Future<CostMode> costMode();

  /// Sets the online display name from preset word ids (shared/names);
  /// returns the name as composed by the server.
  Future<ChosenDisplayName> setDisplayName(String adjectiveId, String nounId);

  /// Returns true when this child had already reported the character.
  Future<bool> reportCharacter(String snapshotId, ReportReason reason);

  /// Reports a name / move name the AI suggested (preset reason only).
  Future<void> reportAiSuggestion(
    AiSuggestionKind kind,
    String text,
    AiReportReason reason,
  );

  /// Opponent snapshot image (Storage), or null.
  Future<Uint8List?> loadSnapshotImage(String imagePath);

  /// Deletes everything on the server and signs out (behind the gate).
  Future<void> deleteMyData();
}

/// Used when Firebase is not configured: nothing works, nothing crashes.
class UnavailableBackendApi implements BackendApi {
  const UnavailableBackendApi();

  Never _fail() => throw const BackendException(BackendCodes.unavailable);

  @override
  bool get isAvailable => false;
  @override
  String? get supportId => null;
  @override
  Future<void> syncConsent(ParentConsents consents, int policyVersion) async {}
  @override
  Future<CloudJudgement> judgeDrawing(
    Uint8List cutoutPng, {
    V2DrawingInput? v2,
  }) async => _fail();
  @override
  Future<RegisterOutcome> registerCharacter(RegisterCharacterRequest r) async =>
      _fail();
  @override
  Future<Map<String, Object?>?> generateMove(GenerateMoveRequest r) async =>
      null;
  @override
  Future<RealtimeAuth> realtimeAuth() async => _fail();
  @override
  Future<CostMode> costMode() async => CostMode.normal;
  @override
  Future<ChosenDisplayName> setDisplayName(
    String adjectiveId,
    String nounId,
  ) async => _fail();
  @override
  Future<bool> reportCharacter(String snapshotId, ReportReason reason) async =>
      _fail();
  @override
  Future<void> reportAiSuggestion(
    AiSuggestionKind kind,
    String text,
    AiReportReason reason,
  ) async => _fail();
  @override
  Future<Uint8List?> loadSnapshotImage(String imagePath) async => null;
  @override
  Future<void> deleteMyData() async {}
}
