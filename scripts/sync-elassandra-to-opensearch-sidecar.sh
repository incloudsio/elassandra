#!/usr/bin/env bash
# Copy org.elassandra sources into an OpenSearch side-car checkout (see server/OPENSEARCH_PORT.md).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OPENSEARCH_CLONE_DIR:-$ROOT/../incloudsio-opensearch}"
SRC_MAIN="$ROOT/server/src/main/java/org/elassandra"
SRC_TEST="$ROOT/server/src/test/java/org/elassandra"
DEST_MAIN="$DEST/server/src/main/java/org/elassandra"
DEST_TEST="$DEST/server/src/test/java/org/elassandra"

if [[ ! -d "$DEST/.git" ]]; then
  echo "OpenSearch clone not found at: $DEST" >&2
  echo "Run: ./scripts/opensearch-port-bootstrap.sh" >&2
  exit 1
fi
if [[ ! -d "$SRC_MAIN" ]]; then
  echo "Missing: $SRC_MAIN" >&2
  exit 1
fi

RSYNC=(rsync -a --delete)
if [[ "${OPENSEARCH_SYNC_DRY_RUN:-}" == "1" ]]; then
  RSYNC=(rsync -a --delete --dry-run)
  echo "[dry-run] target: $DEST"
fi

"${RSYNC[@]}" "$SRC_MAIN/" "$DEST_MAIN/"
if [[ -d "$SRC_TEST" ]]; then
  mkdir -p "$DEST_TEST"
  "${RSYNC[@]}" "$SRC_TEST/" "$DEST_TEST/"
fi

echo "Synced → $DEST_MAIN"
[[ -d "$SRC_TEST" ]] && echo "Synced tests → $DEST_TEST"
echo "Next: ./scripts/rewrite-elassandra-imports-for-opensearch.sh \"$DEST\""
