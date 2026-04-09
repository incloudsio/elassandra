#!/usr/bin/env bash
# Sync Elassandra sources into the OpenSearch side-car and apply all patch scripts (no Gradle).
# Used by opensearch-sidecar-compile-try.sh and opensearch-sidecar-test-try.sh.
#
# Usage: ./scripts/opensearch-sidecar-prepare.sh [OPEN_SEARCH_CLONE_DIR]
#        or OPENSEARCH_CLONE_DIR=... ./scripts/opensearch-sidecar-prepare.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}}"

"$ROOT/scripts/sync-elassandra-to-opensearch-sidecar.sh"
"$ROOT/scripts/sync-elassandra-fork-minimal-to-opensearch-sidecar.sh" "$DEST"
"$ROOT/scripts/sync-elassandra-fork-overlay-to-opensearch-sidecar.sh" "$DEST"
"$ROOT/scripts/sync-elassandra-routing-overlay-to-opensearch-sidecar.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-routing-table-for-os13.sh" "$DEST"
"$ROOT/scripts/rewrite-elassandra-imports-for-opensearch.sh" "$DEST"
if [[ -d "$DEST/server/src/test/java/org/elassandra" ]]; then
  "$ROOT/scripts/rewrite-engine-java-for-opensearch.sh" "$DEST/server/src/test/java/org/elassandra"
  "$ROOT/scripts/patch-opensearch-elassandra-tests-assertions-import.sh" "$DEST"
  "$ROOT/scripts/patch-opensearch-elassandra-tests-opensearch-api.sh" "$DEST"
fi
"$ROOT/scripts/sync-mock-cassandra-discovery-to-opensearch-sidecar.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-applied-cluster-state-transport-handler.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-sourcetoparse-elassandra-token.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-fieldmapper-elassandra-createfield.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-indexmetadata-elassandra-extensions.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-mapperservice-elassandra-extensions.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-elassandra-sidecar-templates.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-documentmapper-elassandra.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-querymanager-opensearch-api.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-querymanager-mapping-lookup.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-querymanager-version-conflict.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-cluster-service-elassandra-cql-process.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-elassandra-primary-first-strategy-node-id.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-metadata-elassandra-extensions.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-cluster-service-elassandra-stubs.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-cluster-service-elassandra-index-settings-keys.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-cluster-service-elassandra-schema-stubs.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-mappers-elassandra-cql-compat.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-discovery-node-elassandra-uuid.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-mapped-field-type-elassandra-cqlvalue.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-range-fieldmapper-elassandra-compat.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-range-fieldmapper-parse-from-elassandra-fork.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-serializer-range-accessors.sh" "$DEST"
"$ROOT/scripts/overlay-elassandra-parsecontext-to-opensearch-sidecar.sh" "$DEST"
"$ROOT/scripts/install-elassandra-cluster-changed-event-opensearch.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-master-service-taskinputs-public.sh" "$DEST"
"$ROOT/scripts/patch-org-elassandra-opensearch-no-schema-update.sh" "$DEST"
"$ROOT/scripts/patch-org-elassandra-opensearch-elastic-secondary.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-engine-delete-by-query.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-engine-elassandra-getresult-factory.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-gateway-service-protected-perform-recovery.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-discovery-module-elassandra.sh" "$DEST"
"$ROOT/scripts/patch-cassandra-discovery-for-opensearch.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-node-elassandra-activate.sh" "$DEST"
"$ROOT/scripts/patch-opensearch-essingle-node-config-override.sh" "$DEST"
if [[ "${SKIP_OPENSEARCH_FORBIDDEN_DEPS_PATCH:-}" != "1" ]]; then
  "$ROOT/scripts/patch-opensearch-forbidden-deps-for-elassandra.sh" "$DEST"
fi

echo "[opensearch-sidecar-prepare] Side-car tree prepared at $DEST"
