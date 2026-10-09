// ============================================================================
// PLACEHOLDER — there is no Firebase project yet.
//
// Generate the real file with the FlutterFire CLI (see docs/UI.md §Firebase):
//   cd app && flutterfire configure --project=<firebase-project-id> \
//     --platforms=android --out=lib/firebase_options.dart
//
// While this placeholder is in place `currentPlatform` throws
// UnsupportedError, exactly like a generated file does for an unconfigured
// platform, and the app runs fully offline (online battles and cloud judging
// show 「じゅんびちゅう」). Do NOT add the google-services Gradle plugin; the
// app initialises Firebase from these options.
//
// Release safety: like the CI stub this file mentions `demo-doodle-battle`,
// so `scripts/write_firebase_config.sh --require` refuses to ship it.
// ============================================================================
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'DefaultFirebaseOptions are a placeholder: run `flutterfire configure`.',
    );
  }
}
