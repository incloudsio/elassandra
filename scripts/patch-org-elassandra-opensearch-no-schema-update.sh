#!/usr/bin/env bash
# Historical compatibility hook: OpenSearch 1.3 originally lacked ClusterStateTaskConfig.SchemaUpdate.
# The sidecar now restores that plumbing, so there is nothing left to strip here.
#
# Usage: ./scripts/patch-org-elassandra-opensearch-no-schema-update.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
echo "SchemaUpdate compatibility hook is now a no-op: $DEST"
