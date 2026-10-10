import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/battle/battle.dart';
import '../app_settings.dart';
import 'backend_api.dart';

/// Cloud Functions region (docs/BACKEND.md §2).
const functionsRegion = 'asia-northeast1';

/// [BackendApi] on Firebase: Anonymous Auth, callable functions with App
/// Check, and read-only Firestore/Storage access.
///
/// Nothing touches the network until a server feature is used: App Check is
/// activated and the anonymous user is created on the first call, and the
/// app only makes calls once a parent enabled cloud judging or online play
/// (see `SettingsController.ensureConsentSynced`).
class FirebaseBackendApi implements BackendApi {
  FirebaseBackendApi({
    Future<void> Function()? activateAppCheck,
    this.callTimeout = const Duration(seconds: 30),
  }) : _activateAppCheck = activateAppCheck ?? (() async {});

  final Future<void> Function() _activateAppCheck;
  final Duration callTimeout;
  Future<void>? _appCheck;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  late final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: functionsRegion,
  );
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseStorage get _storage => FirebaseStorage.instance;

  @override
  bool get isAvailable => true;

  @override
  String? get supportId => _auth.currentUser?.uid;

  Future<String> _ensureSignedIn() async {
    try {
      await (_appCheck ??= _activateAppCheck());
      final current = _auth.currentUser;
      if (current != null) return current.uid;
      final cred = await _auth.signInAnonymously().timeout(callTimeout);
      return cred.user!.uid;
    } on Object catch (e) {
      _appCheck = null;
      throw BackendException(BackendCodes.network, '$e');
    }
  }

  Future<Map<String, Object?>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    await _ensureSignedIn();
    try {
      final result = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: callTimeout),
          )
          .call<Object?>(data);
      final raw = result.data;
      return raw is Map ? _deepCast(raw) : <String, Object?>{};
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final code = details is Map && details['code'] is String
          ? details['code'] as String
          : _codeFromStatus(e.code);
      throw BackendException(code, e.message);
    } on TimeoutException {
      throw const BackendException(BackendCodes.network, 'timeout');
    } on Object catch (e) {
      throw BackendException(BackendCodes.network, '$e');
    }
  }

  static String _codeFromStatus(String status) => switch (status) {
    'unauthenticated' => BackendCodes.unauthenticated,
    'permission-denied' => BackendCodes.consentRequired,
    'resource-exhausted' => BackendCodes.rateLimited,
    'not-found' => BackendCodes.notFound,
    'invalid-argument' => BackendCodes.invalidArgument,
    'internal' => BackendCodes.internal,
    _ => BackendCodes.network,
  };

  static Map<String, Object?> _deepCast(Map raw) =>
      jsonDecode(jsonEncode(raw)) as Map<String, Object?>;

  @override
  Future<void> syncConsent(ParentConsents consents, int policyVersion) async {
    final uid = await _ensureSignedIn();
    final doc = _firestore.collection('users').doc(uid);
    final consent = {
      'cloudJudge': consents.cloudJudge,
      'online': consents.online,
      'policyVersion': policyVersion,
    };
    try {
      final snap = await doc.get();
      if (snap.exists) {
        await doc.update({
          'consent': consent,
          'consentUpdatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await doc.set({
          'consent': consent,
          'consentUpdatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } on Object catch (e) {
      throw BackendException(BackendCodes.network, '$e');
    }
  }

  @override
  Future<CloudJudgement> judgeDrawing(Uint8List cutoutPng) async =>
      CloudJudgement.fromJson(
        await _call('judgeDrawing', {'imageBase64': base64Encode(cutoutPng)}),
      );

  @override
  Future<RegisterOutcome> registerCharacter(
    RegisterCharacterRequest request,
  ) async => RegisterOutcome.fromJson(
    await _call('registerCharacter', request.toJson()),
  );

  @override
  Future<QueueStatus> joinQueue(String snapshotId) async =>
      QueueStatus.fromJson(
        await _call('joinQueue', {'characterId': snapshotId}),
      );

  @override
  Future<void> leaveQueue() async {
    if (_auth.currentUser == null) return;
    await _call('leaveQueue', {});
  }

  @override
  Stream<MatchSnapshot> watchMatch(String matchId) async* {
    final uid = await _ensureSignedIn();
    yield* _firestore
        .collection('matches')
        .doc(matchId)
        .snapshots()
        .where((s) => s.exists)
        .map(
          (s) => MatchSnapshot.fromJson(
            s.id,
            _deepCastFirestore(s.data()!),
            myUid: uid,
          ),
        );
  }

  /// Firestore maps may contain Timestamps; convert to millis for parsing.
  static Map<String, Object?> _deepCastFirestore(Map<String, dynamic> data) {
    Object? conv(Object? v) => switch (v) {
      Timestamp t => t.millisecondsSinceEpoch,
      Map m => {for (final e in m.entries) '${e.key}': conv(e.value)},
      List l => [for (final x in l) conv(x)],
      _ => v,
    };
    return conv(data)! as Map<String, Object?>;
  }

  @override
  Future<List<BattleEvent>> turnEvents(String matchId, int turn) async {
    await _ensureSignedIn();
    try {
      final snap = await _firestore
          .collection('matches')
          .doc(matchId)
          .collection('turns')
          .doc('$turn')
          .get();
      return parseTurnEvents(snap.data()?['events']);
    } on Object catch (e) {
      throw BackendException(BackendCodes.network, '$e');
    }
  }

  @override
  Future<void> submitAction(String matchId, int turn, BattleAction action) =>
      _call('submitAction', {
        'matchId': matchId,
        'turn': turn,
        'action': action.name,
      });

  @override
  Future<PollResult> pollMatch(String matchId) async =>
      PollResult.fromJson(await _call('pollMatch', {'matchId': matchId}));

  @override
  Future<ChosenDisplayName> setDisplayName(
    String adjectiveId,
    String nounId,
  ) async {
    final r = await _call('setDisplayName', {
      'adjectiveId': adjectiveId,
      'nounId': nounId,
    });
    final dn = r['displayName'];
    if (dn is! Map) {
      throw const BackendException(BackendCodes.internal, 'no displayName');
    }
    return ChosenDisplayName.fromJson(dn.cast<String, Object?>());
  }

  @override
  Future<bool> reportCharacter(String snapshotId, ReportReason reason) async {
    final r = await _call('reportCharacter', {
      'snapshotId': snapshotId,
      'reasonCode': reason.code,
    });
    return r['alreadyReported'] == true;
  }

  @override
  Future<void> reportAiSuggestion(
    AiSuggestionKind kind,
    String text,
    AiReportReason reason,
  ) async {
    await _call('reportAiSuggestion', {
      'kind': kind.code,
      'text': text,
      'reasonCode': reason.code,
    });
  }

  @override
  Future<Uint8List?> loadSnapshotImage(String imagePath) async {
    try {
      await _ensureSignedIn();
      return await _storage.ref(imagePath).getData(1024 * 1024);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> deleteMyData() async {
    if (_auth.currentUser == null) return; // nothing on the server
    await _call('deleteMyData', {'confirm': 'DELETE'});
    try {
      await _auth.signOut();
    } on Object {
      // the auth user is already deleted server-side
    }
  }
}
