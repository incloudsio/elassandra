#!/usr/bin/env bash
# DiscoveryNode has no uuid() in OpenSearch; use getId() for trace logging (fork parity).
#
# Usage: ./scripts/patch-opensearch-elassandra-primary-first-strategy-node-id.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
PF="$DEST/server/src/main/java/org/elassandra/cluster/routing/PrimaryFirstSearchStrategy.java"
[[ -f "$PF" ]] || exit 0
if grep -q 'node.getId()' "$PF" && ! grep -q 'node.uuid()' "$PF"; then
  echo "PrimaryFirstSearchStrategy already patched: $PF"
  exit 0
fi
perl -i -pe 's/node\.uuid\(\)/node.getId()/g' "$PF"
echo "Patched PrimaryFirstSearchStrategy node.uuid → getId → $PF"
