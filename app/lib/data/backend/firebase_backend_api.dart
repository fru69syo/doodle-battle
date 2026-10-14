import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/cost_mode.dart';
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
  Future<CloudJudgement> judgeDrawing(
    Uint8List cutoutPng, {
    V2DrawingInput? v2,
  }) async => CloudJudgement.fromJson(
    await _call('judgeDrawing', {
      'imageBase64': base64Encode(cutoutPng),
      if (v2 != null) 'v2': v2.toJson(),
    }),
  );

  @override
  Future<RegisterOutcome> registerCharacter(
    RegisterCharacterRequest request,
  ) async => RegisterOutcome.fromJson(
    await _call('registerCharacter', request.toJson()),
  );

  @override
  Future<Map<String, Object?>?> generateMove(
    GenerateMoveRequest request,
  ) async {
    final r = await _call('generateMove', request.toJson());
    final p = r['proposal'];
    return p is Map ? p.cast<String, Object?>() : null;
  }

  @override
  Future<RealtimeAuth> realtimeAuth() async {
    await _ensureSignedIn();
    try {
      // Fresh token for every connection (never cached across restarts).
      final id = await _auth.currentUser!.getIdToken(true);
      String? appCheck;
      try {
        appCheck = await FirebaseAppCheck.instance.getToken();
      } on Object {
        appCheck = null; // the server refuses when App Check is required
      }
      return RealtimeAuth(idToken: id!, appCheckToken: appCheck);
    } on Object catch (e) {
      throw BackendException(BackendCodes.network, '$e');
    }
  }

  CostMode? _costMode;
  DateTime? _costModeAt;

  @override
  Future<CostMode> costMode() async {
    final at = _costModeAt;
    if (at != null && DateTime.now().difference(at).inSeconds < 60) {
      return _costMode!;
    }
    var mode = CostMode.normal;
    try {
      await _ensureSignedIn();
      final snap = await _firestore
          .collection('config')
          .doc('costMode')
          .get()
          .timeout(const Duration(seconds: 5));
      mode = CostMode.parse(snap.data()?['mode']);
    } on Object {
      mode = _costMode ?? CostMode.normal;
    }
    _costMode = mode;
    _costModeAt = DateTime.now();
    return mode;
  }

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
