#!/usr/bin/env bash
# OpenSearch 1.3 removed ClusterStateTaskConfig.SchemaUpdate and ClusterStateUpdateTask#schemaUpdate().
# Run on the OpenSearch clone **after** rewrite-elassandra-imports-for-opensearch.sh.
#
# Usage: ./scripts/patch-org-elassandra-opensearch-no-schema-update.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
SL="$DEST/server/src/main/java/org/elassandra/cluster/SchemaListener.java"

if [[ -f "$SL" ]]; then
  perl -i -0pe 's/\s*\@Override\s*public\s+SchemaUpdate\s+schemaUpdate\(\)\s*\{\s*return\s+SchemaUpdate\.UPDATE;\s*\}//s' "$SL"
  perl -ni -e 'print unless /^import org\.opensearch\.cluster\.ClusterStateTaskConfig\.SchemaUpdate;/' "$SL"
  echo "Patched SchemaListener (removed schemaUpdate override): $SL"
fi

# Unused import in discovery (would fail compile after rewrite to non-existent type).
CD="$DEST/server/src/main/java/org/elassandra/discovery/CassandraDiscovery.java"
if [[ -f "$CD" ]]; then
  perl -ni -e 'print unless /^import org\.opensearch\.cluster\.ClusterStateTaskConfig\.SchemaUpdate;/' "$CD"
  echo "Stripped stale SchemaUpdate import if present: $CD"
fi
