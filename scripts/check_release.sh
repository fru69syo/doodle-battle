#!/usr/bin/env bash
# Google Play Families / store compliance checks on the *merged* release manifest.
#
# Usage:
#   scripts/check_release.sh <app-release.aab | app-release.apk | AndroidManifest.xml> [options]
#
# Options:
#   --require-upload-key      fail if the AAB/APK is signed with the Android debug key
#   --expect-version-code N   fail unless versionCode == N
#   --expect-version-name S   fail unless versionName == S
#   --require-real-admob      fail when the AdMob APPLICATION_ID is Google's test App ID
#                             (release.yml; Play uploads must use the real AdMob app)
#   --iap                     the build sells in-app products (built with
#                             --dart-define=IAP_ENABLED=true): allow the BILLING permission.
#                             Without it (v2.0: free, SPEC §10.2) BILLING must be absent and the
#                             repo's IAP flag must default to off.
#
# Input:
#   .aab  manifest read with bundletool (scripts/bundletool.sh downloads it if needed)
#   .apk  manifest read with apkanalyzer (Android SDK cmdline-tools)
#   .xml  a merged manifest, e.g. from `gradlew :app:processReleaseMainManifest`
#
# What fails the check (exit 1):
#   - any <uses-permission> not on the ALLOWLIST below (AD_ID, location, RECORD_AUDIO,
#     READ_CONTACTS, ... are additionally called out with a reason)
#   - legacy storage permissions without android:maxSdkVersion <= 28
#   - targetSdkVersion < MIN_TARGET_SDK, minSdkVersion != EXPECTED_MIN_SDK
#   - wrong package name, android:debuggable="true", cleartext traffic allowed
#   - Firebase/Google Analytics (measurement) components or the install-referrer service
#   - AdMob present without the setup we expect: DELAY_APP_MEASUREMENT_INIT=true, a well-formed
#     APPLICATION_ID (test id only a warning unless --require-real-admob); the AD_ID / Privacy
#     Sandbox permissions are on the deny list above (docs/COMPLIANCE.md)
#   - Crashlytics present without firebase_crashlytics_collection_enabled=false (opt-in only)
#   - in-app purchases (unless --iap): the com.android.vending.BILLING permission in the
#     manifest (the release build removes it while IAP_ENABLED is off, build.gradle.kts), or
#     app/lib/core/config/app_config.dart letting IAP_ENABLED default to true
#   - with --require-upload-key: debug-signed artifact
#
# The allowlist is deliberately short. To add a permission, add it here *and* update
# docs/STORE_LISTING.md (Data safety / permissions) and get PM sign-off.
set -euo pipefail

EXPECTED_PACKAGE="${EXPECTED_PACKAGE:-com.fru69syo.doodle_battle}"
MIN_TARGET_SDK="${MIN_TARGET_SDK:-36}"
EXPECTED_MIN_SDK="${EXPECTED_MIN_SDK:-24}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input=""
require_upload_key=0
require_real_admob=0
allow_iap=0
expect_code=""
expect_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-upload-key) require_upload_key=1 ;;
    --require-real-admob) require_real_admob=1 ;;
    --expect-version-code) expect_code="$2"; shift ;;
    --expect-version-name) expect_name="$2"; shift ;;
    --iap) allow_iap=1 ;;
    -h|--help) sed -n '2,42p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) input="$1" ;;
  esac
  shift
done
if [[ -z "$input" || ! -f "$input" ]]; then
  echo "usage: $0 <app-release.aab|.apk|AndroidManifest.xml> [--require-upload-key] [--require-real-admob] [--iap] [--expect-version-code N] [--expect-version-name S]" >&2
  exit 2
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
manifest="$workdir/AndroidManifest.xml"

case "$input" in
  *.aab)
    "$here/bundletool.sh" dump manifest --bundle "$input" > "$manifest"
    ;;
  *.apk)
    analyzer="$(command -v apkanalyzer || true)"
    if [[ -z "$analyzer" && -n "${ANDROID_HOME:-}" ]]; then
      analyzer="$(find "$ANDROID_HOME/cmdline-tools" -maxdepth 3 -path "*/bin/apkanalyzer" 2>/dev/null | head -1 || true)"
    fi
    [[ -n "$analyzer" ]] || { echo "apkanalyzer not found (install Android cmdline-tools)" >&2; exit 2; }
    "$analyzer" manifest print "$input" > "$manifest"
    ;;
  *.xml)
    cp "$input" "$manifest"
    ;;
  *)
    echo "unsupported input: $input" >&2; exit 2 ;;
