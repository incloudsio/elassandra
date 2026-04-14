#!/usr/bin/env bash
# Replace OpenSearch stock ClusterChangedEvent with the Elassandra fork (CQL schemaUpdate, mutations, taskInputs),
# then apply org.opensearch rewrites. Run on the OpenSearch clone **after** sync + before :server:compileJava.
#
# Usage: ./scripts/install-elassandra-cluster-changed-event-opensearch.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?OpenSearch clone root}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$ROOT/server/src/main/java/org/elasticsearch/cluster/ClusterChangedEvent.java"
DST="$DEST/server/src/main/java/org/opensearch/cluster/ClusterChangedEvent.java"

if [[ ! -f "$SRC" ]]; then
  echo "Missing Elassandra ClusterChangedEvent: $SRC" >&2
  exit 1
fi

cp "$SRC" "$DST"
"$SCRIPT_DIR/rewrite-engine-java-for-opensearch.sh" --file "$DST"

# Align method names with OpenSearch 1.3 (rewrite handles .metaData() -> .metadata() but not these identifiers).
perl -i -pe '
  s/\bmetaDataChanged\b/metadataChanged/g;
  s/\bchangedCustomMetaDataSet\b/changedCustomMetadataSet/g;
' "$DST"

# Elassandra code still calls metaDataChanged(); keep compatibility with OpenSearch naming.
if ! grep -q 'boolean metaDataChanged()' "$DST"; then
  perl -i -0pe 's/(public boolean metadataChanged\(\) \{\s*return state\.metadata\(\) != previousState\.metadata\(\);\s*\})/$1\n\n    public boolean metaDataChanged() {\n        return metadataChanged();\n    }/s' "$DST"
fi

# The sidecar now restores ClusterStateTaskConfig.SchemaUpdate, so keep the rewritten import from
# the Elassandra source rather than re-declaring a duplicate enum on ClusterChangedEvent.

echo "Installed Elassandra ClusterChangedEvent (rewritten) → $DST"
