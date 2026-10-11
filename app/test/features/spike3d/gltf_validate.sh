#!/usr/bin/env bash
# Exports inflated character GLBs (puffy + simplified) and validates them with
# the Khronos glTF validator, reusing the AR team's validator setup.
# Run from anywhere: app/test/features/spike3d/gltf_validate.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$here/../../.." && pwd)"
validator="$app/test/features/ar/gltf_validator"
out="$(mktemp -d)"
(cd "$app" && SPIKE3D_GLB_EXPORT_DIR="$out" flutter test test/features/spike3d/glb_export_test.dart)
(cd "$validator" && npm install --no-audit --no-fund --silent)
node "$validator/validate.mjs" "$out"
