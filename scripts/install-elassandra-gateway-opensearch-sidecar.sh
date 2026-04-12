#!/usr/bin/env bash
# Install Elassandra Gateway (CQL/bootstrap recovery) over stock OpenSearch Gateway.
#
# Usage: ./scripts/install-elassandra-gateway-opensearch-sidecar.sh "${OPENSEARCH_CLONE_DIR}"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?OpenSearch clone root}"
SRC="$ROOT/scripts/templates/opensearch-sidecar/Gateway.java"
DST="$DEST/server/src/main/java/org/opensearch/gateway/Gateway.java"
[[ -f "$SRC" ]] || {
  echo "Missing $SRC" >&2
  exit 1
}
mkdir -p "$(dirname "$DST")"
cp "$SRC" "$DST"
"$ROOT/scripts/rewrite-engine-java-for-opensearch.sh" --file "$DST"
echo "Installed Elassandra Gateway → $DST"