esac

signer=""
if [[ "$input" == *.aab ]]; then
  # AABs are jar-signed (upload key).
  signer="$(keytool -printcert -jarfile "$input" 2>/dev/null | grep -m1 -E '^(Owner|所有者):' || true)"
elif [[ "$input" == *.apk ]]; then
  # APKs with minSdk >= 24 may be v2/v3-only signed; keytool cannot read those.
  apksigner="$(command -v apksigner || find "${ANDROID_HOME:-/nonexistent}/build-tools" -maxdepth 2 -name apksigner 2>/dev/null | sort -V | tail -1 || true)"
  if [[ -n "$apksigner" ]]; then
    dn="$("$apksigner" verify --print-certs "$input" 2>/dev/null | grep -m1 'certificate DN:' | sed 's/.*certificate DN: //' || true)"
    [[ -n "$dn" ]] && signer="Owner: $dn"
  fi
fi

repo="$(cd "$here/.." && pwd)"
app_config="$repo/app/lib/core/config/app_config.dart"
python3 -I - "$manifest" "$EXPECTED_PACKAGE" "$MIN_TARGET_SDK" "$EXPECTED_MIN_SDK" \
  "$require_upload_key" "$signer" "$expect_code" "$expect_name" "$require_real_admob" \
  "$allow_iap" "$app_config" <<'PY'
import os
import re
import sys
import xml.etree.ElementTree as ET

(manifest, expected_pkg, min_target, expected_min, require_key, signer,
 expect_code, expect_name, require_real_admob, allow_iap, app_config) = sys.argv[1:12]
A = "{http://schemas.android.com/apk/res/android}"

# --- Permission policy ----------------------------------------------------------
# name -> why it is OK (or a dict with conditions)
ALLOWLIST = {
    "android.permission.CAMERA": "drawing capture + AR (runtime permission, asked in context)",
    "android.permission.INTERNET": "Firebase (cloud judging / online battles), ads",
    "android.permission.ACCESS_NETWORK_STATE": "offline detection (Firebase, SceneView/media3, ads SDK)",
    "android.permission.WAKE_LOCK": "WorkManager / Firebase internals (normal permission)",
    "android.permission.RECEIVE_BOOT_COMPLETED": "WorkManager rescheduling (pulled in by Play services libs)",
    "android.permission.FOREGROUND_SERVICE": "WorkManager SystemForegroundService (no service of ours runs)",
}
BILLING = "com.android.vending.BILLING"
if allow_iap == "1":
    ALLOWLIST[BILLING] = "Google Play Billing (parent-gated purchases; built with IAP_ENABLED=true)"
# Allowed only with android:maxSdkVersion <= 28 (photo saving on Android 7-9).
LEGACY_STORAGE = {
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.READ_EXTERNAL_STORAGE",
}
# androidx.core adds "<applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION" (signature-level).
DYNAMIC_RECEIVER_SUFFIX = ".DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"

