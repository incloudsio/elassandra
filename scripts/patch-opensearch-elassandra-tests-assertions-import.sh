#!/usr/bin/env bash
# Elassandra tests static-import ElasticsearchAssertions; OpenSearch renamed it to OpenSearchAssertions.
#
# Usage: ./scripts/patch-opensearch-elassandra-tests-assertions-import.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
DIR="$DEST/server/src/test/java/org/elassandra"
[[ -d "$DIR" ]] || exit 0
find "$DIR" -name '*.java' -print0 | xargs -0 perl -i -pe \
  's/org\.opensearch\.test\.hamcrest\.ElasticsearchAssertions/org.opensearch.test.hamcrest.OpenSearchAssertions/g'
echo "Patched ElasticsearchAssertions static imports under $DIR"
