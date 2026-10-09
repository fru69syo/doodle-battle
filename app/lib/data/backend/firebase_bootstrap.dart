import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'backend_api.dart';
import 'firebase_backend_api.dart';

/// Initialises Firebase when `lib/firebase_options.dart` is configured and
/// returns the matching [BackendApi]. Never throws: without a Firebase
/// project (the placeholder options file) the app runs fully offline.
Future<BackendApi> initBackend() async {
  final FirebaseOptions options;
  try {
    options = DefaultFirebaseOptions.currentPlatform;
  } on UnsupportedError {
    debugPrint('Firebase is not configured: running offline.');
    return const UnavailableBackendApi();
  }
  try {
    // Local only: no network until a server feature is used.
    await Firebase.initializeApp(options: options);
    return FirebaseBackendApi(
      // Deferred to the first server call (Play Integrity; debug provider in
      // debug builds — register its token in the Firebase console).
      activateAppCheck: () => FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      ),
    );
  } on Object catch (e) {
    debugPrint('Firebase init failed, running offline: $e');
    return const UnavailableBackendApi();
  }
}