DENY_REASONS = {
    "com.google.android.gms.permission.AD_ID":
        "advertising ID must not be collected from children (Families policy). "
        "Remove with <uses-permission ... tools:node=\"remove\"/>",
    "android.permission.ACCESS_ADSERVICES_AD_ID": "Privacy Sandbox ad ID (child-directed app)",
    "android.permission.ACCESS_ADSERVICES_ATTRIBUTION": "Privacy Sandbox attribution (child-directed app)",
    "android.permission.ACCESS_ADSERVICES_TOPICS": "Privacy Sandbox topics (child-directed app)",
    "android.permission.ACCESS_FINE_LOCATION": "location is not collected (Families policy / Data safety)",
    "android.permission.ACCESS_COARSE_LOCATION": "location is not collected (Families policy / Data safety)",
    "android.permission.ACCESS_BACKGROUND_LOCATION": "location is not collected",
    "android.permission.ACCESS_MEDIA_LOCATION": "photo location metadata is not needed",
    "android.permission.RECORD_AUDIO": "no audio capture (camera plugin adds it; remove it)",
    "android.permission.READ_CONTACTS": "contacts are personal data of children/parents",
    "android.permission.WRITE_CONTACTS": "contacts are personal data",
    "android.permission.GET_ACCOUNTS": "account list is personal data",
    "android.permission.READ_PHONE_STATE": "device identifiers",
    "android.permission.READ_PHONE_NUMBERS": "personal data",
    "android.permission.READ_SMS": "restricted permission",
    "android.permission.READ_CALL_LOG": "restricted permission",
    "android.permission.READ_MEDIA_IMAGES": "use the system photo picker (image_picker) instead",
    "android.permission.READ_MEDIA_VIDEO": "use the system photo picker instead",
    "android.permission.READ_MEDIA_VISUAL_USER_SELECTED": "use the system photo picker instead",
    "android.permission.MANAGE_EXTERNAL_STORAGE": "restricted permission",
    "android.permission.QUERY_ALL_PACKAGES": "restricted permission",
    "android.permission.SYSTEM_ALERT_WINDOW": "overlays are not used",
    "android.permission.POST_NOTIFICATIONS": "no notifications in v1 (would need Data safety + parent consent)",
    "android.permission.VIBRATE": "removed on purpose (SceneView adds it); not needed",
    "android.permission.BLUETOOTH_SCAN": "nearby device discovery",
    "android.permission.NEARBY_WIFI_DEVICES": "nearby device discovery",
    "android.permission.ACCESS_WIFI_STATE": "can reveal network identifiers; not needed",
    "android.permission.BODY_SENSORS": "sensor data",
    "android.permission.ACTIVITY_RECOGNITION": "activity data",
    "com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE":
        "install referrer = attribution tracking (pulled in by Firebase Analytics, which SPEC §7 forbids)",
    "com.google.android.c2dm.permission.RECEIVE": "push messaging (FCM) is not used in v1",
}
if allow_iap != "1":
    DENY_REASONS[BILLING] = (
        "in-app purchases are off in v2.0 (SPEC §10.2; Play may label the app "
        "'contains in-app purchases'). The release build removes it unless built with "
        "--dart-define=IAP_ENABLED=true (build.gradle.kts, src/noIap); pass --iap for such builds")

errors, warnings, info = [], [], []

# The IAP flag must default to off in the source the release is built from (SPEC §10.2).
# `bool.fromEnvironment('IAP_ENABLED')` without a defaultValue (false) is the only accepted form.
if os.path.isfile(app_config):
    src = open(app_config, encoding="utf-8").read()
    m = re.search(r"kIapEnabled\s*=\s*bool\.fromEnvironment\(\s*'IAP_ENABLED'\s*(,[^)]*)?\)", src)
    if not m:
        errors.append("app_config.dart: kIapEnabled must be bool.fromEnvironment('IAP_ENABLED')")
    elif m.group(1) and "true" in m.group(1):
        (warnings if allow_iap == "1" else errors).append(
            "app_config.dart: IAP_ENABLED defaults to true (v2.0 ships with purchases off)")
    else:
        info.append("IAP_ENABLED defaults to off (app_config.dart)")

# Source checks for what the manifest cannot show (run from a checkout; skipped otherwise).
repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(app_config)))))
admob = os.path.join(repo, "app/lib/features/monetization/admob_gateway.dart")
if os.path.isfile(admob):
    # Families policy / COMPLIANCE C2: every ad request is child-directed, rated G, not personalised.
    src = open(admob, encoding="utf-8").read()
    missing = [n for n in ("AgeRestrictedTreatment.child", "TagForChildDirectedTreatment.yes",
                           "TagForUnderAgeOfConsent.yes", "MaxAdContentRating.g",
                           "nonPersonalizedAds: true", "disableMediationInitialization")
               if n not in src]
    for n in missing:
        errors.append(f"admob_gateway.dart: '{n}' missing (child-directed ad requests, "
                      "docs/COMPLIANCE.md C2)")
    if not missing:
        info.append("AdMob requests: child-directed, G, non-personalised (admob_gateway.dart)")
