#!/usr/bin/env bash
# Rewrite org/elassandra test sources under an OpenSearch side-car clone for org.opensearch.* imports.
#
# Prerequisite: port Elassandra's test/framework ESSingleNodeTestCase (CQL process(), etc.) and
# test/discovery/MockCassandraDiscovery onto org.opensearch.test.* in that clone; otherwise
# :server:compileTestJava will still fail after this pass.
#
# Usage:
#   ./scripts/rewrite-elassandra-opensearch-tests.sh [OPENSEARCH_CLONE_DIR]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}}"
TDIR="$DEST/server/src/test/java/org/elassandra"
if [[ ! -d "$TDIR" ]]; then
  echo "Not found: $TDIR" >&2
  exit 1
fi
"$ROOT/scripts/rewrite-engine-java-for-opensearch.sh" "$TDIR"
find "$TDIR" -name '*.java' -type f -exec perl -i -pe '
  s/\bESSingleNodeTestCase\b/OpenSearchSingleNodeTestCase/g;
  s/org\.opensearch\.test\.hamcrest\.ElasticsearchAssertions/org.opensearch.test.hamcrest.OpenSearchAssertions/g;
' {} +
echo "Rewrote tests under $TDIR"
