#!/usr/bin/env bash
# Materialise the Firebase client config for a build (CI or local).
#
#   FIREBASE_OPTIONS_DART_B64   base64 of app/lib/firebase_options.dart (from `flutterfire configure`)
#   GOOGLE_SERVICES_JSON_B64    base64 of app/android/app/google-services.json
#
# Usage: scripts/write_firebase_config.sh [--require]
#   --require   (release builds) fail unless the real config is available, either from the
#               variables above or already present in the checkout.
#   default     (CI)  write the real config if the variables are set; otherwise, if the app
#               depends on firebase_core and the files are missing, write *demo* stubs
#               (project `demo-doodle-battle`, which can never reach a real backend) so that
#               analyze/test/debug builds work on forks and PRs without secrets.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dart_file="$root/app/lib/firebase_options.dart"
json_file="$root/app/android/app/google-services.json"
require=0
[[ "${1:-}" == "--require" ]] && require=1

decode() { # <b64 env value> <dest>
  printf '%s' "$1" | base64 --decode > "$2"
  echo "wrote $(realpath --relative-to="$root" "$2") ($(wc -c < "$2") bytes)"
}

[[ -n "${FIREBASE_OPTIONS_DART_B64:-}" ]] && decode "$FIREBASE_OPTIONS_DART_B64" "$dart_file"
[[ -n "${GOOGLE_SERVICES_JSON_B64:-}" ]] && decode "$GOOGLE_SERVICES_JSON_B64" "$json_file"

uses_firebase=0
grep -qE '^\s+firebase_core:' "$root/app/pubspec.yaml" && uses_firebase=1

if (( require )); then
  if (( uses_firebase )) && [[ ! -s "$dart_file" ]]; then
    echo "error: app uses firebase_core but app/lib/firebase_options.dart is missing (secret FIREBASE_OPTIONS_DART_B64)" >&2
    exit 1
  fi
  if [[ -s "$dart_file" ]] && grep -q 'demo-doodle-battle' "$dart_file"; then
    echo "error: firebase_options.dart is the demo stub; release builds need the real project" >&2
    exit 1
  fi
  if grep -rqs 'com.google.gms.google-services' "$root/app/android" --include='*.kts' && [[ ! -s "$json_file" ]]; then
    echo "error: google-services plugin is applied but google-services.json is missing (secret GOOGLE_SERVICES_JSON_B64)" >&2
    exit 1
  fi
  echo "firebase config: ok (release)"
  exit 0
fi

if (( uses_firebase )) && [[ ! -s "$dart_file" ]]; then
  cat > "$dart_file" <<'DART'
// GENERATED STUB for CI only (scripts/write_firebase_config.sh). Not a real project.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => android;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-doodle-battle',
    storageBucket: 'demo-doodle-battle.appspot.com',
  );
}
DART
  echo "wrote demo stub app/lib/firebase_options.dart"
fi
if grep -rqs 'com.google.gms.google-services' "$root/app/android" --include='*.kts' && [[ ! -s "$json_file" ]]; then
  cat > "$json_file" <<'JSON'
{
  "project_info": {
    "project_number": "000000000000",
    "project_id": "demo-doodle-battle",
    "storage_bucket": "demo-doodle-battle.appspot.com"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:000000000000:android:0000000000000000000000",
        "android_client_info": { "package_name": "com.fru69syo.doodle_battle" }
      },
      "oauth_client": [],
      "api_key": [{ "current_key": "demo-api-key" }],
      "services": { "appinvite_service": { "other_platform_oauth_client": [] } }
    }
  ],
  "configuration_version": "1"
}
JSON
  echo "wrote demo stub app/android/app/google-services.json"
fi
echo "firebase config: ok (ci)"