providers = os.path.join(repo, "app/lib/core/providers.dart")
if os.path.isfile(providers):
    # SPEC §10.2: rewarded ads exist only on Android (the iPhone build is ad-free).
    if not re.search(r"adsSupportedProvider\s*=\s*Provider<bool>\([^;]*Platform\.isAndroid",
                     open(providers, encoding="utf-8").read()):
        errors.append("providers.dart: adsSupportedProvider must require Platform.isAndroid "
                      "(iPhone build has no ads, SPEC §10.2)")
    else:
        info.append("ads only on Android (providers.dart adsSupportedProvider)")
# SPEC §11.1: the Claude model id is a deploy-time parameter (CLAUDE_MODEL), never in the repo.
model_id = re.compile(r"claude-(?:opus|sonnet|haiku|instant|[0-9])[-a-z0-9.@]*", re.I)
model_errors = len(errors)
for sub in ("app/lib", "firebase/functions/src", "server/realtime/src", "shared",
            ".github/workflows", "infra/terraform"):
    top = os.path.join(repo, sub)
    for dirpath, dirnames, files in os.walk(top):
        dirnames[:] = [d for d in dirnames if d not in ("node_modules", "build", "lib-cjs", ".terraform")]
        for name in files:
            path = os.path.join(dirpath, name)
            try:
                text = open(path, encoding="utf-8").read()
            except (UnicodeDecodeError, OSError):
                continue
            m = model_id.search(text)
            if m:
                errors.append(f"{os.path.relpath(path, repo)}: Claude model id '{m.group()}' in the "
                              "repo (set CLAUDE_MODEL at deploy time, SPEC §11.1)")
if os.path.isdir(os.path.join(repo, "app/lib")) and len(errors) == model_errors:
    info.append("no Claude model id in the sources (CLAUDE_MODEL is set at deploy time)")

root = ET.parse(manifest).getroot()
pkg = root.get("package", "")
info.append(f"package={pkg}")
if pkg != expected_pkg:
    errors.append(f"package is '{pkg}', expected '{expected_pkg}'")

vcode = root.get(A + "versionCode", "")
vname = root.get(A + "versionName", "")
info.append(f"versionCode={vcode} versionName={vname}")
if expect_code and vcode != expect_code:
    errors.append(f"versionCode is {vcode}, expected {expect_code}")
if expect_name and vname != expect_name:
    errors.append(f"versionName is '{vname}', expected '{expect_name}'")

# uses-sdk
sdk = root.find("uses-sdk")
if sdk is None:
    errors.append("no <uses-sdk> in merged manifest")
else:
    tgt = int(sdk.get(A + "targetSdkVersion", "0"))
    mn = int(sdk.get(A + "minSdkVersion", "0"))
    info.append(f"minSdk={mn} targetSdk={tgt}")
    if tgt < int(min_target):
        errors.append(f"targetSdkVersion {tgt} < {min_target} (Google Play target API requirement)")
    if mn != int(expected_min):
        errors.append(f"minSdkVersion {mn} != {expected_min} (SPEC: minSdk 24)")

# permissions
perms = []
for tag in ("uses-permission", "uses-permission-sdk-23", "permission"):
    for el in root.findall(tag):
        perms.append((tag, el.get(A + "name", ""), el.get(A + "maxSdkVersion")))
for tag, name, max_sdk in perms:
    if tag == "permission":
        if name.endswith(DYNAMIC_RECEIVER_SUFFIX):
            continue
        warnings.append(f"declares custom <permission> {name}")
        continue
    if name in DENY_REASONS:
        errors.append(f"forbidden permission {name}: {DENY_REASONS[name]}")
    elif name in LEGACY_STORAGE:
        if max_sdk is None or int(max_sdk) > 28:
            errors.append(f"{name} must have android:maxSdkVersion <= 28 (has {max_sdk})")
        else:
            info.append(f"permission {name} (maxSdk {max_sdk})")
    elif name.endswith(DYNAMIC_RECEIVER_SUFFIX):
        if name != expected_pkg + DYNAMIC_RECEIVER_SUFFIX:
            errors.append(f"unexpected dynamic receiver permission {name}")
    elif name in ALLOWLIST:
        info.append(f"permission {name}")
    else:
        errors.append(f"permission {name} is not on the allowlist (scripts/check_release.sh)")

# application flags
app = root.find("application")
if app is None:
    errors.append("no <application>")
