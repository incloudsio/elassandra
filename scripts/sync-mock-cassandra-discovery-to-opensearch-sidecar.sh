#!/usr/bin/env bash
# Install MockCassandraDiscovery under org.elassandra.discovery for OpenSearch side-car main sources.
# See scripts/templates/opensearch-sidecar/MockCassandraDiscovery.java
#
# Usage: ./scripts/sync-mock-cassandra-discovery-to-opensearch-sidecar.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?OpenSearch clone root}"
SRC="$ROOT/scripts/templates/opensearch-sidecar/MockCassandraDiscovery.java"
DST="$DEST/server/src/main/java/org/elassandra/discovery/MockCassandraDiscovery.java"
[[ -f "$SRC" ]] || exit 1
mkdir -p "$(dirname "$DST")"
cp "$SRC" "$DST"
echo "Installed MockCassandraDiscovery → $DST"
