#!/usr/bin/env bash
# Overlay forked sources needed for :server:compileJava in the OpenSearch side-car:
# - Staged org.opensearch.index.mapper (Elassandra fork)
# - org.opensearch.common.lucene.all.AllEntries
# - org.apache.cassandra.service.ElassandraDaemon (+ small CQL helpers)
# - org.opensearch.index.engine.DeleteByQuery (paired with scripts/patch-opensearch-engine-delete-by-query.sh)
#
# Usage: ./scripts/sync-elassandra-fork-overlay-to-opensearch-sidecar.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:?OpenSearch clone root}"

# Optional: full mapper fork overlay (breaks stock OpenSearch mappers when ES 6.8 APIs diverge).
# Use ./scripts/stage-elassandra-mapper-fork-as-opensearch.sh for a review tree under build/ instead.
if [[ "${ELASSANDRA_OVERLAY_OPENSEARCH_MAPPERS:-}" == "1" ]]; then
  "$SCRIPT_DIR/stage-elassandra-mapper-fork-as-opensearch.sh"
  STAGED="$ROOT/build/elassandra-mapper-staged-opensearch/server/src/main/java/org/opensearch/index/mapper"
  TARGET_MAPPER="$DEST/server/src/main/java/org/opensearch/index/mapper"
  mkdir -p "$TARGET_MAPPER"
  shopt -s nullglob
  for f in "$STAGED"/*.java; do
    cp "$f" "$TARGET_MAPPER/$(basename "$f")"
  done
  shopt -u nullglob
fi

# AllEntries (removed in OpenSearch; Elassandra still references it)
AE_SRC="$ROOT/server/src/main/java/org/elasticsearch/common/lucene/all/AllEntries.java"
AE_DST="$DEST/server/src/main/java/org/opensearch/common/lucene/all/AllEntries.java"
if [[ -f "$AE_SRC" ]]; then
  mkdir -p "$(dirname "$AE_DST")"
  perl -pe 's/^package org\.elasticsearch\.common\.lucene\.all/package org.opensearch.common.lucene.all/' "$AE_SRC" > "$AE_DST"
  echo "Wrote $AE_DST"
fi

# DeleteByQuery top-level (paired with Engine patch in the clone)
DBQ_SRC="$ROOT/server/src/main/java/org/elasticsearch/index/engine/DeleteByQuery.java"
DBQ_DST="$DEST/server/src/main/java/org/opensearch/index/engine/DeleteByQuery.java"
if [[ -f "$DBQ_SRC" ]]; then
  mkdir -p "$(dirname "$DBQ_DST")"
  cp "$DBQ_SRC" "$DBQ_DST"
  "$SCRIPT_DIR/rewrite-engine-java-for-opensearch.sh" --file "$DBQ_DST"
  echo "Wrote $DBQ_DST (rewritten)"
fi

# Minimal IndexSearcherWrapper (OpenSearch removed it; Elassandra TokenRangesSearcherWrapper still extends it)
ISW="$DEST/server/src/main/java/org/opensearch/index/shard/IndexSearcherWrapper.java"
mkdir -p "$(dirname "$ISW")"
cat > "$ISW" << 'EOF'
/*
 * Elassandra side-car stub: OpenSearch 1.3 removed this class; Elassandra still extends it for token-range search wrapping.
 */
package org.opensearch.index.shard;

import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.search.IndexSearcher;

import java.io.IOException;

public class IndexSearcherWrapper {
    protected DirectoryReader wrap(DirectoryReader reader) throws IOException {
        return reader;
    }

    protected IndexSearcher wrap(IndexSearcher searcher) throws IOException {
        return searcher;
    }
}
EOF
echo "Wrote stub $ISW"

# CQL fetch phase (forked from Elasticsearch in Elassandra)
CFP_SRC="$ROOT/server/src/main/java/org/elasticsearch/search/fetch/CqlFetchPhase.java"
CFP_DST="$DEST/server/src/main/java/org/opensearch/search/fetch/CqlFetchPhase.java"
if [[ -f "$CFP_SRC" ]]; then
  mkdir -p "$(dirname "$CFP_DST")"
  cp "$CFP_SRC" "$CFP_DST"
  "$SCRIPT_DIR/rewrite-engine-java-for-opensearch.sh" --file "$CFP_DST"
  echo "Wrote $CFP_DST"
fi

STUB_DAEMON="$ROOT/scripts/templates/ElassandraDaemon-opensearch-sidecar-stub.java"
DAEMON_DST="$DEST/server/src/main/java/org/apache/cassandra/service/ElassandraDaemon.java"
if [[ -f "$STUB_DAEMON" ]]; then
  mkdir -p "$(dirname "$DAEMON_DST")"
  cp "$STUB_DAEMON" "$DAEMON_DST"
  echo "Installed compile-only ElassandraDaemon stub → $DAEMON_DST"
fi

# Optional: full ElassandraDaemon + CQL helpers (expects Elasticsearch 6.8 APIs; use only when porting the bootstrap).
if [[ "${ELASSANDRA_OVERLAY_CASSANDRA_SOURCES:-}" == "1" ]]; then
  for rel in \
    "org/apache/cassandra/service/ElassandraDaemon.java" \
    "org/apache/cassandra/cql3/functions/ToJsonArrayFct.java" \
    "org/apache/cassandra/cql3/functions/ToStringFct.java"; do
    src="$ROOT/server/src/main/java/$rel"
    dst="$DEST/server/src/main/java/$rel"
    if [[ -f "$src" ]]; then
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      echo "Synced $rel"
    fi
  done
fi

echo "Fork overlay complete → $DEST"