else:
    if app.get(A + "debuggable") == "true":
        errors.append("android:debuggable=\"true\" in release manifest")
    if app.get(A + "usesCleartextTraffic") == "true":
        errors.append("android:usesCleartextTraffic=\"true\" (all traffic must be HTTPS)")
    if app.get(A + "testOnly") == "true":
        errors.append("android:testOnly=\"true\" (Play rejects test-only builds)")
    label = app.get(A + "label", "")
    if label != "おえかきファイターズ":  # SPEC §11.4, app_config.dart appDisplayName
        warnings.append(f"application label is '{label}' (should be おえかきファイターズ)")

    names = []
    for comp in ("activity", "activity-alias", "service", "receiver", "provider"):
        for el in app.findall(comp):
            names.append(el.get(A + "name", ""))
    meta = {el.get(A + "name", ""): el.get(A + "value") for el in app.findall("meta-data")}

    analytics = [n for n in names if "gms.measurement" in n or "firebase.analytics" in n]
    if analytics:
        errors.append("Google/Firebase Analytics components present (SPEC §7: no Analytics): "
                      + ", ".join(sorted(set(analytics))))
    if meta.get("firebase_analytics_collection_deactivated") not in (None, "true"):
        errors.append("firebase_analytics_collection_deactivated must be true when present")

    ads_app_id = meta.get("com.google.android.gms.ads.APPLICATION_ID")
    ads_sdk = any(n.startswith("com.google.android.gms.ads.") for n in names)
    if ads_sdk and ads_app_id is None:
        errors.append("Mobile Ads SDK present but no com.google.android.gms.ads.APPLICATION_ID "
                      "meta-data (the app would crash at start)")
    if ads_app_id is not None:
        info.append(f"AdMob app id present ({ads_app_id})")
        if not re.fullmatch(r"ca-app-pub-\d{16}~\d{10}", ads_app_id):
            errors.append(f"AdMob APPLICATION_ID '{ads_app_id}' is malformed (ADMOB_APP_ID)")
        elif ads_app_id.startswith("ca-app-pub-3940256099942544"):
            (errors if require_real_admob == "1" else warnings).append(
                "AdMob APPLICATION_ID is Google's *test* app id (set ADMOB_APP_ID)")
        if meta.get("com.google.android.gms.ads.DELAY_APP_MEASUREMENT_INIT") != "true":
            errors.append("AdMob: meta-data DELAY_APP_MEASUREMENT_INIT must be true "
                          "(no app measurement; SPEC §7)")
    elif require_real_admob == "1":
        errors.append("--require-real-admob: no AdMob APPLICATION_ID in the manifest")

    # Crashlytics must be opt-in (parent consent): collection off by default.
    all_meta = {el.get(A + "name", ""): el.get(A + "value") for el in root.iter("meta-data")}
    crashlytics = any("firebase.crashlytics" in k for k in all_meta)
    if crashlytics:
        flag = meta.get("firebase_crashlytics_collection_enabled")
        if flag != "false":
            errors.append("Crashlytics present but firebase_crashlytics_collection_enabled is "
                          f"'{flag}' (must be 'false': crash reports are opt-in)")
        else:
            info.append("Crashlytics present, collection disabled by default (opt-in)")

    ar = meta.get("com.google.ar.core")
    if ar is not None and ar != "optional":
        errors.append(f"com.google.ar.core is '{ar}', must be 'optional' (app installs on non-AR devices)")

# required features would hide the app from devices without them
for f in root.findall("uses-feature"):
    name = f.get(A + "name") or f"glEsVersion={f.get(A + 'glEsVersion')}"
    if f.get(A + "required", "true") == "true":
        errors.append(f"<uses-feature {name}> is required; must be required=\"false\"")

# signing
if signer:
    info.append(f"signed by: {signer.split(':',1)[1].strip()}")
    if "CN=Android Debug" in signer:
        (errors if require_key == "1" else warnings).append(
            "artifact is signed with the Android DEBUG key (no android/key.properties)")
elif require_key == "1":
    errors.append("artifact is not signed (no android/key.properties?)")

for m in info:
    print(f"  ok    {m}")
for m in warnings:
    print(f"  WARN  {m}")
for m in errors:
    print(f"  FAIL  {m}")
if errors:
    print(f"check_release: {len(errors)} error(s)")
    sys.exit(1)
print(f"check_release: passed ({len(warnings)} warning(s))")
PY
