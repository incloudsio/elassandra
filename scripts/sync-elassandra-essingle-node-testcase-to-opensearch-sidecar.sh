#!/usr/bin/env bash
# Replace stock OpenSearch OpenSearchSingleNodeTestCase with Elassandra's forked ESSingleNodeTestCase
# (CQL process(), ElassandraDaemon bootstrap, MockCassandraDiscovery, etc.), rewritten for org.opensearch.*.
#
# createIndex / ensureGreen behavior (wait-for-active-shards NONE, bounded health, master/ack timeouts) lives only
# in Elassandra's ESSingleNodeTestCase — edit that file, then re-run this script or opensearch-sidecar-prepare.sh.
#
# Usage: ./scripts/sync-elassandra-essingle-node-testcase-to-opensearch-sidecar.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?OpenSearch clone root}"
SRC="$ROOT/test/framework/src/main/java/org/elasticsearch/test/ESSingleNodeTestCase.java"
OUT="$DEST/test/framework/src/main/java/org/opensearch/test/OpenSearchSingleNodeTestCase.java"
[[ -f "$SRC" ]] || {
  echo "Missing Elassandra fork: $SRC" >&2
  exit 1
}
mkdir -p "$(dirname "$OUT")"
cp "$SRC" "$OUT"
"$ROOT/scripts/rewrite-engine-java-for-opensearch.sh" --file "$OUT"
perl -i -pe '
  s/\bESSingleNodeTestCase\b/OpenSearchSingleNodeTestCase/g;
  s/\bextends ESTestCase\b/extends OpenSearchTestCase/;
  s/\bESIntegTestCase\b/OpenSearchIntegTestCase/g;
  s/org\.opensearch\.test\.hamcrest\.ElasticsearchAssertions/org.opensearch.test.hamcrest.OpenSearchAssertions/g;
' "$OUT"
echo "Installed Elassandra single-node test base → $OUT"
