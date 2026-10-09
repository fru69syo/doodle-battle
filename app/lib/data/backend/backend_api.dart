import 'dart:typed_data';

import '../../domain/battle/battle.dart';
import '../app_settings.dart';
import 'backend_models.dart';

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

  Future<CloudJudgement> judgeDrawing(Uint8List cutoutPng);

  Future<RegisterOutcome> registerCharacter(RegisterCharacterRequest request);

  /// Join or heartbeat (call every ~10 s while waiting).
  Future<QueueStatus> joinQueue(String snapshotId);

  Future<void> leaveQueue();

  /// Live `matches/{id}`.
  Stream<MatchSnapshot> watchMatch(String matchId);

  /// Events of resolved turn [turn] (`matches/{id}/turns/{turn}`).
  Future<List<BattleEvent>> turnEvents(String matchId, int turn);

  Future<void> submitAction(String matchId, int turn, BattleAction action);

  Future<PollResult> pollMatch(String matchId);

  /// Returns true when this child had already reported the character.
  Future<bool> reportCharacter(String snapshotId, ReportReason reason);

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
  Future<CloudJudgement> judgeDrawing(Uint8List cutoutPng) async => _fail();
  @override
  Future<RegisterOutcome> registerCharacter(RegisterCharacterRequest r) async =>
      _fail();
  @override
  Future<QueueStatus> joinQueue(String snapshotId) async => _fail();
  @override
  Future<void> leaveQueue() async {}
  @override
  Stream<MatchSnapshot> watchMatch(String matchId) =>
      Stream.error(const BackendException(BackendCodes.unavailable));
  @override
  Future<List<BattleEvent>> turnEvents(String matchId, int turn) async =>
      _fail();
  @override
  Future<void> submitAction(
    String matchId,
    int turn,
    BattleAction action,
  ) async => _fail();
  @override
  Future<PollResult> pollMatch(String matchId) async => _fail();
  @override
  Future<bool> reportCharacter(String snapshotId, ReportReason reason) async =>
      _fail();
  @override
  Future<Uint8List?> loadSnapshotImage(String imagePath) async => null;
  @override
  Future<void> deleteMyData() async {}
}
