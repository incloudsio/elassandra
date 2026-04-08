#!/usr/bin/env bash
# Overlay Elassandra-forked routing types that add ClusterService-aware builders
# (RoutingTable.build(ClusterService, ClusterState), IndexRoutingTable.Builder(..., ClusterService, ...)).
#
# Usage: ./scripts/sync-elassandra-routing-overlay-to-opensearch-sidecar.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:?OpenSearch clone root}"

IRT_SRC="$ROOT/server/src/main/java/org/elasticsearch/cluster/routing/IndexRoutingTable.java"
RT_SRC="$ROOT/server/src/main/java/org/elasticsearch/cluster/routing/RoutingTable.java"
IRT_DST="$DEST/server/src/main/java/org/opensearch/cluster/routing/IndexRoutingTable.java"
RT_DST="$DEST/server/src/main/java/org/opensearch/cluster/routing/RoutingTable.java"

for pair in "$IRT_SRC|$IRT_DST" "$RT_SRC|$RT_DST"; do
  src="${pair%%|*}"
  dst="${pair##*|}"
  if [[ ! -f "$src" ]]; then
    echo "Missing $src" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  "$SCRIPT_DIR/rewrite-engine-java-for-opensearch.sh" --file "$dst"
  echo "Wrote (rewritten) $dst"
done

echo "Routing overlay complete → $DEST"
