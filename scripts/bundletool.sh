#!/usr/bin/env bash
# Run bundletool, downloading the pinned "all" jar once into a cache dir.
#   BUNDLETOOL_JAR=/path/to/bundletool-all.jar   use an existing jar instead
#   BUNDLETOOL_CACHE=~/.cache/bundletool         where the downloaded jar is kept
set -euo pipefail
VERSION="1.18.3"
SHA256="a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"

jar="${BUNDLETOOL_JAR:-}"
if [[ -z "$jar" ]]; then
  cache="${BUNDLETOOL_CACHE:-$HOME/.cache/bundletool}"
  jar="$cache/bundletool-all-$VERSION.jar"
  if [[ ! -f "$jar" ]]; then
    mkdir -p "$cache"
    tmp="$(mktemp "$cache/dl.XXXXXX")"
    curl -fsSL -o "$tmp" \
      "https://github.com/google/bundletool/releases/download/$VERSION/bundletool-all-$VERSION.jar"
    echo "$SHA256  $tmp" | sha256sum -c --quiet - >&2
    mv "$tmp" "$jar"
  fi
fi
exec java -jar "$jar" "$@"
