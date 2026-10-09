#!/usr/bin/env bash
# Derive Android versionName / versionCode from a release tag.
#
#   v1.2.3        -> versionName 1.2.3        versionCode 1020399   (final release = 99)
#   v1.2.3-rc.4   -> versionName 1.2.3-rc.4   versionCode 1020304   (release candidate 1..98)
#
# versionCode = MAJOR*1_000_000 + MINOR*10_000 + PATCH*100 + BUILD
#   MINOR, PATCH: 0..99   BUILD: rc number 1..98, or 99 for the final release.
# A final release therefore always outranks its own release candidates, and every
# tag maps to exactly one versionCode (Play rejects a re-upload of the same code,
# which is what we want: rebuild = new rc tag). Max MAJOR is 2099 (Play limit 2100000000).
#
# Usage: scripts/version_from_tag.sh <tag>       (prints `version_name=..` and `version_code=..`)
#        GITHUB_OUTPUT is appended to when set (for GitHub Actions).
set -euo pipefail

tag="${1:-}"
if [[ -z "$tag" ]]; then
  echo "usage: $0 <tag like v1.2.3 or v1.2.3-rc.4>" >&2
  exit 2
fi

re='^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-rc\.([0-9]+))?$'
if [[ ! "$tag" =~ $re ]]; then
  echo "error: '$tag' is not a release tag (expected vMAJOR.MINOR.PATCH or vMAJOR.MINOR.PATCH-rc.N)" >&2
  exit 1
fi
major=$((10#${BASH_REMATCH[1]}))
minor=$((10#${BASH_REMATCH[2]}))
patch=$((10#${BASH_REMATCH[3]}))
rc="${BASH_REMATCH[5]:-}"

if (( minor > 99 || patch > 99 )); then
  echo "error: MINOR and PATCH must be <= 99 (got $minor.$patch)" >&2
  exit 1
fi
if (( major < 1 && minor < 1 && patch < 1 )); then
  echo "error: version 0.0.0 is not allowed" >&2
  exit 1
fi
if [[ -n "$rc" ]]; then
  build=$((10#$rc))
  if (( build < 1 || build > 98 )); then
    echo "error: rc number must be 1..98 (got $build)" >&2
    exit 1
  fi
  name="$major.$minor.$patch-rc.$build"
else
  build=99
  name="$major.$minor.$patch"
fi

code=$((major * 1000000 + minor * 10000 + patch * 100 + build))
if (( code > 2100000000 )); then
  echo "error: versionCode $code exceeds Play's limit 2100000000" >&2
  exit 1
fi

echo "version_name=$name"
echo "version_code=$code"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "version_name=$name"
    echo "version_code=$code"
  } >> "$GITHUB_OUTPUT"
fi
