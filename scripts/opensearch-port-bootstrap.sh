#!/usr/bin/env bash
# Create the OpenSearch side-car branch used for the Elassandra 1.3.x port (see docs/elassandra/source/developer/opensearch_porting_guide.rst).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${OPENSEARCH_TAG:-1.3.20}"
DEST="${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}"
BRANCH="${OPENSEARCH_PORT_BRANCH:-elassandra-os-1.3}"

OPENSEARCH_CLONE_DIR="$DEST" OPENSEARCH_TAG="$TAG" "$ROOT/scripts/clone-opensearch-upstream.sh"

cd "$DEST"
git fetch --tags origin 2>/dev/null || true
git checkout -B "$BRANCH" "$TAG"
echo "OpenSearch port branch ready: cd \"$DEST\" && git branch --show-current"
echo "Next: port org.elassandra.* from $ROOT/server/src/main/java/org/elassandra per opensearch_porting_guide.rst"
