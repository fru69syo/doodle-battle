#!/usr/bin/env bash
# Regenerates the store/QA screenshots in store/screenshots/raw/ by rendering
# the real app (fakes for services) in a widget test with the bundled fonts.
# The test is tagged `screenshots` and skipped in normal `flutter test` runs.
#
#   app/tool/screenshots.sh            # all screens
#   SCREENSHOT_DIR=/tmp/shots app/tool/screenshots.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
out="${SCREENSHOT_DIR:-$(cd .. && pwd)/store/screenshots/raw}"
mkdir -p "$out"
SCREENSHOT_DIR="$out" flutter test --concurrency=1 --run-skipped --tags screenshots \
  test/screenshots/screenshots_test.dart
ls -1 "$out"
