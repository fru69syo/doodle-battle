#!/usr/bin/env bash
# Renders sample frames of the Before/After video to PNG for review
# (docs/VIDEO.md §7). Usage: tool/video_frames.sh [out_dir] [--all]
#   --all  every frame (then e.g. `ffmpeg -framerate 30 -i photo_%04d.png`
#          to preview the motion on a desktop)
set -euo pipefail
cd "$(dirname "$0")/.."
export VIDEO_FRAMES_DIR="${1:-build/video_frames}"
[[ "${2:-}" == "--all" ]] && export VIDEO_FRAMES_ALL=1
flutter test --run-skipped --tags video_frames \
  test/features/video_export/video_frames_dump_test.dart
echo "frames written to $VIDEO_FRAMES_DIR"
