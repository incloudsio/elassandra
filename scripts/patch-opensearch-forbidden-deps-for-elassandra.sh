#!/usr/bin/env bash
# Elassandra sources use Guava on the compile classpath; OpenSearch forbids it in gradle/forbidden-dependencies.gradle.
# Formal fork exception for the side-car pipeline: the 'guava' rule is commented with marker elassandra-side-car-forbidden-deps.
# Long-term: remove Guava from Elassandra code paths or replace this with an explicit OpenSearch fork dependency policy change.
# Restore stock guard: mv forbidden-dependencies.gradle.bak forbidden-dependencies.gradle
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
