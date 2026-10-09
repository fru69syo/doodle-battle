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
// Release safety: `scripts/write_firebase_config.sh --require` refuses to ship
// this file. It detects the marker below (also present in the CI stub), the
// `demo-` project id, and the absence of real Android options. Keep the
// marker until the file is replaced by `flutterfire configure`.
// DOODLE_BATTLE_FIREBASE_PLACEHOLDER (demo-doodle-battle)
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
