#!/usr/bin/env bash
# Elassandra sources use Guava on the compile classpath; OpenSearch forbids it in gradle/forbidden-dependencies.gradle.
# This script comments out that guard in an OpenSearch side-car checkout (restore from .bak when done).
set -euo pipefail
OS_ROOT="${1:?OpenSearch clone root required}"
TARGET="$OS_ROOT/gradle/forbidden-dependencies.gradle"
if [[ ! -f "$TARGET" ]]; then
  echo "Missing $TARGET" >&2
  exit 1
fi
if grep -q "elassandra-side-car-forbidden-deps" "$TARGET"; then
  echo "Already patched: $TARGET"
  exit 0
fi
if [[ "$(uname -s)" == Darwin ]]; then
  cp "$TARGET" "$TARGET.bak"
  perl -i -pe "s/^(\s*)'guava'/\$1\/\/ elassandra-side-car-forbidden-deps: 'guava'/" "$TARGET"
else
  cp "$TARGET" "$TARGET.bak"
  sed -i "s/^\([[:space:]]*\)'guava'/\1\/\/ elassandra-side-car-forbidden-deps: 'guava'/" "$TARGET"
fi
echo "Patched $TARGET (backup: $TARGET.bak). Revert with: mv \"$TARGET.bak\" \"$TARGET\""
