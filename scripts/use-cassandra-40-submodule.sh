#!/usr/bin/env bash
# Switch server/cassandra to the Cassandra 4.0.x Elassandra branch (incloudsio/cassandra).
# After running, update OpenSearch port / org.elassandra.* before expecting a green build.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${CASSANDRA_40_BRANCH:-cassandra-4.0.x-elassandra}"
PROP_FILE="$ROOT/buildSrc/version.properties"

if [[ ! -d "$ROOT/server/cassandra/.git" ]] && ! git -C "$ROOT/server/cassandra" rev-parse --git-dir &>/dev/null; then
  echo "error: server/cassandra submodule not initialized" >&2
  exit 1
fi

(
  cd "$ROOT/server/cassandra"
  git remote get-url inclouds &>/dev/null || git remote add inclouds https://github.com/incloudsio/cassandra.git
  git fetch inclouds "$BRANCH"
  git checkout -B "elassandra-local-${BRANCH}" "inclouds/${BRANCH}"
  BASE_VER="$(grep -E 'property name="base\.version"' "$ROOT/server/cassandra/build.xml" | head -1 | sed 's/.*value="\([^"]*\)".*/\1/')"
  echo "Checked out Cassandra fork at base.version=$BASE_VER"
)

# Bump cassandra= in version.properties to match submodule build.xml
BASE_VER="$(grep -E 'property name="base\.version"' "$ROOT/server/cassandra/build.xml" | head -1 | sed 's/.*value="\([^"]*\)".*/\1/')"
if [[ -z "$BASE_VER" ]]; then
  echo "error: could not read base.version from server/cassandra/build.xml" >&2
  exit 1
fi
if grep -q '^[[:space:]]*cassandra[[:space:]]*=' "$PROP_FILE"; then
  if [[ "$(uname)" == Darwin ]]; then
    sed -i '' "s/^[[:space:]]*cassandra[[:space:]]*=.*/cassandra         = ${BASE_VER}/" "$PROP_FILE"
  else
    sed -i "s/^[[:space:]]*cassandra[[:space:]]*=.*/cassandra         = ${BASE_VER}/" "$PROP_FILE"
  fi
else
  echo "error: no cassandra= line in $PROP_FILE" >&2
  exit 1
fi

cd "$ROOT"
git add server/cassandra buildSrc/version.properties
echo "Staged server/cassandra + buildSrc/version.properties. Review and commit."
echo "Next: ./scripts/check-cassandra-submodule.sh && ./gradlew :server:compileJava (expect API fixes for Cassandra 4.0 + OpenSearch port)."
