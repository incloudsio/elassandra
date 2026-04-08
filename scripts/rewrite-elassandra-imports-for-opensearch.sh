#!/usr/bin/env bash
# Rewrite org.elasticsearch → org.opensearch for Elassandra side-car Java under the OpenSearch clone.
# Pass 1: ES 6.8 nested metrics packages (metrics.min.*, etc.) → OS 1.3 flat org.opensearch.search.aggregations.metrics.*
# Pass 2: ElasticsearchException, global package rename, TotalHits long → Lucene TotalHits.value (7.x+)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_ROOT="${1:?OpenSearch clone root required}"
MAIN="$OS_ROOT/server/src/main/java/org/elassandra"
TEST="$OS_ROOT/server/src/main/java/org/elassandra"
EXTRA_AGG="$OS_ROOT/server/src/main/java/org/opensearch/search/aggregations/AggregationMetaDataBuilder.java"

"$SCRIPT_DIR/rewrite-engine-java-for-opensearch.sh" "$MAIN"
"$SCRIPT_DIR/rewrite-engine-java-for-opensearch.sh" --file "$EXTRA_AGG"

echo "Rewrote imports under $MAIN (and AggregationMetaDataBuilder if present)"
