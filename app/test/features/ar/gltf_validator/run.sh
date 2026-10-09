#!/usr/bin/env bash
# Exports sample standee GLBs from the Dart generator and validates them with
# the Khronos glTF validator (npm: gltf-validator).
# Run from anywhere: app/test/features/ar/gltf_validator/run.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$here/../../../.." && pwd)"
out="$(mktemp -d)"
(cd "$app" && AR_GLB_EXPORT_DIR="$out" flutter test test/features/ar/glb_export_test.dart)
(cd "$here" && npm install --no-audit --no-fund --silent)
node "$here/validate.mjs" "$out"
