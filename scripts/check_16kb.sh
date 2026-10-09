#!/usr/bin/env bash
# 16 KB page-size compatibility + download size report for a release AAB.
#
# Usage: scripts/check_16kb.sh app-release.aab
#
# 1. bundletool build-apks --mode=universal  (signed with a throwaway key, only for inspection)
# 2. zipalign -c -P 16 -v 4 on the universal APK  (uncompressed .so must be 16 KB aligned in the zip)
# 3. every 64-bit ELF (arm64-v8a, x86_64) must have LOAD segment p_align >= 16384
#    (32-bit ABIs are exempt from Google Play's 16 KB requirement)
# 4. prints AAB size and estimated download sizes for an arm64 phone (bundletool get-size)
#
# Needs: java, python3, Android build-tools (zipalign) via ANDROID_HOME.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
aab="${1:-}"
[[ -f "$aab" ]] || { echo "usage: $0 app-release.aab" >&2; exit 2; }

zipalign="$(command -v zipalign || true)"
if [[ -z "$zipalign" ]]; then
  zipalign="$(find "${ANDROID_HOME:-/nonexistent}/build-tools" -maxdepth 2 -name zipalign 2>/dev/null | sort -V | tail -1 || true)"
fi
[[ -x "$zipalign" ]] || { echo "zipalign not found (set ANDROID_HOME)" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

keytool -genkeypair -keystore "$work/inspect.jks" -storetype PKCS12 -alias inspect \
  -keyalg RSA -keysize 2048 -validity 1 -storepass inspect -keypass inspect \
  -dname "CN=inspect" >/dev/null 2>&1

"$here/bundletool.sh" build-apks --bundle "$aab" --output "$work/u.apks" --mode=universal \
  --ks "$work/inspect.jks" --ks-key-alias inspect --ks-pass pass:inspect --key-pass pass:inspect
(cd "$work" && python3 -I -c 'import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extract("universal.apk", sys.argv[2])' u.apks .)
apk="$work/universal.apk"

status=0
echo "== zipalign -c -P 16 (universal APK)"
if "$zipalign" -c -P 16 -v 4 "$apk" > "$work/zipalign.log" 2>&1; then
  echo "   ok: $(grep -c '\.so' "$work/zipalign.log" || true) native libs, all 16 KB aligned in the zip"
else
  grep -E '\.so|FAIL|BAD' "$work/zipalign.log" | grep -v '(OK' | head -20 || true
  echo "   FAIL: zip alignment"
  status=1
fi

echo "== ELF LOAD segment alignment (64-bit ABIs)"
python3 -I - "$apk" <<'PY' || status=1
import struct, sys, zipfile
bad, ok, skipped = [], 0, 0
with zipfile.ZipFile(sys.argv[1]) as z:
    for n in sorted(z.namelist()):
        if not (n.startswith("lib/") and n.endswith(".so")):
            continue
        d = z.read(n)
        if d[:4] != b"\x7fELF":
            continue
        if d[4] != 2:  # ELFCLASS32: armeabi-v7a / x86 are exempt
            skipped += 1
            continue
        phoff = struct.unpack_from("<Q", d, 0x20)[0]
        phentsize, phnum = struct.unpack_from("<HH", d, 0x36)
        aligns = []
        for i in range(phnum):
            off = phoff + i * phentsize
            p_type = struct.unpack_from("<I", d, off)[0]
            if p_type == 1:  # PT_LOAD
                aligns.append(struct.unpack_from("<Q", d, off + 0x30)[0])
        m = min(aligns) if aligns else 0
        if m < 16384:
            bad.append(f"{n} (p_align={m})")
        else:
            ok += 1
print(f"   64-bit libs >= 16 KB: {ok}; 32-bit skipped: {skipped}")
for b in bad:
    print(f"   FAIL {b}")
sys.exit(1 if bad else 0)
PY

echo "== size"
python3 -I -c 'import os,sys; print(f"   AAB: {os.path.getsize(sys.argv[1])/1048576:.1f} MiB"); print(f"   universal APK: {os.path.getsize(sys.argv[2])/1048576:.1f} MiB")' "$aab" "$apk"
cat > "$work/device.json" <<'JSON'
{"supportedAbis":["arm64-v8a"],"supportedLocales":["ja-JP"],"screenDensity":420,"sdkVersion":34}
JSON
"$here/bundletool.sh" build-apks --bundle "$aab" --output "$work/d.apks" \
  --ks "$work/inspect.jks" --ks-key-alias inspect --ks-pass pass:inspect --key-pass pass:inspect >/dev/null
"$here/bundletool.sh" get-size total --apks "$work/d.apks" --device-spec "$work/device.json" \
  | awk -F, 'NR==2 { printf "   download size, arm64 phone (ja, 420dpi): %.1f MiB\n", $2/1048576 }'

exit "$status"
